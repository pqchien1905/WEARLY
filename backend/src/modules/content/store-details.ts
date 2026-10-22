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
  tagline: 'Bản demo chạy local',
  email: '',
  phone: '',
  address: '',
  about:
    'WEARLY là cửa hàng minh họa chạy trên máy local. Catalog và ảnh dùng để trải nghiệm các chức năng; chưa đại diện cho hoạt động bán hàng thực tế.',
  privacy:
    'Tài khoản, địa chỉ, đơn hàng và yêu cầu hỗ trợ được lưu trên máy chủ local. Phiên đăng nhập dùng cookie HttpOnly và có thể tiếp tục sau khi tải lại trang; đăng xuất để thu hồi phiên. Stylist gửi nội dung lựa chọn tới Google Gemini sau khi bạn đồng ý. Thử đồ chỉ lưu ảnh và gửi ảnh người/trang phục tới Gemini sau các bước đồng ý riêng. Ảnh riêng tư cần đăng nhập để xem, có thời hạn lưu và có thể xóa trong phòng thử; xóa hoặc hết hạn chặn truy cập, việc dọn bytes được xử lý nền. Thư hỗ trợ nằm trong hộp thư local. Hạn chế dùng dữ liệu cá nhân thật trong bản thử nghiệm.',
  terms:
    'Đây là bản demo local. VNPay dùng môi trường thử nghiệm, vận chuyển được mô phỏng và COD được xác nhận thu tiền bằng thao tác đối soát có phân quyền. Kết quả Gemini chỉ hỗ trợ tham khảo, không xác nhận độ vừa vặn hay chất lượng sản phẩm. Không có cam kết giao hàng thực tế hoặc tự động hoàn tiền ngoài hệ thống.',
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
