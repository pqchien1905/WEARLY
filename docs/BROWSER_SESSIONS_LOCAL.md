# Phiên đăng nhập trên trình duyệt local

Web dùng hai phiên riêng cho khách hàng và nhân viên. Tải lại trang hoặc mở tab
mới sẽ khôi phục tài khoản trước khi tải dữ liệu riêng. Đăng xuất khách hàng không
đăng xuất nhân viên và ngược lại. Đổi quyền, khóa tài khoản hoặc đặt lại mật khẩu
thu hồi phiên ở máy chủ; token cũ không tiếp tục truy cập được.

Chạy frontend và API với cùng tên máy: dùng `127.0.0.1` cho cả hai, hoặc `localhost`
cho cả hai. Ví dụ frontend `http://127.0.0.1:5173` và API
`http://127.0.0.1:3000/api/v1`. `CORS_ORIGINS` trong `backend/.env` phải chứa chính
xác origin của frontend, gồm cổng. Không dùng dấu `*`. Chỉ HTTP local loopback được
chấp nhận cho các endpoint cookie. Chế độ production yêu cầu HTTPS trực tiếp tới
ứng dụng; cấu hình reverse proxy/TLS production nằm ngoài phạm vi bản local này.

Cookie `wearly_customer_session` sống tối đa7ngày; `wearly_admin_session` tối đa8giờ.
Cả hai là HttpOnly, SameSite=Strict, không có Domain và có Path riêng theo phạm vi.
Secure bật khi HTTPS/production; local HTTP không bật Secure. Thời hạn tính từ lúc
đăng nhập, không kéo dài khi gia hạn access token. Cookie chỉ chứa chuỗi ngẫu nhiên;
cơ sở dữ liệu lưu hash. Access token chỉ ở bộ nhớ, không lưu localStorage/sessionStorage.

POST `/api/v1/auth/browser/customer/{register,login,refresh,logout}` và
`/api/v1/auth/browser/admin/{login,refresh,logout}` cần Origin hợp lệ và header
`X-Wearly-Browser: 1`. Frontend web tự gửi cookie. JSON không trả refresh token.
Các endpoint JSON `/auth/login`, `/auth/admin/login`, `/auth/register`, `/auth/refresh`
hiện có vẫn dùng được cho API/native và giữ cơ chế xoay refresh token cũ.

Gia hạn cookie dùng phiên cố định có thể thu hồi, để nhiều tab hoặc phản hồi gia
hạn bị mất không làm đăng xuất nhầm. Đăng nhập mới tạo phiên mới, thu hồi cookie
cũ được gửi cùng yêu cầu. Cookie bị lấy cắp vẫn dùng được tới khi hết hạn/thu hồi;
không coi cookie Path là ranh giới tin cậy giữa mã JavaScript cùng origin.

Nếu tab khác đổi tài khoản, tab cũ không gửi lại thao tác đang chờ dưới tài khoản
mới; màn hình yêu cầu đăng nhập lại. Các yêu cầu đăng nhập/đăng xuất trong cùng tab
được xếp theo hoàn tất mạng thực tế; phản hồi đăng nhập trễ bị bỏ sẽ được thu hồi.
Đăng nhập/đăng xuất đồng thời ở nhiều tab có thể cần đăng nhập lại. Nếu mạng lỗi
khi khôi phục hoặc đăng xuất, giao diện cho thử lại và không báo thành công giả.

Trước khi gửi đăng nhập, web lưu một mã lần thử không bí mật trong localStorage
(khóa bắt đầu bằng `wearly.auth-recovery.v1:`, riêng theo API và phạm vi). Mã này
không chứa tài khoản, mật khẩu hay token, và bị xóa khi đăng nhập được xác nhận.
Nếu đăng nhập bị bỏ dở và hủy phiên thất bại, mã còn lại qua lần tải trang. Web
phải hủy phiên thành công trước khi khôi phục hoặc đăng nhập lại; màn hình lỗi
có nút thử lại. Trình duyệt cần cho phép lưu dữ liệu trang để dùng đăng nhập web.

Mở ứng dụng bằng link đặt lại mật khẩu sẽ bắt đầu với giao diện chưa đăng nhập,
xóa token khỏi URL ngay và bỏ qua khôi phục phiên trong cửa sổ đó. Sau khi đặt lại,
đăng nhập bằng mật khẩu mới. Các lần tải trang thông thường vẫn khôi phục hai phiên.

Kiểm chứng: `node tools/test-frontend-api.cjs --sessions` tạo tài khoản riêng trong
database `_test`, kiểm tra cookie thật bằng Chrome, nhiều tab, token hết hạn, CSRF,
đổi tài khoản, đăng xuất và thu hồi quyền. Không ghi giá trị cookie/token vào ảnh
hay báo cáo. Các kịch bản trình duyệt cũ đã đổi kỳ vọng reload sang khôi phục phiên.
Kịch bản cũng gây trễ đăng nhập thật, trả lỗi hủy phiên, tải lại trang và thử hủy
lại để kiểm chứng không tự khôi phục phiên đã bỏ dở.

Tham chiếu thiết kế: [OWASP Session Management](https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html),
[OWASP CSRF](https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html),
[MDN Set-Cookie](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Set-Cookie).
