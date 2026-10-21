import { Inject, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { HeadBucketCommand, S3Client } from '@aws-sdk/client-s3';
import { Client } from 'pg';
import { Socket } from 'node:net';
import Redis from 'ioredis';
import { databaseSchemaReady } from '../../database/schema-readiness';
import { AI_QUEUE } from '../../queues/ai.queue';
import { RECOVERY_QUEUE } from '../recovery/recovery.queue';

export const OPS_RESOURCES = Symbol('OPS_RESOURCES');
export interface OperationsResources {
  database(config: ConfigService): { client: Client; transport: Socket };
  redis(config: ConfigService): Redis;
  storage(config: ConfigService): S3Client;
  socket(): Socket;
}
export const operationsResources: OperationsResources = {
  database(config) {
    const transport = new Socket();
    const url = new URL(config.getOrThrow<string>('DATABASE_URL'));
    url.searchParams.set(
      'options',
      `${url.searchParams.get('options') ?? ''} -c timezone=UTC -c statement_timeout=1000`.trim(),
    );
    return {
      transport,
      client: new Client({
        connectionString: url.toString(),
        stream: () => transport,
        connectionTimeoutMillis: 500,
        query_timeout: 1500,
      }),
    };
  },
  redis(config) {
    return new Redis({
      host: config.getOrThrow<string>('REDIS_HOST'),
      port: config.getOrThrow<number>('REDIS_PORT'),
      connectTimeout: 1000,
      commandTimeout: 1000,
      maxRetriesPerRequest: 0,
      retryStrategy: () => null,
      enableOfflineQueue: false,
      lazyConnect: true,
    });
  },
  storage(config) {
    return new S3Client({
      endpoint: config.getOrThrow<string>('S3_ENDPOINT'),
      region: config.getOrThrow<string>('S3_REGION'),
      forcePathStyle: true,
      maxAttempts: 1,
      credentials: {
        accessKeyId: config.getOrThrow<string>('S3_ACCESS_KEY_ID'),
        secretAccessKey: config.getOrThrow<string>('S3_SECRET_ACCESS_KEY'),
      },
    });
  },
  socket: () => new Socket(),
};
export const operationsResourcesProvider = {
  provide: OPS_RESOURCES,
  useValue: operationsResources,
};

export async function operationDeadline<T>(
  work: () => Promise<T>,
  milliseconds = 2000,
): Promise<T> {
  let deadline: NodeJS.Timeout | undefined;
  try {
    return await Promise.race([
      Promise.resolve().then(work),
      new Promise<never>((_, reject) => {
        deadline = setTimeout(
          () => reject(Error('OPERATION_PROBE_UNAVAILABLE')),
          milliseconds,
        );
      }),
    ]);
  } catch {
    throw Error('OPERATION_PROBE_UNAVAILABLE');
  } finally {
    if (deadline) clearTimeout(deadline);
  }
}

export type ProbeState = { status: 'ok' | 'unavailable' | 'disabled' };
export type OperationsWork = {
  outbox: { pending: number; oldestPendingAt: string | null };
  ai: {
    reserved: number;
    processing: number;
    stale: number;
    todayCount: number;
    todayEstimatedVnd: string;
    dayStartedAt: string;
    failuresSinceAt: string;
    failures: { kind: string; code: string; count: number }[];
  };
  mail: { pending: number; processing: number; failed: number };
  cleanup: { imagesPending: number };
};
export type QueueCounts = {
  waiting: number;
  active: number;
  delayed: number;
  failed: number;
  oldestWaitingAt: string | null;
};
export type WorkerState = {
  status: 'ok' | 'unavailable';
  lastAt: string | null;
};
export type DatabaseProbe = {
  database: { status: 'ok'; schemaReady: boolean; migrations: number | null };
  work: OperationsWork | null;
};
export type RedisProbe = {
  queues: { tryOn: QueueCounts; recovery: QueueCounts | null };
  worker: WorkerState;
};

// Explicit allowlist: a stored error or kind may contain arbitrary old/provider data.
const FAILURE_CODES = [
  'AI_QUEUE_EXPIRED',
  'AI_OUTCOME_UNKNOWN',
  'AI_PROVIDER_NOT_CONFIGURED',
  'AI_GARMENT_UNAVAILABLE',
  'AI_CATALOG_CHANGED',
  'PROVIDER_TIMEOUT',
  'PROVIDER_ABORTED',
  'INVALID_PROVIDER_OUTPUT',
  'AI_PROVIDER_AUTH',
  'AI_PROVIDER_RATE_LIMIT',
  'AI_PROVIDER_UNAVAILABLE',
  'AI_PROVIDER_ERROR',
  'IMAGE_UNAVAILABLE',
  'IMAGE_DELETED',
  'AI_REQUEST_LEGACY',
];

@Injectable()
export class OperationsProbes {
  constructor(
    private readonly config: ConfigService,
    @Inject(OPS_RESOURCES) private readonly resources: OperationsResources,
  ) {}
  async database(): Promise<DatabaseProbe> {
    const { client, transport } = this.resources.database(this.config);
    client.on('error', () => undefined);
    try {
      return await operationDeadline(async () => {
        await client.connect();
        const schemaReady = await databaseSchemaReady(client);
        if (!schemaReady)
          return {
            database: { status: 'ok', schemaReady: false, migrations: null },
            work: null,
          };
        // All identifiers target Prisma's public schema regardless of URL search_path.
        const result = await client.query<{
          migrations: number;
          work: OperationsWork;
        }>(
          `
        WITH failures AS (
          SELECT CASE WHEN kind IN ('TRY_ON','STYLIST') THEN kind ELSE 'OTHER' END AS kind,
            CASE WHEN "errorCode" = ANY($1::text[]) THEN "errorCode" ELSE 'OTHER' END AS code, count(*)::int AS count
          FROM public."AiUsage" WHERE status IN ('FAILED','UNKNOWN') AND "createdAt" >= now() - interval '24 hours'
          GROUP BY 1,2
        )
        SELECT (SELECT count(*)::int FROM public._prisma_migrations WHERE finished_at IS NOT NULL AND rolled_back_at IS NULL) AS migrations,
          jsonb_build_object(
            'outbox', (SELECT jsonb_build_object('pending',count(*)::int,'oldestPendingAt',min("createdAt") AT TIME ZONE 'UTC') FROM public."OutboxEvent" WHERE "publishedAt" IS NULL),
            'ai', (SELECT jsonb_build_object(
              'reserved',count(*) FILTER (WHERE status='RESERVED')::int,
              'processing',count(*) FILTER (WHERE status='PROCESSING')::int,
              'stale',count(*) FILTER (WHERE status IN ('RESERVED','PROCESSING') AND "deadlineAt" < now())::int,
              'todayCount',count(*) FILTER (WHERE "createdAt" >= date_trunc('day',now()))::int,
              'todayEstimatedVnd',COALESCE(sum("estimatedCostVnd") FILTER (WHERE "createdAt" >= date_trunc('day',now())),0)::text,
              'dayStartedAt',date_trunc('day',now()),'failuresSinceAt',now()-interval '24 hours',
              'failures',(SELECT COALESCE(jsonb_agg(f ORDER BY kind,code),'[]') FROM failures f)) FROM public."AiUsage"),
            'mail',(SELECT jsonb_build_object('pending',count(*) FILTER (WHERE status='PENDING')::int,'processing',count(*) FILTER (WHERE status='PROCESSING')::int,'failed',count(*) FILTER (WHERE status='FAILED')::int) FROM public."MailOutbox"),
            'cleanup',(SELECT jsonb_build_object('imagesPending',count(*)::int) FROM public."ImageAsset" WHERE "purgedAt" IS NULL AND ("deletedAt" IS NOT NULL OR "expiresAt" <= now() OR "purgeRetryAt" IS NOT NULL))
          ) AS work`,
          [FAILURE_CODES],
        );
        return {
          database: {
            status: 'ok',
            schemaReady: true,
            migrations: result.rows[0].migrations,
          },
          work: result.rows[0].work,
        };
      });
    } finally {
      transport.destroy();
      // Closing the owned transport interrupts lost replies; do not await a hung close.
      void client.end().catch(() => undefined);
    }
  }
  async redis(): Promise<RedisProbe> {
    const client = this.resources.redis(this.config);
    client.on('error', () => undefined);
    try {
      return await operationDeadline(async () => {
        await client.connect();
        const prefix = this.config.getOrThrow<string>('AI_QUEUE_PREFIX');
        const counts = async (name: string): Promise<QueueCounts> => {
          // BullMQ getJobCounts may RPOP legacy markers. This atomic read must
          // leave all queue state intact and never load private job payloads.
          const values = (await client.eval(
            `
            local p = KEYS[1]
            local waiting = 0
            local oldest = nil
            for _, state in ipairs({'wait','paused'}) do
              local count = redis.call('LLEN',p..state)
              local tail = redis.call('LRANGE',p..state,-2,-1)
              if #tail > 0 and string.sub(tail[#tail],1,2) == '0:' then count = count - 1 end
              waiting = waiting + count
              for i = #tail,1,-1 do
                if string.sub(tail[i],1,2) ~= '0:' then
                  local stamp = tonumber(redis.call('HGET',p..tail[i],'timestamp'))
                  if stamp and (not oldest or stamp < oldest) then oldest = stamp end
                  break
                end
              end
            end
            local priority = redis.call('ZCARD',p..'prioritized')
            if priority > 0 then oldest = nil end
            return {waiting+priority,redis.call('LLEN',p..'active'),redis.call('ZCARD',p..'delayed'),redis.call('ZCARD',p..'failed'),oldest or false}
          `,
            1,
            `${prefix}:${name}:`,
          )) as [number, number, number, number, number | null];
          const oldest = values[4];
          return {
            waiting: values[0],
            active: values[1],
            delayed: values[2],
            failed: values[3],
            oldestWaitingAt:
              oldest !== null &&
              Number.isFinite(oldest) &&
              oldest > 0 &&
              oldest <= Date.now()
                ? new Date(oldest).toISOString()
                : null,
          };
        };
        const [tryOn, recovery, raw] = await Promise.all([
          counts(AI_QUEUE),
          this.config.get('PASSWORD_RECOVERY_ENABLED') === 'true'
            ? counts(RECOVERY_QUEUE)
            : Promise.resolve(null),
          client.get(`${prefix}:monitor:worker`),
        ]);
        return { queues: { tryOn, recovery }, worker: this.worker(raw) };
      });
    } finally {
      client.disconnect();
    }
  }
  private worker(raw: string | null): WorkerState {
    if (raw && raw.length <= 300)
      try {
        const value = JSON.parse(raw) as Record<string, unknown>;
        if (
          typeof value.instanceId === 'string' &&
          /^[0-9a-f-]{36}$/i.test(value.instanceId) &&
          typeof value.startedAt === 'string' &&
          typeof value.lastAt === 'string'
        ) {
          const start = Date.parse(value.startedAt),
            last = Date.parse(value.lastAt),
            now = Date.now();
          if (
            Number.isFinite(start) &&
            Number.isFinite(last) &&
            start <= last &&
            last <= now
          )
            return {
              status: now - last < 30000 ? 'ok' : 'unavailable',
              lastAt: new Date(last).toISOString(),
            };
        }
      } catch {
        /* malformed heartbeat is unavailable, never echoed */
      }
    return { status: 'unavailable', lastAt: null };
  }
  async storage(): Promise<ProbeState> {
    const client = this.resources.storage(this.config),
      controller = new AbortController();
    try {
      await operationDeadline(() =>
        client.send(
          new HeadBucketCommand({
            Bucket: this.config.getOrThrow<string>('S3_BUCKET'),
          }),
          { abortSignal: controller.signal },
        ),
      );
      return { status: 'ok' };
    } finally {
      controller.abort();
      client.destroy();
    }
  }
  async mail(): Promise<ProbeState> {
    if (
      this.config.get('LOCAL_MAIL_ENABLED') !== 'true' &&
      this.config.get('PASSWORD_RECOVERY_ENABLED') !== 'true'
    )
      return { status: 'disabled' };
    const socket = this.resources.socket();
    try {
      await operationDeadline(
        () =>
          new Promise<void>((resolve, reject) => {
            socket.once('error', reject);
            socket.once('connect', resolve);
            socket.connect(
              this.config.getOrThrow<number>('SMTP_PORT'),
              this.config.getOrThrow<string>('SMTP_HOST'),
            );
          }),
        1000,
      );
      return { status: 'ok' };
    } finally {
      socket.destroy();
    }
  }
}
