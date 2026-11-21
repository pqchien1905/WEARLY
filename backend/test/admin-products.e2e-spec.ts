import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/database/prisma.service';

describe('Products workspace with PostgreSQL', () => {
  let app: INestApplication,
    db: PrismaService,
    categoryId: string,
    brandId: string;
  const marker = randomUUID(),
    users: string[] = [],
    products: string[] = [],
    tokens: Record<string, string> = {},
    userIds: Record<string, string> = {};
  const call = (
    method: 'get' | 'post' | 'patch' | 'delete',
    path: string,
    role = 'ADMIN',
  ) =>
    request(app.getHttpServer())
      [method]('/api/v1/' + path)
      .auth(tokens[role], { type: 'bearer' });
  const input = (slug: string) => ({
    slug: `products-${marker}-${slug}`,
    name: `Sản phẩm ${slug} ${marker}`,
    description: 'Mô tả',
    material: 'Cotton',
    style: 'Casual',
    categoryId,
    brandId,
    active: false,
    images: [{ url: 'assets/images/shirt.jpg', alt: 'Ảnh sản phẩm' }],
  });
  const read = async (id: string) =>
    (await call('get', `admin/products/${id}`).expect(200)).body;
  beforeAll(async () => {
    if (!new URL(process.env.TEST_DATABASE_URL!).pathname.endsWith('_test'))
      throw Error('Isolated test database required');
    const module = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = module.createNestApplication({ logger: false });
    configureApp(app);
    await app.init();
    db = app.get(PrismaService);
    for (const role of [
      'ADMIN',
      'MANAGER',
      'WAREHOUSE',
      'SUPPORT',
      'CUSTOMER',
    ] as const) {
      const r = await request(app.getHttpServer())
        .post('/api/v1/auth/register')
        .send({
          email: `products-${role}-${marker}@example.test`,
          name: role,
          password: 'Products-fixture-2026',
        })
        .expect(201);
      users.push(r.body.user.id);
      userIds[role] = r.body.user.id;
      tokens[role] = r.body.accessToken;
      if (role !== 'CUSTOMER')
        await db.user.update({ where: { id: r.body.user.id }, data: { role } });
    }
    categoryId = (
      await db.category.create({
        data: { slug: marker, name: `Category ${marker}` },
      })
    ).id;
    brandId = (
      await db.brand.create({ data: { slug: marker, name: `Brand ${marker}` } })
    ).id;
    for (let index = 0; index < 6; index++) {
      const p = await db.product.create({
        data: {
          ...input(`${index}`),
          active: index !== 4,
          images: {
            create:
              index === 3
                ? []
                : [{ url: 'assets/images/shirt.jpg', alt: 'Ảnh', position: 0 }],
          },
          createdAt: new Date(Date.UTC(2026, 0, index + 1)),
          variants: {
            create:
              index === 2
                ? []
                : [
                    {
                      sku: `${marker}_${index}_A`,
                      size: 'M',
                      color: 'Đen',
                      colorHex: '#000000',
                      price: String((index + 1) * 100000),
                      inventory: { create: { quantity: index === 1 ? 0 : 3 } },
                    },
                    {
                      sku: `${marker}_${index}_B`,
                      size: 'L',
                      color: 'Đen',
                      colorHex: '#000000',
                      price: '900000',
                      active: index !== 5,
                      inventory: { create: { quantity: 20 } },
                    },
                  ],
          },
        },
        include: { variants: true },
      });
      products.push(p.id);
    }
    // Product 1 has no stock in any selling SKU.
    await db.inventory.updateMany({
      where: { variant: { productId: products[1] } },
      data: { quantity: 0 },
    });
  });
  afterAll(async () => {
    try {
      if (db) {
        const owned = (
          await db.product.findMany({
            where: { categoryId },
            select: { id: true },
          })
        ).map((p) => p.id);
        const orders = (
          await db.order.findMany({
            where: { userId: { in: users } },
            select: { id: true },
          })
        ).map((o) => o.id);
        await db.adminAuditEvent.deleteMany({
          where: { actorId: { in: users } },
        });
        await db.mailOutbox.deleteMany({ where: { orderId: { in: orders } } });
        await db.inventoryMovement.deleteMany({
          where: { inventory: { variant: { productId: { in: owned } } } },
        });
        await db.orderItem.deleteMany({ where: { orderId: { in: orders } } });
        await db.payment.deleteMany({ where: { orderId: { in: orders } } });
        await db.order.deleteMany({ where: { id: { in: orders } } });
        await db.cartItem.deleteMany({
          where: { variant: { productId: { in: owned } } },
        });
        await db.review.deleteMany({ where: { productId: { in: owned } } });
        await db.aIJob.deleteMany({ where: { userId: { in: users } } });
        await db.imageAsset.deleteMany({ where: { userId: { in: users } } });
        await db.storeCollection.deleteMany({
          where: { slug: { startsWith: `delete-${marker}` } },
        });
        await db.inventory.deleteMany({
          where: { variant: { productId: { in: owned } } },
        });
        await db.productVariant.deleteMany({
          where: { productId: { in: owned } },
        });
        await db.product.deleteMany({ where: { id: { in: owned } } });
        await db.category.delete({ where: { id: categoryId } });
        await db.brand.delete({ where: { id: brandId } });
        await db.user.deleteMany({ where: { id: { in: users } } });
      }
    } finally {
      await app?.close();
    }
  });

  it('filters by category, brand, literal SKU, stock, visibility and same-SKU prices', async () => {
    const list = async (query: Record<string, string>) =>
      (
        await call('get', 'admin/products')
          .query({ categoryId, ...query })
          .expect(200)
      ).body;
    const all = await list({});
    expect(all.total).toBe(6);
    expect(all.items[0].id).toBe(products[5]);
    expect((await list({ brandId })).total).toBe(6);
    expect(
      (await list({ q: `${marker}_0_A` })).items.map(
        (p: { id: string }) => p.id,
      ),
    ).toEqual([products[0]]);
    expect((await list({ q: products[0] })).items[0].id).toBe(products[0]);
    expect((await list({ q: products[0].toUpperCase() })).items[0].id).toBe(
      products[0],
    );
    expect((await list({ q: '%' })).total).toBe(0);
    expect(
      (await list({ stock: 'out' })).items.map((p: { id: string }) => p.id),
    ).toEqual([products[1]]);
    expect((await list({ stock: 'no_variants' })).items[0].id).toBe(
      products[2],
    );
    expect((await list({ status: 'hidden' })).items[0].id).toBe(products[4]);
    expect((await list({ visibility: 'published' })).total).toBe(3);
    expect((await list({ visibility: 'incomplete' })).total).toBe(3);
    expect((await list({ minPrice: '300001', maxPrice: '399999' })).total).toBe(
      0,
    );
    const priced = await list({ minPrice: '0', maxPrice: '100000' });
    expect(priced.items[0].id).toBe(products[0]);
    expect(priced.items[0].summary).toMatchObject({
      stock: 23,
      totalStock: 23,
      minPrice: '100000',
      maxPrice: '900000',
      lowVariants: 1,
      activeVariants: 2,
      published: true,
    });
    const hiddenSku = (await list({ q: `${marker}_5_A` })).items[0].summary;
    expect(hiddenSku).toMatchObject({
      stock: 3,
      totalStock: 23,
      minPrice: '600000',
      maxPrice: '600000',
    });
  });
  it('sorts and paginates stably and rejects invalid filters', async () => {
    for (const sort of [
      'newest',
      'oldest',
      'updated',
      'name_asc',
      'name_desc',
      'price_asc',
      'price_desc',
      'stock_asc',
      'stock_desc',
    ]) {
      const first = await call('get', 'admin/products')
        .query({ categoryId, sort, limit: 2, page: 1 })
        .expect(200);
      const second = await call('get', 'admin/products')
        .query({ categoryId, sort, limit: 2, page: 2 })
        .expect(200);
      expect(
        new Set([...first.body.items, ...second.body.items].map((p) => p.id))
          .size,
      ).toBe(4);
      expect(first.body.total).toBe(6);
    }
    for (const query of [
      { stock: 'bad' },
      { status: 'SHIPPED' },
      { sort: 'bad' },
      { categoryId: 'bad' },
      { brandId: 'bad' },
      { minPrice: '-1' },
      { maxPrice: '1.5' },
      { minPrice: '10', maxPrice: '1' },
      { limit: 101 },
      { page: 0 },
      { q: 'a'.repeat(101) },
    ])
      await call('get', 'admin/products').query(query).expect(400);
    const sorted = await call('get', 'admin/products')
      .query({ categoryId, sort: 'price_asc' })
      .expect(200);
    expect(sorted.body.items[0].id).toBe(products[0]);
    expect(sorted.body.items.at(-1).id).toBe(products[2]);
  });
  it('computes real summary and enforces permissions and record validation', async () => {
    const s = await call('get', 'admin/products/summary').expect(200);
    expect(s.body.total).toBe(await db.product.count());
    expect(s.body.active + s.body.hidden).toBe(s.body.total);
    expect(s.body.published).toBe(
      await db.product.count({
        where: {
          active: true,
          images: { some: { url: { not: '' } } },
          variants: { some: { active: true } },
        },
      }),
    );
    for (const role of ['WAREHOUSE', 'SUPPORT', 'CUSTOMER']) {
      await call('get', 'admin/products', role).expect(403);
      await call('post', 'admin/products', role)
        .send(input(`blocked-${role}`))
        .expect(403);
      await call('patch', `admin/products/${products[0]}`, role)
        .send({ active: false })
        .expect(403);
    }
    await request(app.getHttpServer())
      .get('/api/v1/admin/products')
      .expect(401);
    await call('get', `admin/products/${randomUUID()}`).expect(404);
    await call('get', 'admin/products/bad').expect(400);
    await call('patch', `admin/products/${products[0]}`)
      .send({ role: 'ADMIN' })
      .expect(400);
    await call('patch', `admin/products/${products[0]}`)
      .send({ categoryId: randomUUID() })
      .expect(400);
  });
  it('prevents duplicate creation, empty SKU values and negative prices', async () => {
    const created = await Promise.all(
      [1, 2].map(() => call('post', 'admin/products').send(input('unique'))),
    );
    expect(created.map((r) => r.status).sort()).toEqual([201, 409]);
    expect(created.find((r) => r.status === 409)!.body.error.code).toBe(
      'PRODUCT_SLUG_EXISTS',
    );
    const id = created.find((r) => r.status === 201)!.body.id;
    const sku = {
      productId: id,
      sku: ` ${marker}-new `,
      size: ' M ',
      color: ' Đen ',
      colorHex: '#000000',
      price: '0',
    };
    const first = await call('post', 'admin/skus').send(sku).expect(201);
    expect(first.body.sku).toBe(sku.sku.trim());
    const duplicate = await call('post', 'admin/skus').send(sku).expect(409);
    expect(['SKU_EXISTS', 'VARIANT_EXISTS']).toContain(
      duplicate.body.error.code,
    );
    for (const changes of [
      { sku: '  ' },
      { size: ' ' },
      { color: ' ' },
      { price: '-1' },
      { price: '1.2' },
    ])
      await call('post', 'admin/skus')
        .send({ ...sku, ...changes })
        .expect(400);
    await call('patch', `admin/skus/${first.body.id}`)
      .send({ price: '-1' })
      .expect(400);
    await call('patch', `admin/products/${id}`)
      .send({ name: '  ' })
      .expect(400);
  });
  it('protects metadata, gallery and SKU changes from stale versions', async () => {
    const initial = await read(products[0]);
    const raced = await Promise.all(
      ['One', 'Two'].map((name) =>
        call('patch', `admin/products/${initial.id}`, 'MANAGER').send({
          name,
          expectedUpdatedAt: initial.updatedAt,
        }),
      ),
    );
    expect(raced.map((r) => r.status).sort()).toEqual([200, 409]);
    expect(raced.find((r) => r.status === 409)!.body.error.code).toBe(
      'PRODUCT_CONFLICT',
    );
    const fresh = await read(initial.id);
    expect(fresh.images).toEqual(initial.images);
    await call('patch', `admin/products/${initial.id}`)
      .send({ images: [], expectedUpdatedAt: initial.updatedAt })
      .expect(409);
    const sku = fresh.variants[0];
    const edits = await Promise.all(
      ['123000', '124000'].map((price) =>
        call('patch', `admin/skus/${sku.id}`).send({
          price,
          expectedUpdatedAt: sku.updatedAt,
        }),
      ),
    );
    expect(edits.map((r) => r.status).sort()).toEqual([200, 409]);
    const audit = await db.adminAuditEvent.findFirst({
      where: { targetId: initial.id, action: 'PRODUCT_UPDATED' },
    });
    expect(audit).not.toBeNull();
  });
  it('keeps order prices/images and customer history after edits, hide, and one-time stock restoration', async () => {
    const p = (
      await call('post', 'admin/products')
        .send({ ...input('history'), active: true })
        .expect(201)
    ).body;
    const v = (
      await call('post', 'admin/skus')
        .send({
          productId: p.id,
          sku: `history-${marker}`,
          size: 'M',
          color: 'Đen',
          colorHex: '#000000',
          price: '500000',
        })
        .expect(201)
    ).body;
    const inventory = await db.inventory.findUniqueOrThrow({
      where: { variantId: v.id },
    });
    await call('post', `admin/inventory/${inventory.id}/adjust`)
      .send({ delta: 3, expectedVersion: 0, reason: 'Fixture stock' })
      .expect(201);
    await call('post', `admin/inventory/${inventory.id}/adjust`)
      .send({ delta: 3, expectedVersion: 0, reason: 'Repeated stale request' })
      .expect(409);
    const address = (
      await db.address.create({
        data: {
          userId: userIds.CUSTOMER,
          label: 'Nhà',
          recipient: 'Buyer',
          phone: '0900000000',
          address: 'Fixture address',
        },
      })
    ).id;
    await call('post', 'cart/items', 'CUSTOMER')
      .send({ sku: v.sku, quantity: 1 })
      .expect(201);
    const order = (
      await call('post', 'orders', 'CUSTOMER')
        .set('Idempotency-Key', randomUUID())
        .send({
          addressId: address,
          shippingMethod: 'standard',
          expectedSubtotal: '500000',
        })
        .expect(201)
    ).body;
    await call('patch', `admin/skus/${v.id}`)
      .send({ price: '600000', expectedUpdatedAt: v.updatedAt })
      .expect(200);
    await call('patch', `admin/products/${p.id}`)
      .send({
        name: 'Renamed product',
        images: [],
        active: false,
        expectedUpdatedAt: p.updatedAt,
      })
      .expect(200);
    const history = (await call('get', `admin/orders/${order.id}`).expect(200))
      .body;
    expect(history.items[0].unitPrice).toBe('500000');
    expect(history.items[0].name).toBe(p.name);
    expect(history.items[0].image).toBe('assets/images/shirt.jpg');
    const savedProduct = await read(p.id);
    const blockedDelete = await call('delete', `admin/products/${p.id}`)
      .send({ expectedUpdatedAt: savedProduct.updatedAt })
      .expect(409);
    expect(blockedDelete.body.error.code).toBe('PRODUCT_IN_USE');
    const customerOrders = await call('get', 'admin/orders')
      .query({ customerId: userIds.CUSTOMER })
      .expect(200);
    expect(
      customerOrders.body.items.map((o: { id: string }) => o.id),
    ).toContain(order.id);
    await request(app.getHttpServer())
      .get(`/api/v1/products/${p.slug}`)
      .expect(404);
    const publicList = await request(app.getHttpServer())
      .get('/api/v1/products')
      .query({ q: p.slug })
      .expect(200);
    expect(publicList.body.total).toBe(0);
    const cancel = await call(
      'post',
      `orders/${order.id}/cancel`,
      'CUSTOMER',
    ).send({ expectedVersion: order.version, reason: 'Fixture cancellation' });
    expect([200, 201]).toContain(cancel.status);
    await call('post', `orders/${order.id}/cancel`, 'CUSTOMER')
      .send({ expectedVersion: order.version, reason: 'Repeated cancellation' })
      .expect(201);
    expect(
      (await db.inventory.findUniqueOrThrow({ where: { id: inventory.id } }))
        .quantity,
    ).toBe(3);
    await call('post', `admin/inventory/${inventory.id}/adjust`)
      .send({ delta: -4, expectedVersion: 3, reason: 'Prevent negative stock' })
      .expect(409);
  });
  const deletable = async () => {
    const { images, ...data } = input(`delete-${randomUUID().slice(0, 8)}`);
    return db.product.create({
      data: {
        ...data,
        active: true,
        images: {
          create: images.map((image, position) => ({ ...image, position })),
        },
        variants: {
          create: {
            sku: randomUUID(),
            size: 'M',
            color: 'Đen',
            colorHex: '#000000',
            price: '100000',
            inventory: { create: { quantity: 7 } },
          },
        },
      },
      include: { variants: { include: { inventory: true } }, images: true },
    });
  };
  it('deletes unused products atomically, updates public/admin lists and records one audit', async () => {
    const p = await deletable();
    await db.wishlistItem.create({
      data: { userId: userIds.CUSTOMER, productId: p.id },
    });
    const collection = await db.storeCollection.create({
      data: {
        slug: `delete-${marker}`,
        title: 'Test collection',
        description: '',
        style: `delete-${marker}`,
        coverProductId: p.id,
      },
    });
    const before = (await call('get', 'admin/products/summary')).body.total;
    await call('delete', `admin/products/${p.id}`, 'MANAGER')
      .send({ expectedUpdatedAt: p.updatedAt.toISOString() })
      .expect(200, { id: p.id, deleted: true });
    expect(await db.product.findUnique({ where: { id: p.id } })).toBeNull();
    expect(
      await db.inventory.count({ where: { id: p.variants[0].inventory!.id } }),
    ).toBe(0);
    expect(await db.productVariant.count({ where: { productId: p.id } })).toBe(
      0,
    );
    expect(await db.productImage.count({ where: { productId: p.id } })).toBe(0);
    expect(await db.wishlistItem.count({ where: { productId: p.id } })).toBe(0);
    expect(
      (
        await db.storeCollection.findUniqueOrThrow({
          where: { id: collection.id },
        })
      ).coverProductId,
    ).toBeNull();
    expect((await call('get', 'admin/products/summary')).body.total).toBe(
      before - 1,
    );
    expect(
      (await call('get', 'admin/products').query({ q: p.id })).body.total,
    ).toBe(0);
    await request(app.getHttpServer())
      .get(`/api/v1/products/${p.slug}`)
      .expect(404);
    await call('get', `admin/products/${p.id}`).expect(404);
    await call('delete', `admin/products/${p.id}`)
      .send({ expectedUpdatedAt: p.updatedAt.toISOString() })
      .expect(404);
    expect(
      await db.adminAuditEvent.count({
        where: { action: 'PRODUCT_DELETED', targetId: p.id },
      }),
    ).toBe(1);
  });
  it('requires permission and an exact version, and serializes repeated deletion', async () => {
    const p = await deletable(),
      endpoint = `admin/products/${p.id}`;
    const body = { expectedUpdatedAt: p.updatedAt.toISOString() };
    for (const role of ['CUSTOMER', 'SUPPORT', 'WAREHOUSE'])
      await call('delete', endpoint, role).send(body).expect(403);
    await request(app.getHttpServer())
      .delete('/api/v1/' + endpoint)
      .send(body)
      .expect(401);
    for (const invalid of [
      {},
      { expectedUpdatedAt: null },
      { expectedUpdatedAt: 'bad-date' },
    ])
      await call('delete', endpoint).send(invalid).expect(400);
    const fresh = (
      await call('patch', endpoint)
        .send({ name: 'Updated before deletion', ...body })
        .expect(200)
    ).body;
    expect(
      (await call('delete', endpoint).send(body).expect(409)).body.error.code,
    ).toBe('PRODUCT_CONFLICT');
    expect(
      await db.inventory.count({ where: { id: p.variants[0].inventory!.id } }),
    ).toBe(1);
    const attempts = await Promise.all(
      [1, 2].map(() =>
        call('delete', endpoint).send({ expectedUpdatedAt: fresh.updatedAt }),
      ),
    );
    expect(attempts.map((r) => r.status).sort()).toEqual([200, 404]);
    expect(
      await db.adminAuditEvent.count({
        where: { action: 'PRODUCT_DELETED', targetId: p.id },
      }),
    ).toBe(1);
  });
  it('preserves each kind of customer or stock reference when deletion is blocked', async () => {
    for (const kind of ['cart', 'movement', 'review', 'tryon']) {
      const p = await deletable(),
        variantId = p.variants[0].id;
      if (kind === 'cart') {
        const cart = await db.cart.upsert({
          where: { userId: userIds.CUSTOMER },
          create: { userId: userIds.CUSTOMER },
          update: {},
        });
        await db.cartItem.create({
          data: { cartId: cart.id, variantId, quantity: 1 },
        });
      } else if (kind === 'movement') {
        await db.inventoryMovement.create({
          data: {
            inventoryId: p.variants[0].inventory!.id,
            delta: 7,
            reason: 'Fixture receipt',
          },
        });
      } else if (kind === 'review') {
        await db.review.create({
          data: {
            userId: userIds.CUSTOMER,
            productId: p.id,
            rating: 5,
            comment: 'Test review',
          },
        });
      } else {
        const image = await db.imageAsset.create({
          data: {
            userId: userIds.CUSTOMER,
            objectKey: `delete-${marker}/${randomUUID()}`,
            mimeType: 'image/png',
            size: 100,
            expiresAt: new Date(Date.now() + 60000),
          },
        });
        await db.aIJob.create({
          data: {
            userId: userIds.CUSTOMER,
            variantId,
            imageId: image.id,
            consentAt: new Date(),
            status: 'FAILED',
          },
        });
      }
      const response = await call('delete', `admin/products/${p.id}`)
        .send({ expectedUpdatedAt: p.updatedAt.toISOString() })
        .expect(409);
      expect(response.body.error.code).toBe('PRODUCT_IN_USE');
      expect((await read(p.id)).variants[0].inventory.quantity).toBe(7);
      expect(await db.productImage.count({ where: { productId: p.id } })).toBe(
        1,
      );
      expect(
        await db.adminAuditEvent.count({
          where: { action: 'PRODUCT_DELETED', targetId: p.id },
        }),
      ).toBe(0);
    }
  });
});
