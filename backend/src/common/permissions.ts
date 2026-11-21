export const capabilities = [
  'reports.read',
  'audit.read',
  'catalog.read',
  'catalog.write',
  'inventory.read',
  'inventory.write',
  'orders.read',
  'orders.fulfill',
  'orders.cancel',
  'payments.manage',
  'returns.decide',
  'returns.receive',
  'customers.read',
  'customers.manage',
  'promotions.manage',
  'content.manage',
  'support.manage',
  'mail.read',
  'staff.manage',
] as const;
export type Capability = (typeof capabilities)[number];
const permissions: Record<string, readonly Capability[]> = {
  ADMIN: capabilities,
  MANAGER: capabilities.filter((p) => p !== 'staff.manage'),
  WAREHOUSE: [
    'inventory.read',
    'inventory.write',
    'orders.read',
    'orders.fulfill',
    'returns.receive',
  ],
  SUPPORT: ['orders.read', 'support.manage'],
  CUSTOMER: [],
};
export const can = (role: string, capability: Capability): boolean =>
  permissions[role]?.includes(capability) ?? false;
export const isStaff = (role: string): boolean =>
  ['ADMIN', 'MANAGER', 'WAREHOUSE', 'SUPPORT'].includes(role);
