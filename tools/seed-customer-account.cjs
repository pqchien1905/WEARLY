// Explicit local data preparation. Never resets credentials, clears the cart,
// sends mail, or invokes a payment/AI provider. Stable keys make repeats a no-op.
const fs = require('node:fs');
const path = require('node:path');
const { createHash, randomUUID } = require('node:crypto');
const { createRequire } = require('node:module');
const root = path.resolve(__dirname, '..');
const backend = createRequire(path.join(root, 'backend/package.json'));
const { transaction, lockUser } = backend('./dist/common/transaction');
const prefix = 'account-sample-v1';

function localDatabase() {
  const env = backend('dotenv').parse(fs.readFileSync(path.join(root, 'backend/.env')));
  const host = new URL(env.DATABASE_URL).hostname;
  if (env.NODE_ENV === 'production' || !['localhost', '127.0.0.1', '[::1]'].includes(host)) {
    throw Error('Sample data is restricted to the local development database.');
  }
  const { ConfigService } = backend('@nestjs/config');
  const { PrismaService } = backend('./dist/database/prisma.service');
  return new PrismaService(new ConfigService(env));
}

async function seedCustomerAccount(db, email) {
  return transaction(db, async tx => {
    const user = await tx.user.findUnique({ where: { email } });
    if (!user?.active || user.role !== 'CUSTOMER') throw Error('An active existing customer is required.');
    await lockUser(tx, user.id);
    const before = {
      orders: await tx.order.count({ where: { userId: user.id } }),
      reviews: await tx.review.count({ where: { userId: user.id } }),
      wishlist: await tx.wishlistItem.count({ where: { userId: user.id } }),
    };
    const products = await tx.product.findMany({
      where: { active: true, images: { some: {} }, variants: { some: { active: true, size: 'M', inventory: { quantity: { gte: 6 } } } } },
      orderBy: [{ tryOnSupported: 'desc' }, { slug: 'asc' }], take: 6,
      include: { images: { orderBy: { position: 'asc' }, take: 1 }, variants: { where: { active: true, size: 'M', inventory: { quantity: { gte: 6 } } }, orderBy: { sku: 'asc' }, take: 1, include: { inventory: true } } },
    });
    if (products.length < 4) throw Error('At least four available, illustrated clothing products are required.');
    let addresses = await tx.address.findMany({ where: { userId: user.id }, orderBy: [{ isDefault: 'desc' }, { createdAt: 'asc' }] });
    const sampleLabel = 'Văn phòng';
    if (addresses.length < 5 && !addresses.some(a => a.label === sampleLabel)) {
      await tx.address.create({ data: {
        userId: user.id, label: sampleLabel, recipient: user.name,
        phone: user.phone || '0900000000',
        address: 'Tầng 2, đường Nguyễn Văn Cừ, Vinh',
        isDefault: addresses.length === 0,
      } });
      addresses = await tx.address.findMany({ where: { userId: user.id }, orderBy: [{ isDefault: 'desc' }, { createdAt: 'asc' }] });
    }
    const address = addresses[0];
    await tx.stylePreference.upsert({ where: { userId: user.id }, update: {}, create: {
      userId: user.id, size: 'M', style: 'Tối giản', color: 'Trắng', budget: '1500000',
    } });
    for (const product of products) {
      if (await tx.wishlistItem.count({ where: { userId: user.id } }) >= 200) break;
      await tx.wishlistItem.upsert({ where: { userId_productId: { userId: user.id, productId: product.id } }, update: {}, create: { userId: user.id, productId: product.id } });
    }
    const definitions = [
      { key: 'pending', states: ['PENDING'], days: 1, products: [products[2]] },
      { key: 'shipping', states: ['PENDING', 'CONFIRMED', 'SHIPPED'], days: 4, products: [products[3]] },
      { key: 'delivered', states: ['PENDING', 'CONFIRMED', 'SHIPPED', 'DELIVERED'], days: 8, products: products.slice(0, 2) },
    ];
    const orders = [];
    for (const definition of definitions) {
      const idempotencyKey = `${prefix}-${definition.key}`;
      const previous = await tx.order.findUnique({ where: { userId_idempotencyKey: { userId: user.id, idempotencyKey } }, include: { shipment: true } });
      if (previous) {
        // Repair the initial fixture format without relaxing the shipping API
        // contract or changing any real customer shipment.
        if (previous.addressSnapshot?.sampleData === true && previous.shipment?.trackingCode.startsWith('SAMPLE-')) {
          await tx.shipment.update({ where: { id: previous.shipment.id }, data: { trackingCode: `LOCAL-${randomUUID().toUpperCase()}` } });
        }
        orders.push({ id: previous.id, status: previous.status, created: false }); continue;
      }
      const createdAt = new Date(Date.now() - definition.days * 86400000);
      const dateAt = index => new Date(createdAt.getTime() + index * 3600000);
      const subtotal = definition.products.reduce((total, p) => total + BigInt(p.variants[0].price.toString()), 0n);
      const shipping = subtotal >= 1500000n ? 0n : 30000n;
      const status = definition.states.at(-1), version = definition.states.length - 1;
      const order = await tx.order.create({ data: {
        userId: user.id, idempotencyKey,
        requestHash: createHash('sha256').update(idempotencyKey).digest('hex'),
        addressSnapshot: { recipient: address.recipient, phone: address.phone, address: address.address, sampleData: true },
        subtotal: subtotal.toString(), shipping: shipping.toString(), total: (subtotal + shipping).toString(),
        shippingMethod: 'standard', status, version, createdAt, updatedAt: dateAt(version),
        items: { create: definition.products.map(p => ({
          variantId: p.variants[0].id, name: p.name, sku: p.variants[0].sku, slug: p.slug,
          size: p.variants[0].size, color: p.variants[0].color, image: p.images[0].url,
          unitPrice: p.variants[0].price, quantity: 1, createdAt,
        })) },
        payment: { create: { provider: 'cod', status: 'PENDING', amount: (subtotal + shipping).toString(), createdAt } },
        history: { create: definition.states.map((state, index) => ({
          status: state, version: index, actorId: user.id, createdAt: dateAt(index),
          note: { PENDING: 'Đơn hàng đã được tiếp nhận.', CONFIRMED: 'Cửa hàng đã xác nhận và chuẩn bị sản phẩm.', SHIPPED: 'Đơn hàng đã được bàn giao để vận chuyển.', DELIVERED: 'Đơn hàng đã được giao đến người nhận.' }[state],
        })) },
        ...(version >= 2 ? { shipment: { create: {
          carrier: 'local_simulator', trackingCode: `LOCAL-${randomUUID().toUpperCase()}`,
          status: status === 'DELIVERED' ? 'DELIVERED' : 'IN_TRANSIT', createdAt: dateAt(2),
          events: { create: definition.states.slice(2).map((state, index) => ({
            eventKey: randomUUID(), status: state === 'DELIVERED' ? 'DELIVERED' : 'IN_TRANSIT',
            orderVersion: index + 2, actorId: user.id, createdAt: dateAt(index + 2),
            note: state === 'DELIVERED' ? 'Đã hoàn tất giao hàng.' : 'Đơn hàng đang trên đường đến địa chỉ nhận.',
          })) },
        } } } : {}),
      } });
      // Maintain the inventory ledger: cancelling a sample order can restore only
      // stock that was actually reserved here. No independent phantom order rows.
      for (const p of [...definition.products].sort((a,b) => a.variants[0].id.localeCompare(b.variants[0].id))) {
        const variant = p.variants[0];
        const changed = await tx.inventory.updateMany({ where: { variantId: variant.id, quantity: { gte: 1 } }, data: { quantity: { decrement: 1 }, version: { increment: 1 } } });
        if (changed.count !== 1) throw Error('Inventory changed while preparing samples.');
        await tx.inventoryMovement.create({ data: { inventoryId: variant.inventory.id, delta: -1, reason: 'SAMPLE_ORDER', orderId: order.id, createdAt } });
      }
      orders.push({ id: order.id, status: order.status, created: true });
    }
    const delivered = await tx.order.findUnique({ where: { userId_idempotencyKey: { userId: user.id, idempotencyKey: `${prefix}-delivered` } }, include: { items: { include: { variant: true } } } });
    if (delivered?.status === 'DELIVERED') for (const [index, item] of delivered.items.entries()) {
      await tx.review.upsert({ where: { userId_productId: { userId: user.id, productId: item.variant.productId } }, update: {}, create: {
        userId: user.id, productId: item.variant.productId, rating: index === 0 ? 5 : 4,
        comment: index === 0 ? 'Thiết kế thanh lịch, dễ phối cùng các trang phục hằng ngày.' : 'Kiểu dáng đơn giản, màu sắc dễ kết hợp.',
      } });
    }
    const after = {
      orders: await tx.order.count({ where: { userId: user.id } }),
      reviews: await tx.review.count({ where: { userId: user.id } }),
      wishlist: await tx.wishlistItem.count({ where: { userId: user.id } }),
      addresses: addresses.length,
    };
    return { userId: user.id, email, before, after, orders, products: products.map(p => ({ id: p.id, name: p.name, slug: p.slug, sku: p.variants[0].sku, tryOnSupported: p.tryOnSupported })), samplePrefix: prefix };
  });
}

module.exports = { localDatabase, seedCustomerAccount };
if (require.main === module) (async () => {
  const email = process.argv[2]?.trim().toLowerCase();
  if (!email) throw Error('Usage: node tools/seed-customer-account.cjs customer-email');
  const db = localDatabase();
  try {
    const result = await seedCustomerAccount(db, email);
    const folder = path.join(root, '.tools/customer-account');
    fs.mkdirSync(folder, { recursive: true });
    fs.writeFileSync(path.join(folder, 'seed-result.json'), JSON.stringify(result, null, 2));
    console.log(JSON.stringify(result, null, 2));
  } finally { await db.$disconnect(); }
})().catch(error => { console.error(error.code || error.message); process.exitCode = 1; });
