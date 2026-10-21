import { randomUUID } from 'node:crypto';
import { Prisma, ShipmentStatus } from '../../generated/prisma/client';
import { fail } from '../../common/errors';

const allowed: Record<ShipmentStatus, ShipmentStatus[]> = {
  IN_TRANSIT: ['OUT_FOR_DELIVERY', 'DELIVERY_FAILED', 'DELIVERED'],
  OUT_FOR_DELIVERY: ['DELIVERY_FAILED', 'DELIVERED'],
  DELIVERY_FAILED: ['IN_TRANSIT', 'RETURNED'],
  DELIVERED: [],
  RETURNED: [],
};
export async function appendShipmentEvent(
  tx: Prisma.TransactionClient,
  shipment: { id: string; status: ShipmentStatus },
  data: {
    status: ShipmentStatus;
    orderVersion: number;
    actorId: string;
    eventKey: string;
    note: string;
  },
) {
  if (!allowed[shipment.status].includes(data.status))
    fail(409, 'SHIPMENT_STATE_CONFLICT', 'Shipment transition is invalid');
  await tx.shipment.update({
    where: { id: shipment.id },
    data: { status: data.status },
  });
  await tx.shipmentEvent.create({ data: { shipmentId: shipment.id, ...data } });
}

/** Called under the order lock, in the same transaction as its status update. */
export async function recordFulfillment(
  tx: Prisma.TransactionClient,
  orderId: string,
  status: 'CONFIRMED' | 'SHIPPED' | 'DELIVERED',
  version: number,
  actorId: string,
) {
  if (status === 'SHIPPED')
    await tx.shipment.create({
      data: {
        orderId,
        trackingCode: 'LOCAL-' + randomUUID().toUpperCase(),
        events: {
          create: {
            eventKey: randomUUID(),
            status: 'IN_TRANSIT',
            orderVersion: version,
            actorId,
          },
        },
      },
    });
  if (status === 'DELIVERED') {
    const shipment = await tx.shipment.findUnique({ where: { orderId } });
    if (shipment)
      await appendShipmentEvent(tx, shipment, {
        status,
        orderVersion: version,
        actorId,
        eventKey: randomUUID(),
        note: '',
      });
  }
  await tx.orderEvent.create({ data: { orderId, status, version, actorId } });
}
