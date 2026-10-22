# Thông tin cửa hàng trên bản local

Tên mặc định **WEARLY**, ghi rõ **Bản demo chạy local** theo lựa chọn của bạn.
Không có email, điện thoại hoặc địa chỉ thật mặc định. Trường liên hệ trống không
xuất hiện trên cửa hàng; biểu mẫu hỗ trợ vẫn lưu yêu cầu và dùng hộp thư local.

Trong **Quản trị → Nội dung**, sửa tên, mô tả ngắn, liên hệ, giới thiệu, quyền riêng
tư, điều khoản và chính sách giao hàng/đổi trả. **Lưu bản nháp** chưa thay đổi nội
dung khách thấy. Kiểm tra bản đã lưu rồi chọn **Xuất bản nội dung**. Khi có người
khác thay đổi phiên bản, tải lại bản mới trước khi tiếp tục. MANAGER và ADMIN có
quyền quản lý nội dung theo quyền hiện có; các vai trò khác không được sửa.

Tên đã xuất bản xuất hiện ở nhận diện cửa hàng, liên hệ ở chân trang và trang hỗ
trợ, chính sách ở các trang tương ứng. Nội dung chỉ là văn bản; không sửa công
thức giá, phí vận chuyển, quyền hoàn tiền hoặc thời hạn lưu ảnh. Để trống nội dung
giới thiệu/quyền riêng tư/điều khoản sẽ dùng mô tả mặc định của bản local. Ghi chú
demo vẫn hiển thị dù đổi tên cửa hàng.

Mô tả mặc định phản ánh phiên đăng nhập được khôi phục sau tải lại, Gemini chỉ gọi
sau thao tác đồng ý và khi có cấu hình, VNPay sandbox, vận chuyển mô phỏng và COD
đối soát riêng. Không tự đặt cam kết giao hàng thực tế hoặc thời hạn đổi trả.

## HTML sản phẩm để kiểm tra metadata

Backend cung cấp các đường dẫn dưới `/api/v1/storefront`:

- `products/<slug>`: HTML đọc được với tiêu đề, mô tả, canonical, OpenGraph, giá
  biến thể đang hoạt động và liên kết mở sản phẩm trong Flutter.
- `sitemap.xml`: danh sách URL xem trước của sản phẩm đang hoạt động.
- `robots.txt`: ghi chú chế độ local, không chặn crawler đọc noindex.

`LOCAL_API_ORIGIN` mặc định `http://127.0.0.1:3000`;
`LOCAL_STORE_ORIGIN` mặc định `http://localhost:8080`. Đặt đúng cổng local khi
chạy khác mặc định. Cả hai chỉ chấp nhận origin loopback HTTP(S), không có đường
dẫn, thông tin đăng nhập, query hay fragment. Không lấy canonical từ Host do
trình duyệt gửi lên.

HTML và phản hồi preview có `noindex,nofollow`; ứng dụng Flutter cũng giữ noindex.
Sitemap này phục vụ kiểm tra local, không gửi lên công cụ tìm kiếm. Đây chưa phải
triển khai SEO cho tên miền công khai. [Google hướng dẫn noindex](https://developers.google.com/search/docs/crawling-indexing/block-indexing)
yêu cầu crawler đọc được thẻ/header, nên không dùng robots để chặn đường dẫn này.

Migration27 chỉ thêm hai cột JSON nullable, không thay dữ liệu cửa hàng cũ.
Hãy dùng [sao lưu native](NATIVE_RECOVERY.md) trước mỗi lần nâng cấp dữ liệu.
