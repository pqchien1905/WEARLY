import {
  OrderStatus,
  PaymentStatus,
  Prisma,
} from '../../generated/prisma/client';
import { fail } from '../../common/errors';
import { AdminOrdersQueryDto } from './dto/admin-orders-query.dto';

export function orderFilters(q: AdminOrdersQueryDto): Prisma.OrderWhereInput {
  if (q.from && q.to && q.from > q.to)
    fail(
      400,
      'INVALID_DATE_RANGE',
      'Ngày bắt đầu phải trước hoặc bằng ngày kết thúc.',
    );
  const search = (q.q ?? '').replace(/[\\%_]/g, '\\$&');
  const contains = { contains: search, mode: 'insensitive' as const };
  return {
    ...(q.customerId ? { userId: q.customerId } : {}),
    ...(q.from || q.to
      ? {
          createdAt: {
            ...(q.from ? { gte: new Date(`${q.from}T00:00:00+07:00`) } : {}),
            ...(q.to
              ? {
                  lt: new Date(
                    new Date(`${q.to}T00:00:00+07:00`).getTime() + 86400000,
                  ),
                }
              : {}),
          },
        }
      : {}),
    ...(q.provider ? { payment: { provider: q.provider } } : {}),
    ...(q.paymentStatus
      ? {
          AND:
            q.paymentStatus === 'COD_UNSETTLED'
              ? [
                  {
                    status: 'DELIVERED',
                    payment: { provider: 'cod', status: 'PENDING' },
                  },
                ]
              : [{ payment: { status: q.paymentStatus as PaymentStatus } }],
        }
      : {}),
    ...(search
      ? {
          OR: [
            { code: contains },
            { user: { name: contains } },
            { user: { email: contains } },
            ...['recipient', 'phone'].map((field) => ({
              addressSnapshot: {
                path: [field],
                string_contains: search,
                mode: 'insensitive' as const,
              },
            })),
            {
              items: { some: { OR: [{ name: contains }, { sku: contains }] } },
            },
            ...(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
              q.q ?? '',
            )
              ? [{ id: q.q }]
              : []),
          ],
        }
      : {}),
  };
}
export const orderStatusFilter = (status?: string): Prisma.OrderWhereInput =>
  status ? { status: status as OrderStatus } : {};
export function orderSort(
  sort?: string,
): Prisma.OrderOrderByWithRelationInput[] {
  return sort === 'oldest'
    ? [{ createdAt: 'asc' }, { id: 'asc' }]
    : sort === 'total_desc'
      ? [{ total: 'desc' }, { createdAt: 'desc' }, { id: 'desc' }]
      : sort === 'total_asc'
        ? [{ total: 'asc' }, { createdAt: 'desc' }, { id: 'desc' }]
        : [{ createdAt: 'desc' }, { id: 'desc' }];
}
// The list only loads its preview. History, attempts and returns belong to detail.
export const adminOrderListSelect = {
  id: true,
  code: true,
  status: true,
  version: true,
  createdAt: true,
  total: true,
  currency: true,
  addressSnapshot: true,
  user: { select: { name: true, email: true } },
  payment: { select: { provider: true, status: true, amount: true } },
  shipment: { select: { status: true, trackingCode: true } },
  items: {
    take: 1,
    orderBy: { id: 'asc' as const },
    select: { name: true, image: true, quantity: true },
  },
  _count: { select: { items: true } },
} satisfies Prisma.OrderSelect;
