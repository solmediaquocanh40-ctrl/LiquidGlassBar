# LiquidGlassBar 1.0.0

Thanh tab bar kiểu **Liquid Glass cho Messenger** (bản 1.0.0: chỉ Messenger —
test ổn mới mở rộng ra các app khác ở bản sau, kèm trang List app để bật
từng app).

## Tính năng

- Thanh tab bar của Messenger thành **kính mờ dạng viên thuốc nổi**: nền
  blur, viền sáng mỏng, nhuộm màu kính tuỳ chọn.
- **Kéo cục glass trượt ngang để chọn mục**: chạm giữ trên thanh bar, kéo
  qua lại — glass bám theo tay, rung nhẹ khi qua mục mới, thả tay là nảy
  lò xo về mục gần nhất và chọn mục đó. Chạm từng mục vẫn dùng như thường.
- **Đổi màu icon khi được chọn**: vào Cài đặt → LiquidGlassBar → "Màu icon
  khi được chọn", chọn bất kỳ màu nào (mặc định xanh Messenger `#0084FF`).
- **Huy hiệu chưa đọc giữ nguyên**: cục đỏ số tin chưa đọc (vd "30+") và
  chấm đỏ nằm trên lớp kính, không bị nhuộm màu, không bị che.
- Tuỳ chọn: độ rõ của kính, màu nhuộm kính, bật/tắt kéo trượt, bật/tắt rung.

## Cách hoạt động (2 đường)

1. Nếu Messenger dùng thanh chuẩn `UITabBar`: hook trực tiếp thanh đó.
2. Nếu Messenger dùng thanh tự chế: tweak quét cây view ở vùng đáy màn
   hình mỗi 1,5 giây, tìm container có 3–7 mục nằm ngang và áp kính lên.
   Việc quét có ghi log chẩn đoán.

## Build

Đẩy toàn bộ cây này lên GitHub, kèm file workflow riêng
`build-liquidglassbar-1.0.0.yml` vào `.github/workflows/build.yml`
(commit mới — đừng bấm Re-run bản cũ). CI build 3 bản: rootful, rootless,
roothide.

## Test trên máy

1. Cài .deb, mở Messenger: thanh bar dưới phải thành viên thuốc kính.
2. Kéo ngang trên thanh bar: glass trượt theo tay, thả ra chọn mục.
3. Đổi màu icon trong Cài đặt → mở lại Messenger: icon mục đang chọn đổi màu.
4. Nhờ người khác nhắn tin tới: cục đỏ số chưa đọc vẫn hiện bình thường.
5. Nếu bar chưa thành kính hoặc kéo không ăn: lấy file
   `Documents/LiquidGlassBar.log` gửi lại — trong log có cây view vùng đáy
   và class của thanh bar Messenger để chỉnh vòng sau.

## Giới hạn đã biết của bản 1.0.0

- Chỉ Messenger (lọc theo bundle `com.facebook.Messenger`).
- Nếu Messenger dùng thanh tự chế mà mục không phải `UIControl`, cú kéo
  vẫn đổi màu + trượt glass nhưng có thể chưa mô phỏng được cú chạm chọn
  mục — log sẽ ghi rõ trường hợp này.
- Kính là bản backport cho iOS 15/16 (blur hệ thống + viền sáng), không
  phải kính khúc xạ thật của iOS 26.
