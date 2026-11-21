import { Transform } from 'class-transformer';
import { IsString, Matches, MaxLength, MinLength } from 'class-validator';
import { Prisma } from '../../generated/prisma/client';

const trim = () =>
  Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  );
export class StoreDetailsDto {
  @trim() @IsString() @MinLength(1) @MaxLength(80) name!: string;
  @trim() @IsString() @MaxLength(160) tagline!: string;
  @trim()
  @IsString()
  @MaxLength(254)
  @Matches(/^(?:[^\s@]+@[^\s@]+\.[^\s@]+)?$/)
  email!: string;
  @trim() @IsString() @MaxLength(40) phone!: string;
  @trim() @IsString() @MaxLength(300) address!: string;
  @trim() @IsString() @MaxLength(5000) about!: string;
  @trim() @IsString() @MaxLength(5000) privacy!: string;
  @trim() @IsString() @MaxLength(5000) terms!: string;
}
export const defaultStoreDetails: StoreDetailsDto = {
  name: 'WEARLY',
  tagline: 'Tủ đồ đương đại, theo cách bạn.',
  email: '',
  phone: '',
  address: '',
  about:
    'Khám phá những thiết kế, màu sắc và cách phối dành cho phong cách riêng của bạn. WEARLY giúp bạn lưu sản phẩm yêu thích, chọn kích cỡ, theo dõi đơn hàng và tìm cảm hứng cho tủ đồ mỗi ngày.',
  privacy:
    'Tài khoản, địa chỉ, đơn hàng, yêu cầu hỗ trợ và đăng ký nhận tin được lưu trên máy chủ. Phiên đăng nhập dùng cookie HttpOnly; đăng xuất để thu hồi phiên. Email khôi phục được gửi tới địa chỉ tài khoản. Khi dịch vụ Gemini được bật, Stylist chỉ gửi nội dung lựa chọn sau khi bạn đồng ý; phòng thử yêu cầu đồng ý riêng trước khi tải ảnh và tạo kết quả. Ảnh riêng tư cần đăng nhập để xem, có thời hạn lưu và có thể xóa trong phòng thử. Xóa hoặc hết hạn chặn truy cập, việc dọn tệp được xử lý nền.',
  terms:
    'Giá và tồn kho được kiểm tra lại khi đặt hàng. COD được xác nhận thu tiền bằng thao tác đối soát có phân quyền. VNPay hiện dùng môi trường thử nghiệm; theo dõi vận chuyển chưa kết nối với đơn vị giao hàng bên ngoài. Kết quả Gemini chỉ hỗ trợ tham khảo, không xác nhận độ vừa vặn hay chất lượng sản phẩm. Không có tự động giao hàng hoặc hoàn tiền ngoài hệ thống.',
};
export function storeDetails(
  value: Prisma.JsonValue | null | undefined,
): StoreDetailsDto {
  if (!value || typeof value !== 'object' || Array.isArray(value))
    return { ...defaultStoreDetails };
  return Object.fromEntries(
    Object.entries(defaultStoreDetails).map(([key, fallback]) => [
      key,
      typeof value[key] === 'string' ? value[key] : fallback,
    ]),
  ) as unknown as StoreDetailsDto;
}
