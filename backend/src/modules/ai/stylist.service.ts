import {
  automaticOffers,
  automaticPrice,
  effectivePriceSql,
} from '../promotions/automatic-pricing';
import { Injectable } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { isUUID } from 'class-validator';
import { z } from 'zod';
import { PrismaService } from '../../database/prisma.service';
import { AiUsage, Prisma } from '../../generated/prisma/client';
import { GeminiClient } from '../../integrations/ai-providers/gemini.client';
import { fail } from '../../common/errors';
import { catalogInclude, productJson } from '../products/products.service';
import { AiUsageService } from './ai-usage.service';
import { StylistDto } from './dto/stylist.dto';
// Discard every provider field except validated selections, including prose.
const responseSchema = z.object({
  skus: z.array(z.string().min(1).max(150)).min(1).max(4),
});
const receiptSchema = z.object({
  picks: z.array(z.object({ sku: z.string(), price: z.string() })),
  budget: z.number(),
  size: z.string(),
  color: z.string(),
});
@Injectable()
export class StylistService {
  constructor(
    private readonly db: PrismaService,
    private readonly gemini: GeminiClient,
    private readonly usage: AiUsageService,
  ) {}
  async status(userId: string) {
    return {
      stylist: {
        configured: this.gemini.configured,
        model: this.gemini.model,
        ...(await this.usage.status(userId)),
      },
    };
  }
  async create(userId: string, key: string | undefined, dto: StylistDto) {
    if (!key || !isUUID(key, '4'))
      fail(400, 'INVALID_IDEMPOTENCY_KEY', 'Idempotency-Key must be a UUID v4');
    const input = {
      prompt: dto.prompt.trim(),
      size: dto.size.trim(),
      color: dto.color?.trim() ?? '',
      style: dto.style?.trim() ?? '',
      budget: dto.budget,
      consent: true,
    };
    if (!input.prompt || !input.size)
      fail(400, 'INVALID_INPUT', 'Nonempty prompt and size required');
    const hash = createHash('sha256')
      .update(JSON.stringify(input))
      .digest('hex');
    // Existing receipts remain recoverable even if the operator disables Gemini.
    const prior = await this.db.aiUsage.findUnique({
      where: {
        userId_kind_requestKey: { userId, kind: 'STYLIST', requestKey: key },
      },
    });
    if (prior) {
      if (prior.inputHash !== hash)
        fail(
          409,
          'IDEMPOTENCY_CONFLICT',
          'Request key already used with different input',
        );
      return this.get(userId, key);
    }
    if (!this.gemini.configured)
      fail(503, 'AI_PROVIDER_NOT_CONFIGURED', 'Gemini is not configured');
    const offers = await automaticOffers(this.db);
    const candidates = (
      await this.db.productVariant.findMany({
        where: {
          active: true,
          size: input.size,
          ...(input.color ? { color: input.color } : {}),
          id: {
            in: (
              await this.db.$queryRaw<{ id: string }[]>(
                Prisma.sql`SELECT v.id FROM "ProductVariant" v JOIN "Product" p ON p.id=v."productId" JOIN "Inventory" i ON i."variantId"=v.id WHERE v.active=true AND p.active=true AND i.quantity>0 AND v.size=${input.size} AND (${input.color}='' OR v.color=${input.color}) AND ${effectivePriceSql('v')}<=${input.budget} ORDER BY ${effectivePriceSql('v')},v.sku LIMIT 40`,
              )
            ).map((v) => v.id),
          },
          inventory: { quantity: { gt: 0 } },
          product: { active: true },
        },
        include: { product: true },
        orderBy: [{ price: 'asc' }, { sku: 'asc' }],
        take: 40,
      })
    ).map((v) => ({
      ...v,
      price: automaticPrice(v.productId, v.price, offers).price,
    }));
    if (!candidates.length)
      fail(
        409,
        'AI_NO_CATALOG_MATCH',
        'No in-stock catalog items match the requested size, color and budget',
      );
    const reserved = await this.usage.reserve(
      userId,
      'STYLIST',
      key,
      hash,
      this.gemini.model,
    );
    if (!reserved.isNew) return this.present(reserved.row);
    let measured:
      { inputTokens: number | null; outputTokens: number | null } | undefined;
    try {
      const answer = await this.gemini.generateJson(
        JSON.stringify({
          preferences: input,
          catalog: candidates.map((v) => ({
            sku: v.sku,
            productId: v.productId,
            name: v.product.name.slice(0, 160),
            style: v.product.style.slice(0, 80),
            material: v.product.material.slice(0, 120),
            size: v.size,
            color: v.color,
            priceVnd: v.price.toString(),
          })),
        }),
        z.toJSONSchema(responseSchema),
      );
      measured = answer;
      const parsed = responseSchema.safeParse(answer.value);
      if (!parsed.success) throw new Error('INVALID_PROVIDER_OUTPUT');
      const selected = parsed.data.skus.map((sku) =>
        candidates.find((v) => v.sku === sku),
      );
      if (
        selected.some((v) => !v) ||
        new Set(selected.map((v) => v!.productId)).size !== selected.length ||
        selected.reduce((sum, v) => sum + Number(v!.price), 0) > input.budget
      )
        throw new Error('INVALID_PROVIDER_OUTPUT');
      const receipt = {
        picks: selected.map((v) => ({
          sku: v!.sku,
          price: v!.price.toString(),
        })),
        budget: input.budget,
        size: input.size,
        color: input.color,
      };
      await this.resolve(receipt);
      await this.usage.finish(reserved.row.id, 'COMPLETED', receipt, measured);
    } catch (error) {
      const allowed = [
        'INVALID_PROVIDER_OUTPUT',
        'AI_CATALOG_CHANGED',
        'PROVIDER_TIMEOUT',
        'AI_PROVIDER_AUTH',
        'AI_PROVIDER_RATE_LIMIT',
        'AI_PROVIDER_UNAVAILABLE',
      ];
      const code =
        error instanceof Error && allowed.includes(error.message)
          ? error.message
          : 'AI_PROVIDER_UNAVAILABLE';
      await this.usage.finish(
        reserved.row.id,
        code === 'PROVIDER_TIMEOUT' ? 'UNKNOWN' : 'FAILED',
        undefined,
        measured,
        code,
      );
    }
    return this.get(userId, key);
  }
  async get(userId: string, key: string) {
    return this.present(await this.usage.ownedByKey(userId, 'STYLIST', key));
  }
  async latest(userId: string) {
    await this.usage.cleanup();
    const row = await this.db.aiUsage.findFirst({
      where: { userId, kind: 'STYLIST', expiresAt: { gt: new Date() } },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
    });
    return { receipt: row ? await this.present(row) : null };
  }
  private async resolve(receipt: z.infer<typeof receiptSchema>) {
    const rows = await this.db.productVariant.findMany({
      where: {
        sku: { in: receipt.picks.map((p) => p.sku) },
        active: true,
        product: { active: true },
        inventory: { quantity: { gt: 0 } },
      },
      include: { product: { include: catalogInclude } },
    });
    const offers = await automaticOffers(this.db);
    const picks = receipt.picks.map((pick) => {
      const row = rows.find((v) => v.sku === pick.sku);
      if (
        !row ||
        automaticPrice(row.productId, row.price, offers).price.toString() !==
          pick.price ||
        row.size !== receipt.size ||
        (receipt.color && row.color !== receipt.color)
      )
        throw new Error('AI_CATALOG_CHANGED');
      return {
        sku: row.sku,
        price: automaticPrice(
          row.productId,
          row.price,
          offers,
        ).price.toString(),
        product: productJson(row.product, offers),
      };
    });
    const total = picks.reduce(
      (sum, p) => sum.plus(p.price),
      new Prisma.Decimal(0),
    );
    if (total.gt(receipt.budget)) throw new Error('AI_CATALOG_CHANGED');
    return {
      message: `Đã chọn ${picks.length} sản phẩm còn hàng, phù hợp với size và ngân sách của bạn.`,
      picks,
      total: total.toString(),
      currency: 'VND',
    };
  }
  private async present(row: AiUsage) {
    let result: Awaited<ReturnType<StylistService['resolve']>> | null = null;
    let errorCode = row.errorCode;
    if (row.status === 'COMPLETED') {
      const parsed = receiptSchema.safeParse(row.receipt);
      if (row.expiresAt <= new Date() || !parsed.success)
        errorCode = 'AI_RESULT_EXPIRED';
      else {
        try {
          result = await this.resolve(parsed.data);
        } catch {
          errorCode = 'AI_CATALOG_CHANGED';
        }
      }
    }
    return {
      id: row.id,
      requestKey: row.requestKey,
      status: row.status.toLowerCase(),
      errorCode,
      createdAt: row.createdAt,
      estimatedCostVnd: row.estimatedCostVnd.toString(),
      model: row.model,
      result,
    };
  }
}
