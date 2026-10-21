import { Controller, Get, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ApiTags } from '@nestjs/swagger';
import Redis from 'ioredis';
import { Client } from 'pg';
import { Socket } from 'node:net';
import { databaseSchemaReady } from '../../database/schema-readiness';
import { Public } from '../../common/decorators/auth';
@Public()
@ApiTags('health')
@Controller('health')
export class HealthController {
  constructor(
    private readonly config: ConfigService,
  ) {}
  @Get() live() {
    return { status: 'ok', service: 'wearly-api' };
  }
  @Get('ready') async ready() {
    let database = false,
      redis = false;
    const client = new Redis({
      host: this.config.getOrThrow<string>('REDIS_HOST'),
      port: this.config.getOrThrow<number>('REDIS_PORT'),
      connectTimeout: 1000,
      commandTimeout: 1000,
      maxRetriesPerRequest: 0,
      retryStrategy: () => null,
      lazyConnect: true,
    });
    client.on('error', () => undefined);
    // Own the probe transport: a lost reply must not occupy the business pool.
    const transport = new Socket();
    const url = new URL(this.config.getOrThrow<string>('DATABASE_URL'));
    url.searchParams.set('options', `${url.searchParams.get('options') ?? ''} -c statement_timeout=1000`.trim());
    const probe = new Client({
      connectionString: url.toString(),
      stream: () => transport,
      connectionTimeoutMillis: 500,
      query_timeout: 1200,
    });
    probe.on('error', () => undefined);
    let deadline: NodeJS.Timeout | undefined;
    try {
      const checks = await Promise.race([
        Promise.allSettled([
          probe.connect().then(() => databaseSchemaReady(probe)),
          client.ping().then((value) => value === 'PONG'),
        ]),
        new Promise<never>((_, reject) => {
          deadline = setTimeout(() => reject(new Error('Readiness deadline')), 1500);
        }),
      ]);
      database = checks[0].status === 'fulfilled' && checks[0].value;
      redis = checks[1].status === 'fulfilled' && checks[1].value;
    } catch {
      /* reported as unavailable */
    } finally {
      if (deadline) clearTimeout(deadline);
      client.disconnect();
      // This also interrupts connection/authentication and any lost query reply.
      transport.destroy();
      await probe.end().catch(() => undefined);
    }
    if (!database || !redis)
      throw new ServiceUnavailableException({
        code: 'DEPENDENCY_UNAVAILABLE',
        message: 'Required database schema or service is unavailable',
      });
    return { status: 'ready', database, redis };
  }
}
