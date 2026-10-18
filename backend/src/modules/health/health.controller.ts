import { Controller, Get, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ApiTags } from '@nestjs/swagger';
import Redis from 'ioredis';
import { PrismaService } from '../../database/prisma.service';
import { Public } from '../../common/decorators/auth';
@Public()
@ApiTags('health')
@Controller('health')
export class HealthController {
  constructor(
    private readonly db: PrismaService,
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
    try {
      await this.db.$queryRaw`SELECT 1`;
      database = true;
    } catch {
      /* reported as unavailable */
    }
    try {
      redis = (await client.ping()) === 'PONG';
    } catch {
      /* reported as unavailable */
    } finally {
      client.disconnect();
    }
    if (!database || !redis)
      throw new ServiceUnavailableException({
        code: 'DEPENDENCY_UNAVAILABLE',
        message: 'Database or Redis is unavailable',
      });
    return { status: 'ready', database, redis };
  }
}
