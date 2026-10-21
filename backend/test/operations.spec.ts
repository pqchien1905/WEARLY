import 'reflect-metadata';
import { ConfigService } from '@nestjs/config';
import { EventEmitter } from 'node:events';
import { OperationsService } from '../src/modules/operations/operations.service';
import {
  OperationsProbes,
  OperationsResources,
} from '../src/modules/operations/operations.probes';
import { WorkerHeartbeat } from '../src/modules/operations/worker-heartbeat.service';

const config = () =>
  new ConfigService({
    DATABASE_URL:
      'postgresql://fixture:private-db-value@localhost:5432/operations_test',
    REDIS_HOST: '127.0.0.1',
    REDIS_PORT: 6379,
    AI_QUEUE_PREFIX: 'operations-unit',
    S3_ENDPOINT: 'http://127.0.0.1:9000',
    S3_REGION: 'us-east-1',
    S3_BUCKET: 'operations-test',
    S3_ACCESS_KEY_ID: 'fixture',
    S3_SECRET_ACCESS_KEY: 'private-storage-value',
    LOCAL_MAIL_ENABLED: 'true',
    PASSWORD_RECOVERY_ENABLED: 'false',
    SMTP_HOST: '127.0.0.1',
    SMTP_PORT: 1025,
    GEMINI_API_KEY: 'private-gemini-value',
    GEMINI_STYLIST_MODEL: 'gemini-fixture-text',
    GEMINI_TRYON_MODEL: 'gemini-fixture-image',
    VNPAY_ENABLED: 'false',
    SHIPPING_PROVIDER: 'local',
  });
const never = () => new Promise<never>(() => undefined);

describe('Bounded private operations diagnostics', () => {
  afterEach(() => jest.useRealTimers());
  it('reports unavailable measurements as null while keeping healthy sections', async () => {
    const probes = {
      database: jest.fn().mockRejectedValue(Error('private-db-value')),
      redis: jest.fn().mockRejectedValue(Error('private-queue-payload')),
      storage: jest.fn().mockResolvedValue({ status: 'ok' }),
      mail: jest.fn().mockResolvedValue({ status: 'disabled' }),
    };
    const result = await new OperationsService(
      config(),
      probes as unknown as OperationsProbes,
    ).snapshot();
    expect(result).toMatchObject({
      database: { status: 'unavailable', schemaReady: null, migrations: null },
      redis: { status: 'unavailable', queues: null },
      worker: { status: 'unavailable', lastAt: null },
      storage: { status: 'ok' },
      mail: { status: 'disabled' },
      work: null,
    });
    expect(JSON.stringify(result)).not.toMatch(
      /private-|postgresql:|localhost:5432/,
    );
    expect(result.providers.gemini).toMatchObject({ configured: true });
    expect(result.providers.vnpay).toMatchObject({ configured: false });
  });
  it('destroys a database transport that accepts a connection but never replies', async () => {
    jest.useFakeTimers();
    const transport = { destroy: jest.fn() },
      client = {
        connect: jest.fn().mockResolvedValue(undefined),
        query: jest.fn(never),
        on: jest.fn(),
        end: jest.fn().mockResolvedValue(undefined),
      };
    const resources = { database: jest.fn(() => ({ client, transport })) };
    const probe = new OperationsProbes(
      config(),
      resources as unknown as OperationsResources,
    ).database();
    const failure = expect(probe).rejects.toThrow(
      'OPERATION_PROBE_UNAVAILABLE',
    );
    await jest.advanceTimersByTimeAsync(2100);
    await failure;
    expect(transport.destroy).toHaveBeenCalledTimes(1);
    expect(client.end).toHaveBeenCalledTimes(1);
  });
  it('disconnects a Redis probe that never becomes ready', async () => {
    jest.useFakeTimers();
    const client = {
      connect: jest.fn(never),
      on: jest.fn(),
      disconnect: jest.fn(),
    };
    const resources = { redis: jest.fn(() => client) };
    const probe = new OperationsProbes(
      config(),
      resources as unknown as OperationsResources,
    ).redis();
    const failure = expect(probe).rejects.toThrow(
      'OPERATION_PROBE_UNAVAILABLE',
    );
    await jest.advanceTimersByTimeAsync(2100);
    await failure;
    expect(client.disconnect).toHaveBeenCalledTimes(1);
  });
  it('aborts stalled private storage checks and destroys the S3 client', async () => {
    jest.useFakeTimers();
    let signal: AbortSignal | undefined;
    const client = {
      send: jest.fn((_command, options) => {
        signal = options.abortSignal;
        return never();
      }),
      destroy: jest.fn(),
    };
    const resources = { storage: jest.fn(() => client) };
    const probe = new OperationsProbes(
      config(),
      resources as unknown as OperationsResources,
    ).storage();
    const failure = expect(probe).rejects.toThrow(
      'OPERATION_PROBE_UNAVAILABLE',
    );
    await jest.advanceTimersByTimeAsync(2100);
    await failure;
    expect(signal?.aborted).toBe(true);
    expect(client.destroy).toHaveBeenCalledTimes(1);
  });
  it('bounds SMTP connection checks and skips them when local mail is disabled', async () => {
    jest.useFakeTimers();
    const socket = Object.assign(new EventEmitter(), {
      connect: jest.fn(),
      destroy: jest.fn(),
    });
    const resources = { socket: jest.fn(() => socket) };
    const settings = config(),
      probes = new OperationsProbes(
        settings,
        resources as unknown as OperationsResources,
      );
    const failure = expect(probes.mail()).rejects.toThrow(
      'OPERATION_PROBE_UNAVAILABLE',
    );
    await jest.advanceTimersByTimeAsync(1100);
    await failure;
    expect(socket.destroy).toHaveBeenCalledTimes(1);
    settings.set('LOCAL_MAIL_ENABLED', 'false');
    expect(await probes.mail()).toEqual({ status: 'disabled' });
    expect(resources.socket).toHaveBeenCalledTimes(1);
  });
});

