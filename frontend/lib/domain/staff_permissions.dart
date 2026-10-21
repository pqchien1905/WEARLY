const staffRoles = ['ADMIN', 'MANAGER', 'WAREHOUSE', 'SUPPORT'];
const staffRoleNames = {
  'CUSTOMER': 'Khách hàng',
  'ADMIN': 'Quản trị viên',
  'MANAGER': 'Quản lý',
  'WAREHOUSE': 'Kho',
  'SUPPORT': 'Hỗ trợ',
};
const _capabilities = {
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
  'promotions.manage',
  'content.manage',
  'support.manage',
  'mail.read',
  'staff.manage',
};
bool isStaff(String? role) => staffRoles.contains(role);
bool canStaff(String? role, String capability) => switch (role) {
  'ADMIN' => _capabilities.contains(capability),
  'MANAGER' =>
    _capabilities.contains(capability) && capability != 'staff.manage',
  'WAREHOUSE' => const {
    'inventory.read',
    'inventory.write',
    'orders.read',
    'orders.fulfill',
    'returns.receive',
  }.contains(capability),
  'SUPPORT' => const {'orders.read', 'support.manage'}.contains(capability),
  _ => false,
};
String staffHome(String? role) => switch (role) {
  'WAREHOUSE' => '/admin/inventory',
  'SUPPORT' => '/admin/support',
  _ => '/admin',
};
bool canVisitAdmin(String? role, String path) {
  if (path == '/admin') return canStaff(role, 'reports.read');
  final parts = path.split('/');
  if (parts.length < 3) return false;
  final capability = switch (parts[2]) {
    'products' => parts.length > 3 ? 'catalog.write' : 'catalog.read',
    'categories' || 'brands' => 'catalog.write',
    'inventory' => 'inventory.read',
    'orders' => 'orders.read',
    'customers' => 'customers.read',
    'promotions' => 'promotions.manage',
    'content' => 'content.manage',
    'support' => 'support.manage',
    'mail' => 'mail.read',
    'staff' || 'settings' || 'ai-monitoring' => 'staff.manage',
    _ => null,
  };
  return capability != null && canStaff(role, capability);
}
