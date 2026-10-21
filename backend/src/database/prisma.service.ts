import { Injectable, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '../generated/prisma/client';
export const DATABASE_SCHEMA = 'public';
@Injectable()
export class PrismaService
  extends PrismaClient
  implements OnModuleInit, OnModuleDestroy
{
  constructor(config: ConfigService) {
    const url = new URL(config.getOrThrow<string>('DATABASE_URL'));
    // pg URL options override the top-level PoolConfig. Append UTC last so every
    // pooled connection uses the same timestamp contract, retaining other options.
    url.searchParams.set(
      'options',
      `${url.searchParams.get('options') ?? ''} -c timezone=UTC`.trim(),
    );
    super({
      adapter: new PrismaPg({
        connectionString: url.toString(),
        max: 10,
        connectionTimeoutMillis: 5000,
        idleTimeoutMillis: 30000,
      }, { schema: DATABASE_SCHEMA }),
    });
  }
  async onModuleInit() {
    await this.$connect();
    await this.$queryRaw`SELECT 1`;
  }
  async onModuleDestroy() {
    await this.$disconnect();
  }
}
