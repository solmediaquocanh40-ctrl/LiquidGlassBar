# LiquidGlassBar 1.4.0

Thanh tab bar kiểu **Liquid Glass cho Messenger** (chỉ Messenger —
test ổn mới mở rộng ra các app khác ở bản sau, kèm trang List app để bật
từng app).

Bản 1.4.0: thêm **lớp kính shader** (file `LGBGlassShader.h` dùng chung
cho tweak và trang Cài đặt): vệt sáng viền + quầng sáng mặt kính vẽ bằng
Metal, phỏng theo phần toán của shader `GlassBackground17.metal` trong
gói **LiquidGlaze** (com.zege.liquidglaze của tác giả zege — hàm
highlight theo SDF của QuartzCore và falloff cầu; SDF viên thuốc ở đây
tính giải tích, không dùng texture SDF như bản gốc). Lớp shader chỉ vẽ
phần SÁNG đè lên blur sống sẵn có — trong tiến trình app bên thứ ba
không lấy được texture hậu cảnh của render server nên không làm khúc
xạ thật như đường ống cấp hệ thống của LiquidGlaze; độ giống kỳ vọng
~80–85%. Shader **biên dịch sẵn lúc nạp** ở luồng nền, mỗi kích thước
chỉ render 1 ảnh tĩnh có lưu đệm, cục glass vẫn di chuyển bằng
transform → không thêm chi phí theo khung hình, không khựng khi kéo.
Có công tắc **"Kính shader"** trong Cài đặt: tắt là lùi về đúng kính
1.3.0; nếu Metal lỗi, tweak cũng tự lùi và ghi "FAIL" ở nút chẩn đoán
(khoá `diag_shaderGlass`). Khung xem trước trong Cài đặt cũng vẽ lớp
shader này. LƯU Ý: bản này phải đẩy ĐỦ file — có thêm 2 file mới
`tweak/LGBGlassShader.h` và `prefs/LGBGlassShader.h`, và Root.plist có
thêm công tắc `shaderGlass` (tổng 14 khoá prefs).

Bản 1.3.0 (theo test máy thật của 1.2.0): (1) glass đo theo **tổng
khung icon + chữ** (kể cả chữ nằm ngoài/tách khỏi ô icon) nên bao trọn
chữ; (2) **blur sống trở lại** trong cục glass + asset chỉnh trong hơn
để nhìn xuyên qua và mờ nội dung phía sau như ảnh mẫu; (3) di chuyển
bằng **transform** thay cho đổi frame nên kéo mượt, hết khựng; (4) thêm
slider **độ nảy khi thả** và **độ giãn khi kéo**; (5) sửa vụ thông số
không áp dụng: tweak **nạp lại prefs mỗi 1,5 giây** và mỗi lần app được
mở lại, không phụ thuộc tín hiệu báo thay đổi; (6) trang Cài đặt có
**khung xem trước trực quan** vẽ bằng đúng bộ kính, đổi tuỳ chọn là
khung đổi theo ngay. LƯU Ý: bản này phải đẩy ĐỦ file (đặc biệt
Root.plist và 2 file LGCPreviewCell mới) — thiếu file là Cài đặt không
hiện slider/preview mới.

Bản 1.2.0 (theo test máy thật của 1.1.0: kính đã hiện nhưng chưa đẹp,
kéo bị khựng rồi nhảy, glass lệch và nhỏ hơn ô mục): (1) **asset kính
vẽ sẵn** bằng code — gradient có chiều sâu, quầng sáng, vệt bóng gương,
viền sáng — đắp lên lớp blur của viên thuốc nền; (2) **kéo mượt**:
cục glass bỏ blur sống bên trong, bóng đổ có shadowPath, cử chỉ đổi
sang nhận diện tức thì (chạm di chuyển 4pt mới tính là kéo, chạm thường
không đổi), đang kéo thì glass giãn nhẹ theo tốc độ, thả ra co lại;
(3) **kích thước đo theo ô mục thật** (gồm cả chữ) và kẹp gọn trong
viên thuốc nền, nền đo theo vùng nội dung thật của bar; (4) Cài đặt
thêm: độ rõ riêng cho cục glass, chiều rộng/cao cục glass (%), lề
viên thuốc nền.

Bản 1.1.0 sửa **kính không hiện** (test máy thật của 1.0.1: kéo được,
icon đổi màu được, nhưng không thấy kính): hai lớp kính ở bản cũ chèn ở
đáy chồng view nên bị lớp nền đặc của thanh bar Messenger che mất. Nay
kính được nâng lên nằm **trên mọi lớp nền của bar, ngay dưới các mục**,
và cục glass chọn đổi sang kiểu **kính trắng mờ sáng** (blur + lớp trắng
+ nhuộm nhẹ màu chọn + viền sáng + bóng đổ) như clip mẫu, thay cho lớp
màu chọn alpha 0,25 cũ. Phần kéo trượt + đổi màu (đã chạy tốt) giữ nguyên.

Bản 1.0.1 là bản **chẩn đoán khâu nạp**: bản 1.0.0 cài trên máy thật thì
Cài đặt hiện, công tắc bật được, nhưng Messenger không áp kính và không
có file log — vì log ghi ra `/var/mobile/Documents` bị sandbox của
Messenger chặn, và chưa phân biệt được tweak đã nạp vào app hay chưa.
Bản này sửa cả hai: log ghi vào Documents của chính Messenger, và tweak
tự ghi "dấu vết đã nạp + trạng thái quét bar" vào miền cài đặt (đọc lại
bằng nút **Xem trạng thái nạp tweak** trong Cài đặt → LiquidGlassBar).

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
`build-liquidglassbar-1.4.0.yml` vào `.github/workflows/build.yml`
(commit mới — đừng bấm Re-run bản cũ). CI build 3 bản: rootful, rootless,
roothide.

## Test trên máy

1. Cài .deb, mở Messenger: thanh bar dưới phải thành viên thuốc kính.
2. Kéo ngang trên thanh bar: glass trượt theo tay, thả ra chọn mục.
3. Đổi màu icon trong Cài đặt → mở lại Messenger: icon mục đang chọn đổi màu.
4. Nhờ người khác nhắn tin tới: cục đỏ số chưa đọc vẫn hiện bình thường.
5. Nếu bar chưa thành kính: vào Cài đặt → LiquidGlassBar → **Xem trạng
   thái nạp tweak**, chụp màn hình thông báo đó. Kèm file log: mở Filza,
   tìm kiếm toàn máy `LiquidGlassBar.log` (file nằm trong thư mục
   Documents của chính Messenger) rồi gửi lại — trong log có cây view
   vùng đáy và class của thanh bar Messenger để chỉnh vòng sau.

## Giới hạn đã biết của bản 1.0.0

- Chỉ Messenger (lọc theo bundle `com.facebook.Messenger`).
- Nếu Messenger dùng thanh tự chế mà mục không phải `UIControl`, cú kéo
  vẫn đổi màu + trượt glass nhưng có thể chưa mô phỏng được cú chạm chọn
  mục — log sẽ ghi rõ trường hợp này.
- Kính là bản backport cho iOS 15/16 (blur hệ thống + viền sáng), không
  phải kính khúc xạ thật của iOS 26.
