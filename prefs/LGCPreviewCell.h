#import <Preferences/PSTableCell.h>
#import <Preferences/PSSpecifier.h>

// Ô xem trước trực quan ở đầu trang Cài đặt: vẽ một thanh bar mẫu với
// đúng bộ kính của tweak (blur sống + asset kính + màu/độ mờ/kích thước
// đang lưu trong prefs), tự cập nhật ngay khi người dùng đổi tuỳ chọn —
// vừa để chỉnh cho vừa mắt, vừa để thấy ngay thông số có được lưu không.
@interface LGCPreviewCell : PSTableCell
- (void)refreshPreview;
@end
