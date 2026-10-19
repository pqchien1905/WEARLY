import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { publicUser } from '../auth/auth.service';
import { AddressDto, ProfileDto, UpdateAddressDto } from './dto/user.dto';
import { transaction, lockUser } from '../../common/transaction';
import { createHash } from 'node:crypto';
import { fail } from '../../common/errors';
@Injectable()
export class UsersService {
  constructor(private readonly db: PrismaService) {}
  async me(id: string) {
    return publicUser(await this.db.user.findUniqueOrThrow({ where: { id } }));
  }
  async update(id: string, dto: ProfileDto) {
    return publicUser(await this.db.user.update({ where: { id }, data: dto }));
  }
  addresses(userId: string) {
    return this.db.address.findMany({
      where: { userId },
      orderBy: [{ isDefault: 'desc' }, { createdAt: 'asc' }],
    });
  }
  saveAddress(
    userId: string,
    dto: AddressDto | UpdateAddressDto,
    id?: string,
    key?: string,
  ) {
    if (key !== undefined && !/^[A-Za-z0-9_-]{16,128}$/.test(key)) {
      fail(400, 'INVALID_IDEMPOTENCY_KEY', 'Mã yêu cầu không hợp lệ.');
    }
    const requestHash =
      key === undefined
        ? undefined
        : createHash('sha256')
            .update(
              JSON.stringify([
                dto.recipient,
                dto.phone,
                dto.address,
                dto.label ?? 'Nhà',
                dto.isDefault ?? false,
              ]),
            )
            .digest('hex');
    return transaction(this.db, async (tx) => {
      await lockUser(tx, userId);
      if (!id && key !== undefined) {
        const receipt = await tx.addressCreateReceipt.findUnique({
          where: { userId_key: { userId, key } },
          include: { address: true },
        });
        if (receipt) {
          if (receipt.requestHash !== requestHash)
            fail(
              409,
              'IDEMPOTENCY_CONFLICT',
              'Mã yêu cầu đã dùng cho nội dung khác.',
            );
          if (!receipt.address)
            fail(
              410,
              'ADDRESS_REMOVED',
              'Địa chỉ của yêu cầu này đã bị xóa. Hãy mở lại sổ địa chỉ.',
            );
          return receipt.address;
        }
      }
      if (id && !(await tx.address.findFirst({ where: { id, userId } })))
        throw new NotFoundException();
      if (dto.isDefault)
        await tx.address.updateMany({
          where: { userId, isDefault: true },
          data: { isDefault: false },
        });
      if (id) return tx.address.update({ where: { id }, data: dto });
      const address = await tx.address.create({
        data: { ...(dto as AddressDto), userId },
      });
      if (key !== undefined)
        await tx.addressCreateReceipt.create({
          data: {
            userId,
            key,
            requestHash: requestHash!,
            addressId: address.id,
          },
        });
      return address;
    });
  }
  async deleteAddress(userId: string, id: string) {
    const result = await this.db.address.deleteMany({ where: { id, userId } });
    if (!result.count) throw new NotFoundException();
    return { deleted: true };
  }
}
