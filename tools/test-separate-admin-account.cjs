const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID, createHash } = require('node:crypto');
const backend = require('node:module').createRequire(path.resolve(__dirname, '../backend/package.json'));
const { separateAdminAccount } = require('./separate-admin-account.cjs');
const { PrismaService } = backend('./dist/database/prisma.service');
const { ConfigService } = backend('@nestjs/config');
const argon2 = backend('argon2');
const env = backend('dotenv').parse(fs.readFileSync(path.resolve(__dirname, '../backend/.env.test')));
if (!new URL(env.TEST_DATABASE_URL).pathname.endsWith('_test')) throw Error('Dedicated _test database required');
const db = new PrismaService(new ConfigService({ DATABASE_URL: env.TEST_DATABASE_URL }));
(async () => {
  const username = `split-${randomUUID()}`, email = `${username}@example.test`;
  const adminEmail = `${username}@accounts.wearly.invalid`;
  const createdIds = [];
  let snapshots = 0;
  const customerPassword = 'Customer-keeps-this-password-2026', adminPassword = 'Separate-admin-password-2026';
  try {
    const original = await db.user.create({ data: { username, email, name: 'Shared', role: 'ADMIN', passwordHash: await argon2.hash(customerPassword) } });
    createdIds.push(original.id);
    const address = await db.address.create({ data: { userId: original.id, recipient: 'Customer', phone: '0900000000', address: 'Test address' } });
    const cart = await db.cart.create({ data: { userId: original.id } });
    const session = await db.refreshToken.create({ data: { userId: original.id, tokenHash: randomUUID(), familyId: randomUUID(), expiresAt: new Date(Date.now()+60000) } });
    const token = await db.passwordResetToken.create({ data: { userId: original.id, tokenHash: createHash('sha256').update(randomUUID()).digest('hex'), expiresAt: new Date(Date.now()+60000) } });
    const code = await db.passwordResetCode.create({ data: { userId: original.id, codeHash: 'a'.repeat(64), requestedAt: new Date(), expiresAt: new Date(Date.now()+60000) } });
    const input = { customerEmail: email, customerName: 'Customer', adminUsername: username, adminPassword };
    const backup = async snapshot => { assert.equal(snapshot.before.passwordHash, original.passwordHash); snapshots++; };
    // A conflicting staff identity must leave the original account completely intact.
    const collision = await db.user.create({ data: { email: adminEmail, name: 'Existing account', passwordHash: original.passwordHash } });
    createdIds.push(collision.id);
    await assert.rejects(separateAdminAccount(db, input, backup), /SHARED_ADMIN_IDENTITY_MISMATCH/);
    assert.deepEqual(await db.user.findUnique({ where: { id: original.id } }), original);
    await db.user.delete({ where: { id: collision.id } });
    const result = await separateAdminAccount(db, input, backup);
    createdIds.push(result.adminId);
    assert.equal(result.changed, true); assert.equal(snapshots, 1);
    assert.equal(result.customerId, original.id); assert.notEqual(result.adminId, original.id);
    const customer = await db.user.findUniqueOrThrow({ where: { id: original.id } });
    const admin = await db.user.findUniqueOrThrow({ where: { id: result.adminId } });
    assert.equal(customer.email, email); assert.equal(customer.role, 'CUSTOMER'); assert.equal(customer.passwordHash, original.passwordHash);
    assert.equal(admin.username, username); assert.equal(admin.role, 'ADMIN');
    assert(await argon2.verify(admin.passwordHash, adminPassword));
    assert.equal(await argon2.verify(admin.passwordHash, customerPassword), false);
    assert.deepEqual(await db.address.findUnique({ where: { id: address.id } }), address);
    assert.deepEqual(await db.cart.findUnique({ where: { id: cart.id } }), cart);
    assert((await db.refreshToken.findUnique({ where: { id: session.id } })).revokedAt);
    assert((await db.passwordResetToken.findUnique({ where: { id: token.id } })).consumedAt);
    assert((await db.passwordResetCode.findUnique({ where: { id: code.id } })).consumedAt);
    const repeat = await separateAdminAccount(db, {...input, adminPassword: 'Do-not-overwrite-password'}, backup);
    assert.equal(repeat.changed, false); assert.equal(snapshots, 1);
    assert.equal((await db.user.findUnique({ where: { id: admin.id } })).passwordHash, admin.passwordHash);
    console.log('PASS separate accounts: collision rollback, preserved customer password/address/cart, independent admin password, revoked old sessions/grants, idempotent repeat.');
  } finally {
    await db.adminAuditEvent.deleteMany({ where: { actorId: { in: createdIds } } });
    await db.user.deleteMany({ where: { id: { in: createdIds } } });
    await db.$disconnect();
  }
})().catch(error => { console.error(error.name + ': account separation verification failed'); process.exitCode=1; });
