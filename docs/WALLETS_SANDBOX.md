# Ví điện tử MoMo và ZaloPay (sandbox)

Cửa hàng hỗ trợ thanh toán thử nghiệm qua **MoMo** và **ZaloPay**, bên cạnh COD và
VNPay. Chỉ dùng môi trường sandbox; không có thanh toán thật. Trình duyệt quay về
cửa hàng không phải bằng chứng thanh toán: đơn chỉ được xử lý sau khi máy chủ xác
minh qua IPN/callback có chữ ký hoặc truy vấn trực tiếp tới cổng.

## Cấu hình (`backend/.env`)

```dotenv
# Trang cửa hàng hiển thị sau khi rời ví (origin phải có trong CORS_ORIGINS)
PAYMENT_WEB_RETURN_URL="http://localhost:8080/#/payments/return"

MOMO_ENABLED=true
MOMO_PARTNER_CODE=MOMO
MOMO_ACCESS_KEY=F8BBA842ECF85
MOMO_SECRET_KEY=K951B6PE1waDMi640xX08PD3vg6EkVlz
MOMO_RETURN_URL=http://localhost:3000/api/v1/payments/momo/return
MOMO_IPN_URL=http://localhost:3000/api/v1/payments/momo/ipn

ZALOPAY_ENABLED=false
ZALOPAY_APP_ID=2553
ZALOPAY_KEY1=PcY4iZIKFCIdgZvA6ueMcMHHUbRLYjPL
ZALOPAY_KEY2=kLtgPl8HHhfvMuDHPwKfgfsY4Ydm9eIz
ZALOPAY_RETURN_URL=http://localhost:3000/api/v1/payments/zalopay/return
ZALOPAY_CALLBACK_URL=http://localhost:3000/api/v1/payments/zalopay/callback
```

Các giá trị trên là **khóa test công khai** trong tài liệu của MoMo/ZaloPay. Có thể
thay bằng khóa sandbox riêng. Khi bật một ví, API kiểm tra cấu hình lúc khởi động
(mã, khóa, đường dẫn trả về đúng endpoint, HTTPS ngoài localhost) và **từ chối khởi
động** nếu sai. Sửa xong phải khởi động lại API. Khóa chỉ nằm ở backend.

- Số tiền mỗi đơn: **1.000 – 50.000.000 VND** cho cả hai ví.
- Link thanh toán hết hạn sau **15 phút** (gửi kèm cho cổng).
- Trên localhost, cổng không gọi được IPN/callback về máy; nút **Kiểm tra kết quả**
  truy vấn trực tiếp. Khi có địa chỉ công khai, đặt `MOMO_IPN_URL` /
  `ZALOPAY_CALLBACK_URL` thành `https://<domain>/api/v1/payments/{momo/ipn|zalopay/callback}`.

## Thử thanh toán

1. Đăng nhập cửa hàng, thêm sản phẩm, chọn địa chỉ và **MoMo sandbox** (hoặc
   **ZaloPay sandbox**) ở bước thanh toán.
2. Trong chi tiết đơn: **Chuẩn bị thanh toán** → **Mở … sandbox (tab mới)**.
3. MoMo: chọn thanh toán bằng thẻ ATM nội địa và dùng thẻ test trong tài liệu MoMo.
   ZaloPay: dùng ứng dụng ZaloPay sandbox hoặc thẻ test của ZaloPay.
4. Quay lại tab cửa hàng, bấm **Kiểm tra kết quả**. Đơn chỉ được xác nhận giao hàng
   sau khi thanh toán đã xác minh.

## Hoàn tiền

Quản trị viên hoàn tiền từ chi tiết đơn như VNPay. Với ví, hệ thống gửi yêu cầu hoàn
tới cổng; nếu chưa rõ kết quả, khoản hoàn được giữ ở trạng thái chờ và **Kiểm tra kết
quả hoàn** truy vấn bằng mã yêu cầu đã lưu (không cần nhập mã thủ công).

## Trạng thái kiểm chứng (08/11/2026)

| Hạng mục | MoMo | ZaloPay |
|---|---|---|
| Tạo link, truy vấn với sandbox thật | Đạt (khóa test công khai) | **Chưa** — máy local không kết nối được `sb-openapi.zalopay.vn` |
| Chữ ký IPN/callback, luồng đơn hàng, hoàn tiền | Test tự động với dữ liệu ký giả lập | Test tự động với dữ liệu ký giả lập |
| Thanh toán đầy đủ bằng thẻ test, IPN thật, hoàn tiền thật | Chưa thực hiện | Chưa thực hiện |

ZaloPay để tắt mặc định cho tới khi kết nối được sandbox. Định dạng chữ ký IPN của
MoMo và phản hồi truy vấn hoàn tiền được viết theo tài liệu; cần một giao dịch test
thật để xác nhận.

## Mã nguồn

- `backend/src/integrations/payments/{momo,zalopay}.provider.ts`, `wallet-gateway.ts`
- `backend/src/modules/payments/*` — `POST payments/momo/ipn`,
  `POST payments/zalopay/callback`, `GET payments/{momo,zalopay}/return`
- Migration `20261108230000_wallet_payment_links` (cột `PaymentAttempt.checkoutUrl`)
- Test: `backend/test/wallet-providers.spec.ts`, `wallet-config.spec.ts`,
  `wallet-payments.e2e-spec.ts`; `frontend/test/payments_test.dart`
