import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { publicUser } from '../auth/auth.service';
import { AddressDto, ProfileDto, UpdateAddressDto } from './dto/user.dto';
import { transaction, lockUser } from '../../common/transaction';
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
  saveAddress(userId: string, dto: AddressDto | UpdateAddressDto, id?: string) {
    return transaction(this.db, async (tx) => {
      await lockUser(tx, userId);
      if (id && !(await tx.address.findFirst({ where: { id, userId } })))
        throw new NotFoundException();
      if (dto.isDefault)
        await tx.address.updateMany({
          where: { userId, isDefault: true },
          data: { isDefault: false },
        });
      return id
        ? tx.address.update({ where: { id }, data: dto })
        : tx.address.create({ data: { ...(dto as AddressDto), userId } });
    });
  }
  async deleteAddress(userId: string, id: string) {
    const result = await this.db.address.deleteMany({ where: { id, userId } });
    if (!result.count) throw new NotFoundException();
    return { deleted: true };
  }
}
