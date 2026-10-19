import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { lockUser, transaction } from '../../common/transaction';
import { fail } from '../../common/errors';
import { SaveStyleDto } from './dto/style.dto';

const select = {
  size: true,
  style: true,
  color: true,
  budget: true,
  version: true,
} as const;
const defaults = {
  size: 'M',
  style: '',
  color: '',
  budget: '1500000',
  version: 0,
};

@Injectable()
export class StyleService {
  constructor(private readonly db: PrismaService) {}
  async get(userId: string) {
    const row = await this.db.stylePreference.findUnique({
      where: { userId },
      select,
    });
    return row ? { ...row, budget: row.budget.toFixed(0) } : { ...defaults };
  }
  save(userId: string, dto: SaveStyleDto) {
    return transaction(this.db, async (tx) => {
      await lockUser(tx, userId);
      const before = await tx.stylePreference.findUnique({
        where: { userId },
        select: { version: true },
      });
      if ((before?.version ?? 0) !== dto.expectedVersion) {
        fail(
          409,
          'VERSION_CONFLICT',
          'Hồ sơ phong cách đã thay đổi. Hãy tải lại trước khi lưu.',
        );
      }
      const data = {
        size: dto.size,
        style: dto.style,
        color: dto.color,
        budget: dto.budget,
      };
      const row = before
        ? await tx.stylePreference.update({
            where: { userId },
            data: { ...data, version: { increment: 1 } },
            select,
          })
        : await tx.stylePreference.create({
            data: { ...data, userId },
            select,
          });
      return { ...row, budget: row.budget.toFixed(0) };
    });
  }
}
