import {
  Inject,
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import {
  OperationsResources,
  OPS_RESOURCES,
  operationDeadline,
} from './operations.probes';

@Injectable()
export class WorkerHeartbeat implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(WorkerHeartbeat.name);
  private readonly instanceId = randomUUID();
  private readonly startedAt = new Date().toISOString();
  private timer?: NodeJS.Timeout;
  private active?: Promise<void>;
  private lastValue?: string;
  private stopped = false;
  constructor(
    private readonly config: ConfigService,
    @Inject(OPS_RESOURCES) private readonly resources: OperationsResources,
  ) {}
  async onModuleInit() {
    await this.tick();
    this.timer = setInterval(() => {
      void this.tick();
    }, 10000);
    this.timer.unref();
  }
  private async tick() {
    if (this.stopped || this.active) return;
    this.active = this.write();
    try {
      await this.active;
    } finally {
      this.active = undefined;
    }
  }
  private get key() {
    return `${this.config.getOrThrow<string>('AI_QUEUE_PREFIX')}:monitor:worker`;
  }
  private async write() {
    const client = this.resources.redis(this.config);
    client.on('error', () => undefined);
    const value = JSON.stringify({
      instanceId: this.instanceId,
      startedAt: this.startedAt,
      lastAt: new Date().toISOString(),
    });
    try {
      await operationDeadline(async () => {
        await client.connect();
        await client.set(this.key, value, 'EX', 30);
      });
      this.lastValue = value;
    } catch {
      this.logger.warn('WORKER_HEARTBEAT_UNAVAILABLE');
    } finally {
      client.disconnect();
    }
  }
  async onModuleDestroy() {
    this.stopped = true;
    if (this.timer) clearInterval(this.timer);
    await this.active;
    if (!this.lastValue) return;
    const client = this.resources.redis(this.config);
    client.on('error', () => undefined);
    try {
      await operationDeadline(async () => {
        await client.connect();
        await client.eval(
          "if redis.call('GET', KEYS[1]) == ARGV[1] then return redis.call('DEL', KEYS[1]) else return 0 end",
          1,
          this.key,
          this.lastValue!,
        );
      });
    } catch {
      this.logger.warn('WORKER_HEARTBEAT_CLOSE_UNAVAILABLE');
    } finally {
      client.disconnect();
    }
  }
}