describe('Worker liveness ownership', () => {
  afterEach(() => jest.useRealTimers());
  it('writes only a bounded namespace heartbeat and compare-deletes its own value', async () => {
    jest.useFakeTimers();
    jest.setSystemTime(new Date('2026-10-22T00:00:00Z'));
    const client = {
      connect: jest.fn().mockResolvedValue(undefined),
      on: jest.fn(),
      set: jest.fn().mockResolvedValue('OK'),
      eval: jest.fn().mockResolvedValue(1),
      disconnect: jest.fn(),
    };
    const resources = { redis: jest.fn(() => client) };
    const heartbeat = new WorkerHeartbeat(
      config(),
      resources as unknown as OperationsResources,
    );
    await heartbeat.onModuleInit();
    expect(client.set).toHaveBeenCalledTimes(1);
    const [key, value, expiry, ttl] = client.set.mock.calls[0];
    expect(key).toBe('operations-unit:monitor:worker');
    expect(expiry).toBe('EX');
    expect(ttl).toBe(30);
    expect(JSON.parse(value)).toEqual({
      instanceId: expect.any(String),
      startedAt: '2026-10-22T00:00:00.000Z',
      lastAt: '2026-10-22T00:00:00.000Z',
    });
    expect(value).not.toContain('private-');
    await jest.advanceTimersByTimeAsync(10000);
    expect(client.set).toHaveBeenCalledTimes(2);
    await heartbeat.onModuleDestroy();
    expect(client.eval.mock.calls[0][0]).toMatch(/GET/);
    expect(client.eval.mock.calls[0][0]).toMatch(/DEL/);
    expect(client.eval.mock.calls[0].slice(1)).toEqual([
      1,
      key,
      client.set.mock.calls[1][1],
    ]);
    await jest.advanceTimersByTimeAsync(30000);
    expect(client.set).toHaveBeenCalledTimes(2);
  });
});
