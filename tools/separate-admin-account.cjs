// Explicit local operator action. Passwords are supplied over stdin, never argv.
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { createRequire } = require('node:module');
const root = path.resolve(__dirname, '..');
const backend = createRequire(path.join(root, 'backend/package.json'));
const argon2 = backend('argon2');
const { transaction, lockUser } = backend('./dist/common/transaction');
const { databaseNow } = backend('./dist/modules/recovery/recovery.service');
const { recordAdminActivity } = backend('./dist/modules/admin/audit');

async function separateAdminAccount(db, input, backup) {
  const email = input.customerEmail?.trim().toLowerCase();
  const username = input.adminUsername?.trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email ?? '') ||
      !/^[a-z0-9][a-z0-9_.-]{2,63}$/.test(username ?? '') ||
      typeof input.adminPassword !== 'string' || !input.adminPassword.length || input.adminPassword.length > 128 ||
      typeof input.customerName !== 'string' || !input.customerName.trim() || input.customerName.length > 100 ||
      typeof backup !== 'function') throw Error('INVALID_SEPARATION_INPUT');
  // Reserved, non-deliverable identifier. Customer recovery never targets staff.
  const adminEmail = `${username}@accounts.wearly.invalid`;
  if (adminEmail === email) throw Error('ACCOUNTS_MUST_BE_DISTINCT');
  const passwordHash = await argon2.hash(input.adminPassword, {
    type: argon2.argon2id, memoryCost: 19456, timeCost: 2, parallelism: 1,
  });
  return transaction(db, async tx => {
    await tx.$queryRaw`SELECT pg_advisory_xact_lock(hashtextextended('staff-administration',0))::text`;
    const candidate = await tx.user.findUnique({ where: { email } });
    if (!candidate) throw Error('CUSTOMER_ACCOUNT_NOT_FOUND');
    await lockUser(tx, candidate.id);
    const customer = await tx.user.findUniqueOrThrow({ where: { id: candidate.id } });
    const admin = await tx.user.findUnique({ where: { username } });
    // Repeat runs never reset either password or modify an unrelated administrator.
    if (customer.active && customer.role === 'CUSTOMER' && admin?.active && admin.role === 'ADMIN' && admin.id !== customer.id && admin.email === adminEmail) {
      return { changed: false, customerId: customer.id, adminId: admin.id, adminUsername: username };
    }
    if (!customer.active || customer.role !== 'ADMIN' || admin?.id !== customer.id ||
        await tx.user.findUnique({ where: { email: adminEmail } })) throw Error('SHARED_ADMIN_IDENTITY_MISMATCH');
    const now = await databaseNow(tx);
    const adminId = randomUUID();
    await backup({ before: customer, newAdminId: adminId, separatedAt: now });
    const updated = await tx.user.update({ where: { id: customer.id }, data: {
      username: `customer-${randomUUID()}`, role: 'CUSTOMER', name: input.customerName.trim(),
      staffVersion: { increment: 1 }, passwordChangedAt: now,
    } });
    await tx.user.create({ data: {
      id: adminId, email: adminEmail, username, name: username, role: 'ADMIN',
      passwordHash, passwordChangedAt: now,
    } });
    await tx.refreshToken.updateMany({ where: { userId: customer.id, revokedAt: null }, data: { revokedAt: now } });
    await tx.passwordResetToken.updateMany({ where: { userId: customer.id, consumedAt: null }, data: { consumedAt: now } });
    await tx.passwordResetCode.updateMany({ where: { userId: customer.id, consumedAt: null }, data: { consumedAt: now } });
    await recordAdminActivity(tx, adminId, 'STAFF_UPDATED', customer.id, { before: customer, after: updated });
    await recordAdminActivity(tx, adminId, 'STAFF_UPDATED', adminId, { after: { role: 'ADMIN', active: true, staffVersion: 0 } });
    return { changed: true, customerId: customer.id, adminId, adminUsername: username };
  });
}
module.exports = { separateAdminAccount };

if (require.main === module) {
  (async () => {
    const [customerEmail, adminUsername, customerName] = process.argv.slice(2);
    const adminPassword = fs.readFileSync(0, 'utf8').replace(/\r?\n$/, '');
    const { ConfigService } = backend('@nestjs/config');
    const { PrismaService } = backend('./dist/database/prisma.service');
    const env = backend('dotenv').parse(fs.readFileSync(path.join(root, 'backend/.env')));
    const db = new PrismaService(new ConfigService(env));
    try {
      const directory = path.join(root, '.tools/account-separation');
      fs.mkdirSync(directory, { recursive: true });
      const result = await separateAdminAccount(db, { customerEmail, adminUsername, customerName, adminPassword }, async snapshot => {
        // Contains the original hash for recovery; stays in the ignored local folder.
        fs.writeFileSync(path.join(directory, `${snapshot.newAdminId}.private.json`), JSON.stringify(snapshot), { flag: 'wx', mode: 0o600 });
      });
      fs.writeFileSync(path.join(directory, 'result.json'), JSON.stringify(result, null, 2));
      console.log(JSON.stringify({ changed: result.changed, distinctAccounts: result.adminId !== result.customerId, adminUsername: result.adminUsername }));
    } finally { await db.$disconnect(); }
  })().catch(() => { console.error('Account separation failed; no credentials logged. No partial transaction committed.'); process.exitCode = 1; });
}
