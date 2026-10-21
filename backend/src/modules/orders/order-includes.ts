// Public tracking intentionally excludes internal actor identifiers.
const publicEvent = { id: true, status: true, note: true, createdAt: true };
export const orderInclude = {
  items: true,
  payment: true,
  history: { select: publicEvent, orderBy: { version: 'asc' as const } },
  shipment: {
    select: {
      id: true,
      carrier: true,
      trackingCode: true,
      status: true,
      createdAt: true,
      events: {
        select: publicEvent,
        orderBy: { orderVersion: 'asc' as const },
      },
    },
  },
};
export const adminOrderInclude = {
  returns: {
    include: { items: true },
    orderBy: [{ createdAt: 'desc' as const }, { id: 'desc' as const }],
  },
  items: true,
  payment: {
    include: {
      settlement: true,
      attempts: { orderBy: { createdAt: 'desc' as const } },
    },
  },
  user: { select: { email: true, name: true } },
  history: { orderBy: { version: 'asc' as const } },
  shipment: {
    include: { events: { orderBy: { orderVersion: 'asc' as const } } },
  },
};
