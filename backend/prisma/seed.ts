import 'dotenv/config';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '../src/generated/prisma/client';
const db = new PrismaClient({
  adapter: new PrismaPg({ connectionString: process.env.DATABASE_URL }),
});
const seeds = [
  [
    'Áo cotton không tay',
    'ao',
    'shirt.jpg',
    490000,
    'Trắng',
    '#E8E7E2',
    'Cotton mềm, thoáng nhẹ',
    'Tối giản',
  ],
  [
    'Đầm sơ mi mềm',
    'dam',
    'black-dress.jpg',
    890000,
    'Mận',
    '#65394D',
    'Vải dệt mềm với độ rủ nhẹ',
    'Thanh lịch',
  ],
  [
    'Quần jogger nhẹ',
    'quan',
    'trousers.jpg',
    650000,
    'Hồng đất',
    '#C69887',
    'Vải dệt nhẹ, cạp co giãn',
    'Thư giãn',
  ],
  [
    'Áo khoác bomber',
    'khoac',
    'outerwear.jpg',
    1190000,
    'Nâu',
    '#97614B',
    'Vải dệt, lót mỏng',
    'Tối giản',
  ],
  [
    'Quần denim ống rộng',
    'quan',
    'shirt.jpg',
    790000,
    'Xanh',
    '#66899C',
    'Denim cotton, phom rộng',
    'Thư giãn',
  ],
  [
    'Đầm ren tay dài',
    'dam',
    'jacket.jpg',
    1290000,
    'Tím',
    '#453C76',
    'Ren họa tiết, lớp lót mềm',
    'Thanh lịch',
  ],
  [
    'Đầm dài dạo phố',
    'dam',
    'dress.jpg',
    1090000,
    'Đỏ',
    '#AB3143',
    'Vải rủ nhẹ, dáng xòe',
    'Thanh lịch',
  ],
  [
    'Áo khoác dáng dài',
    'khoac',
    'campaign.jpg',
    1690000,
    'Xanh',
    '#66899C',
    'Vải dạ pha, phom suông',
    'Thanh lịch',
  ],
] as const;
async function seed() {
  const categories = new Map<string, string>();
  for (const [slug, name] of Object.entries({
    ao: 'Áo',
    quan: 'Quần',
    dam: 'Váy & đầm',
    khoac: 'Áo khoác',
  }))
    categories.set(
      slug,
      (
        await db.category.upsert({
          where: { slug },
          create: { slug, name },
          update: {},
        })
      ).id,
    );
  const brand = await db.brand.upsert({
    where: { slug: 'wearly' },
    create: { slug: 'wearly', name: 'Wearly' },
    update: {},
  });
  const editions = ['Essential', 'Daily', 'Weekend', 'Studio'];
  for (let e = 0; e < 4; e++)
    for (let i = 0; i < seeds.length; i++) {
      const [name, category, image, price, color, colorHex, material, style] =
          seeds[i],
        index = e * 8 + i + 1,
        slug = 'nep-' + index;
      const product = await db.product.upsert({
        where: { slug },
        update: {},
        create: {
          slug,
          name: name + ' ' + editions[e],
          categoryId: categories.get(category)!,
          brandId: brand.id,
          material,
          style,
          description:
            'Dữ liệu và ảnh sản phẩm minh họa cho trải nghiệm mua sắm.',
          tryOnSupported: category !== 'quan',
        },
      });
      await db.productImage.upsert({
        where: { productId_position: { productId: product.id, position: 0 } },
        update: {},
        create: {
          productId: product.id,
          position: 0,
          url: 'assets/images/' + image,
          alt: name + ' · Ảnh catalog minh họa',
          color,
        },
      });
      for (let c = 0; c < 2; c++)
        for (let s = 0; s < 4; s++) {
          const size = ['S', 'M', 'L', 'XL'][s],
            sku =
              'WRL-' + index + '-' + (c === 0 ? 'MAIN' : 'DARK') + '-' + size;
          await db.productVariant.upsert({
            where: { sku },
            update: {},
            create: {
              productId: product.id,
              sku,
              size,
              color: c === 0 ? color : 'Đen',
              colorHex: c === 0 ? colorHex : '#29282B',
              price: String(price + e * 20000),
              inventory: {
                create: {
                  quantity: s === 3 ? 0 : s === 0 ? 3 : 12,
                  movements: {
                    create: {
                      delta: s === 3 ? 0 : s === 0 ? 3 : 12,
                      reason: 'SEED_INITIAL',
                    },
                  },
                },
              },
            },
          });
        }
    }
  console.log(
    'Seed complete: 32 catalog products; existing prices, stock and users were preserved.',
  );
}
seed().finally(() => db.$disconnect());
