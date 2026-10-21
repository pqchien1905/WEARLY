import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service';
import { transaction } from '../../common/transaction';
import { fail } from '../../common/errors';
import { recordAdminActivity } from '../admin/audit';
import { adminOrderInclude } from '../orders/order-includes';
import { appendShipmentEvent } from './shipment-transitions';
import { ShipmentEventDto } from './shipments.dto';
import { queueOrderStatus } from '../mail/outbox';
@Injectable()
export class ShipmentsService {
  constructor(private readonly db: PrismaService) {}
  event(actorId: string, id: string, dto: ShipmentEventDto) {
    return transaction(this.db, async (tx) => {
      await tx.$queryRaw`SELECT id FROM "Order" WHERE id=${id}::uuid FOR UPDATE`;
      const order = await tx.order.findUnique({
        where: { id },
        include: adminOrderInclude,
      });
      if (!order) throw new NotFoundException();
      const shipment = order.shipment;
      if (!shipment)
        fail(
          409,
          'SHIPMENT_REQUIRED',
          'Start shipping before adding tracking events',
        );
      const previous = shipment.events.find((e) => e.eventKey === dto.eventKey);
      if (previous) {
        if (previous.status !== dto.status || previous.note !== dto.note)
          fail(
            409,
            'IDEMPOTENCY_CONFLICT',
            'Event key was already used with a different payload',
          );
        return order;
      }
      if (order.status !== 'SHIPPED' || order.version !== dto.expectedVersion)
        fail(
          409,
          'ORDER_STATE_CONFLICT',
          'Order changed; reload before updating shipment',
        );
      const version = order.version + 1;
      await appendShipmentEvent(tx, shipment, {
        status: dto.status,
        orderVersion: version,
        actorId,
        eventKey: dto.eventKey,
        note: dto.note,
      });
      const terminal = dto.status === 'RETURNED' || dto.status === 'DELIVERED';
      await tx.order.update({
        where: { id },
        data: {
          version,
          ...(terminal
            ? { status: dto.status as 'RETURNED' | 'DELIVERED' }
            : {}),
        },
      });
      if (terminal)
        await tx.orderEvent.create({
          data: {
            orderId: id,
            status: dto.status as 'RETURNED' | 'DELIVERED',
            version,
            actorId,
            note: dto.note,
          },
        });
      if (dto.status === 'RETURNED') {
        for (const item of [...order.items].sort((a, b) =>
          a.variantId.localeCompare(b.variantId),
        )) {
          const inventory = await tx.inventory.update({
            where: { variantId: item.variantId },
            data: {
              quantity: { increment: item.quantity },
              version: { increment: 1 },
            },
          });
          await tx.inventoryMovement.create({
            data: {
              inventoryId: inventory.id,
              orderId: id,
              delta: item.quantity,
              reason: 'SHIPMENT_RETURN',
            },
          });
        }
        if (
          order.payment?.provider === 'cod' &&
          order.payment.status === 'PENDING'
        )
          await tx.payment.update({
            where: { id: order.payment.id },
            data: { status: 'CANCELLED' },
          });
      }
      await recordAdminActivity(tx, actorId, 'SHIPMENT_UPDATED', id);
      if (terminal)
        await queueOrderStatus(
          tx,
          id,
          dto.status as 'DELIVERED' | 'RETURNED',
          version,
        );
      return tx.order.findUniqueOrThrow({
        where: { id },
        include: adminOrderInclude,
      });
    });
  }
}
