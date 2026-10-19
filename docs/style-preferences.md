# Hồ sơ phong cách

Trong cửa hàng trực tuyến, vào **Tài khoản → Phong cách của tôi** (`/#/account/style`). Chọn size, phong cách, màu ưu tiên và ngân sách mỗi outfit, rồi bấm **Lưu hồ sơ phong cách**. Dữ liệu lưu theo tài khoản trong PostgreSQL, còn sau khi đăng xuất hoặc tải lại trang; tải lại trang vẫn cần đăng nhập lại do phiên hiện lưu trong RAM.

Size là sở thích, không phải số đo hoặc lời khẳng định vừa người. Các lựa chọn không được suy đoán từ ảnh. Hồ sơ chưa tự lọc cửa hàng hay tạo gợi ý AI; chế độ API không có nút mở Stylist khi dịch vụ đó chưa hoạt động. Demo giữ luồng riêng và thông báo dữ liệu chỉ trong phiên.

Nếu hai tab sửa cùng một phiên bản, chỉ một lần lưu thành công; tab còn lại phải tải lại. Nếu mất phản hồi hoặc không đọc được dữ liệu sau khi gửi, giao diện không báo đã lưu và không tự gửi lại. **Tải lại hồ sơ** bỏ thay đổi chưa lưu để đọc trạng thái máy chủ. Phản hồi đến muộn sau timeout làm mới cache của cùng phiên; không khôi phục dữ liệu tài khoản đã thoát.

## API

GET `/api/v1/users/me/style` và PUT cùng đường dẫn đều yêu cầu Bearer. Danh tính lấy từ phiên, không nhận userId trong payload. GET không có hàng trả mặc định size M, phong cách/màu trống, ngân sách1500000 và version0; không ghi DB.

```json
{"size":"L","style":"Thanh lịch","color":"Đen","budget":"2500000","expectedVersion":0}
```

PUT trả cùng các lựa chọn với `version` tăng lên1; lần lưu tiếp gửi phiên bản vừa nhận. Budget là chuỗi nguyên VND, chỉ nhận800000/1500000/2500000. Size XS/S/M/L/XL/XXL; phong cách trống/Tối giản/Thanh lịch/Thư giãn; màu trống/Trắng/Đen/Mận/Xanh/Nâu/Hồng đất/Tím/Đỏ. Dữ liệu sai trả400, phiên bản cũ409. Khóa theo user và transaction giữ đúng kết quả khi tạo/lưu đồng thời.

`StylePreference` có userId UUID PK/FK, budget Decimal(14,0), version và timestamps; xóa theo User. Migration chỉ thêm bảng, không sửa/xóa dữ liệu cũ. AccountDetails đọc cả địa chỉ và phong cách nhưng giữ lỗi phong cách riêng: lỗi này không làm mất địa chỉ đã tải, không chặn checkout hoặc biến lần lưu địa chỉ đã xác nhận thành thất bại. Trang phong cách hiển thị lỗi/thử lại, không cho sửa một bộ giá trị mặc định giả. Lỗi phiên đăng nhập vẫn chặn dữ liệu cũ.

## Kiểm thử

`powershell -NoProfile -File tools/test-backend.ps1` dùng DB `_test`. `node tools/test-frontend-api.cjs --style` tạo hai tài khoản riêng, lưu hồ sơ bằng Chrome, kiểm tra qua reload/login và sửa đồng thời, xác nhận địa chỉ vẫn còn. Helper chỉ dọn dữ liệu fixture của lượt chạy. Ảnh/log trong `.tools/api-style-verification` (ignored). Sau lượt thử, `./tools/frontend.ps1 build-api` khôi phục build API localhost3000.
