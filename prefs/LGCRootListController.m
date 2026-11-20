#import "LGCRootListController.h"

static NSString *const LGC_DOMAIN = @"com.vn.liquidglassbar";
static NSString *const LGC_PREFS_NOTIFICATION = @"com.vn.liquidglassbar/prefsChanged";

static UIColor *LGCColorFromHex(NSString *hexStr, UIColor *fallback) {
    if (![hexStr isKindOfClass:[NSString class]] || hexStr.length == 0) return fallback;
    NSString *clean = [[hexStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    if ([clean hasPrefix:@"#"]) clean = [clean substringFromIndex:1];
    if ([clean hasPrefix:@"0X"]) clean = [clean substringFromIndex:2];
    if (clean.length != 6) return fallback;
    unsigned int rgbVal = 0;
    if (![[NSScanner scannerWithString:clean] scanHexInt:&rgbVal]) return fallback;
    return [UIColor colorWithRed:((rgbVal & 0xFF0000) >> 16) / 255.0
                           green:((rgbVal & 0x00FF00) >> 8) / 255.0
                            blue:(rgbVal & 0x0000FF) / 255.0
                           alpha:1.0];
}

static NSString *LGCHexFromColor(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat w = 0; // màu grayscale: không đọc được RGB thì lấy độ trắng
        if ([color getWhite:&w alpha:&a]) { r = g = b = w; }
    }
    return [NSString stringWithFormat:@"#%02X%02X%02X",
            (int)lround(r * 255.0), (int)lround(g * 255.0), (int)lround(b * 255.0)];
}

@interface LGCRootListController () <UIColorPickerViewControllerDelegate>
@property (nonatomic, copy) NSString *activeColorKey;
@property (nonatomic, copy) NSString *activeColorDefaultHex;
- (void)saveColor:(UIColor *)color postNotification:(BOOL)postNotification;
@end

@implementation LGCRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)openSelectedColorPicker:(id)sender {
    (void)sender;
    [self presentColorPickerForKey:@"selectedColorHex" defaultHex:@"#0084FF" title:@"Màu icon khi được chọn"];
}

- (void)openGlassTintColorPicker:(id)sender {
    (void)sender;
    [self presentColorPickerForKey:@"glassTintHex" defaultHex:@"#FFFFFF" title:@"Màu nhuộm kính"];
}

- (void)presentColorPickerForKey:(NSString *)prefKey defaultHex:(NSString *)defaultHex title:(NSString *)title {
    self.activeColorKey = prefKey;
    self.activeColorDefaultHex = defaultHex;
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:LGC_DOMAIN];
    NSString *currentHex = [defaults stringForKey:prefKey] ?: defaultHex;
    UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
    picker.delegate = self;
    picker.supportsAlpha = NO;
    picker.selectedColor = LGCColorFromHex(currentHex, [UIColor blueColor]);
    picker.title = title;
    [self presentViewController:picker animated:YES completion:nil];
}

// Kéo chọn màu: lưu thầm, KHÔNG bắn thông báo (tránh spam reload như bài
// học bên CircleSwitcher). Chỉ khi chọn xong mới thông báo 1 lần.
- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController {
    [self saveColor:viewController.selectedColor postNotification:NO];
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController {
    [self saveColor:viewController.selectedColor postNotification:YES];
    [self reloadSpecifiers];
}

- (void)showDiagnostics:(id)sender {
    (void)sender;
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:LGC_DOMAIN];
    NSString *last = [defaults stringForKey:@"diag_lastLoadAt"];
    NSString *state = [defaults stringForKey:@"diag_barState"];
    NSNumber *scans = [defaults objectForKey:@"diag_scanCount"];
    NSString *shader = [defaults stringForKey:@"diag_shaderGlass"];
    NSString *msg = nil;
    if (!last) {
        msg = @"Chưa ghi nhận lần nạp nào.\n\nNghĩa là tweak CHƯA chạy vào trong Messenger. Kiểm tra: đã tắt hẳn Messenger trong đa nhiệm rồi mở lại chưa; trong app Dopamine phần nạp tweak có đang bật không; nếu có Choicy thì Messenger có bị tắt nạp tweak không.\n\nChụp màn hình thông báo này gửi lại nếu vẫn không nạp được.";
    } else {
        msg = [NSString stringWithFormat:@"Lần nạp gần nhất: %@\n\nTrạng thái thanh bar: %@\n\nSố lần quét tìm bar: %@\n\nShader kính (1.4.0): %@",
               last, state ?: @"(chưa có)", scans ?: @0, shader ?: @"(chưa rõ — mở Messenger một lúc rồi xem lại)"];
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Trạng thái LiquidGlassBar"
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)saveColor:(UIColor *)color postNotification:(BOOL)postNotification {
    if (!self.activeColorKey || !color) return;
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:LGC_DOMAIN];
    [defaults setObject:LGCHexFromColor(color) forKey:self.activeColorKey];
    [defaults synchronize];
    if (postNotification) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge CFStringRef)LGC_PREFS_NOTIFICATION, NULL, NULL, YES);
    }
}

@end
