import '../../domain/catalog.dart';

const categories = {
  '': 'Tất cả',
  'ao': 'Áo',
  'quan': 'Quần',
  'dam': 'Váy & đầm',
  'khoac': 'Áo khoác',
};
const styles = ['Tối giản', 'Thanh lịch', 'Thư giãn'];

List<Product> catalogFixture() {
  const seeds = [
    (
      'Áo cotton không tay',
      'ao',
      'shirt.jpg',
      490000,
      'Trắng',
      0xFFE8E7E2,
      'Cotton mềm, thoáng nhẹ',
      'Tối giản',
    ),
    (
      'Đầm sơ mi mềm',
      'dam',
      'black-dress.jpg',
      890000,
      'Mận',
      0xFF65394D,
      'Vải dệt mềm với độ rủ nhẹ',
      'Thanh lịch',
    ),
    (
      'Quần jogger nhẹ',
      'quan',
      'trousers.jpg',
      650000,
      'Hồng đất',
      0xFFC69887,
      'Vải dệt nhẹ, cạp co giãn',
      'Thư giãn',
    ),
    (
      'Áo khoác bomber',
      'khoac',
      'outerwear.jpg',
      1190000,
      'Nâu',
      0xFF97614B,
      'Vải dệt, lót mỏng',
      'Tối giản',
    ),
    (
      'Quần denim ống rộng',
      'quan',
      'shirt.jpg',
      790000,
      'Xanh',
      0xFF66899C,
      'Denim cotton, phom rộng',
      'Thư giãn',
    ),
    (
      'Đầm ren tay dài',
      'dam',
      'jacket.jpg',
      1290000,
      'Tím',
      0xFF453C76,
      'Ren họa tiết, lớp lót mềm',
      'Thanh lịch',
    ),
    (
      'Đầm dài dạo phố',
      'dam',
      'dress.jpg',
      1090000,
      'Đỏ',
      0xFFAB3143,
      'Vải rủ nhẹ, dáng xòe',
      'Thanh lịch',
    ),
    (
      'Áo khoác dáng dài',
      'khoac',
      'campaign.jpg',
      1690000,
      'Xanh',
      0xFF66899C,
      'Vải dạ pha, phom suông',
      'Thanh lịch',
    ),
  ];
  const edits = ['Essential', 'Daily', 'Weekend', 'Studio'];
  return [
    for (var e = 0; e < edits.length; e++)
      for (var i = 0; i < seeds.length; i++)
        Product(
          id: 'p${e * 8 + i + 1}',
          slug: 'nep-${e * 8 + i + 1}',
          name: '${seeds[i].$1} ${edits[e]}',
          category: seeds[i].$2,
          image: 'assets/images/${seeds[i].$3}',
          media: [
            ProductMedia(
              path: 'assets/images/${seeds[i].$3}',
              label: '${seeds[i].$1} · Ảnh catalog minh họa',
              color: seeds[i].$5,
            ),
          ],
          description:
              'Một phom dáng dễ mặc, để bạn thoải mái kết hợp cùng những món đồ yêu thích. Dữ liệu và ảnh sản phẩm minh họa cho trải nghiệm mua sắm.',
          material: seeds[i].$7,
          style: seeds[i].$8,
          tryOn: seeds[i].$2 != 'quan',
          variants: [
            for (var c = 0; c < 2; c++)
              for (var s = 0; s < 4; s++)
                ProductVariant(
                  sku:
                      'WRL-${e * 8 + i + 1}-${c == 0 ? "MAIN" : "DARK"}-${["S", "M", "L", "XL"][s]}',
                  size: ['S', 'M', 'L', 'XL'][s],
                  color: c == 0 ? seeds[i].$5 : 'Đen',
                  colorHex: c == 0 ? seeds[i].$6 : 0xFF29282B,
                  price: seeds[i].$4 + e * 20000,
                  stock: s == 3 ? 0 : (s == 0 ? 3 : 12),
                ),
          ],
        ),
  ];
}
