// LiquidGlassBar 1.4.0 — thanh tab bar kiểu Liquid Glass cho Messenger:
// nền kính mờ dạng viên thuốc nổi, cục glass chọn kéo trượt ngang qua lại
// để chọn mục, icon của mục được chọn đổi sang màu tuỳ chọn trong Cài đặt.
// Bản 1.4.0 thêm LỚP KÍNH SHADER (LGBGlassShader.h): vệt sáng viền +
// quầng sáng mặt kính chạy bằng Metal, phỏng theo phần toán của shader
// GlassBackground17 trong gói LiquidGlaze — đè lên blur sống sẵn có.
// Shader biên dịch sẵn lúc nạp, mỗi kích thước chỉ render 1 ảnh tĩnh,
// kéo vẫn bằng transform nên không thêm chi phí theo từng khung hình.
// Tắt "Kính shader" trong Cài đặt là lùi về đúng kính của bản 1.3.0.
//
// Hai đường áp dụng:
//  A) Thanh chuẩn UITabBar (hook trực tiếp, chắc nhất).
//  B) Thanh tự chế của Messenger: quét cây view ở vùng đáy màn hình, tìm
//     container có 3–7 mục nằm ngang cách đều nhau, áp cùng bộ kính +
//     glass trượt lên. Mọi lần quét đều ghi log chẩn đoán (cây view vùng
//     đáy + class của ứng viên) vào Documents/LiquidGlassBar.log để nếu
//     Messenger dùng cấu trúc lạ thì vòng sau soi log là thấy ngay.
//
// Huy hiệu số chưa đọc (cục đỏ "30+") và chấm đỏ KHÔNG bị đụng vào: lớp
// kính nằm dưới icon, và khi nhuộm màu icon thì bỏ qua mọi view trông
// giống huy hiệu (nhỏ, bo tròn, nền đỏ).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "LGBGlassShader.h"

static NSString *const LGB_DOMAIN = @"com.vn.liquidglassbar";
static NSString *const LGB_PREFS_NOTIFICATION = @"com.vn.liquidglassbar/prefsChanged";

// Log ghi vào thư mục Documents của CHÍNH Messenger (bản 1.0.0 ghi ra
// /var/mobile/Documents bị sandbox của app chặn nên không tạo được file).
// Trong Filza: tìm kiếm toàn máy "LiquidGlassBar.log" là thấy, hoặc vào
// /var/mobile/Containers/Data/Application/<thư mục Messenger>/Documents/.
static NSString *LGBLogFilePath(void) {
    static NSString *path = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *base = dirs.firstObject;
        path = base ? [base stringByAppendingPathComponent:@"LiquidGlassBar.log"]
                    : @"/var/mobile/Documents/LiquidGlassBar.log";
    });
    return path;
}

static const NSInteger LGB_BG_TAG = 712001;
static const NSInteger LGB_INDICATOR_TAG = 712002;
static const NSInteger LGB_TINT_COLOR_TAG = 712012;
static const NSInteger LGB_ASSET_TAG = 712013;
static const NSInteger LGB_SPEC_TAG = 712014;

static BOOL pEnabled = YES;
static BOOL pShaderGlass = YES;
static BOOL pDragEnabled = YES;
static BOOL pHaptics = YES;
static BOOL pDebug = YES;
static CGFloat pGlassAlpha = 0.85;
static CGFloat pBlobAlpha = 0.95;
static CGFloat pBlobWidthPct = 100.0;
static CGFloat pBlobHeightPct = 100.0;
static CGFloat pPillInset = 8.0;
static CGFloat pSpringPct = 55.0;
static CGFloat pStretchPct = 60.0;
static NSString *pSelectedColorHex = @"#0084FF";
static NSString *pGlassTintHex = @"#FFFFFF";

// ------------------------------------------------------------------ log
static void LGBLog(NSString *fmt, ...) {
    if (!pDebug) return;
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSLog(@"[LiquidGlassBar] %@", msg);
    @try {
        NSString *line = [NSString stringWithFormat:@"%@ %@\n",
                          [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                         dateStyle:NSDateFormatterNoStyle
                                                         timeStyle:NSDateFormatterMediumStyle],
                          msg];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:LGBLogFilePath()];
        if (!fh) {
            [line writeToFile:LGBLogFilePath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } else {
            [fh seekToEndOfFile];
            [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        }
    } @catch (__unused NSException *e) {}
}

// ------------------------------------------------------------------ prefs
static id LGBGetPref(NSString *key, id def) {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                    (__bridge CFStringRef)LGB_DOMAIN);
    id obj = (__bridge_transfer id)v;
    return obj ?: def;
}

// Ghi "dấu vết chẩn đoán" vào miền prefs của tweak qua CFPreferences —
// đường này đi qua tiến trình hệ thống cfprefsd nên KHÔNG bị sandbox của
// Messenger chặn (khác với ghi file trực tiếp ở bản 1.0.0). Trang Cài đặt
// đọc lại các khoá diag_* này ở nút "Xem trạng thái nạp tweak".
static void LGBDiagWrite(NSString *key, id value) {
    if (value) {
        CFPreferencesSetAppValue((__bridge CFStringRef)key,
                                 (__bridge CFPropertyListRef)value,
                                 (__bridge CFStringRef)LGB_DOMAIN);
    } else {
        CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL,
                                 (__bridge CFStringRef)LGB_DOMAIN);
    }
    CFPreferencesAppSynchronize((__bridge CFStringRef)LGB_DOMAIN);
}

static NSString *LGBNowString(void) {
    return [NSDateFormatter localizedStringFromDate:[NSDate date]
                                          dateStyle:NSDateFormatterShortStyle
                                          timeStyle:NSDateFormatterMediumStyle];
}

static void LGBLoadPrefs(void) {
    pEnabled         = [LGBGetPref(@"enabled", @YES) boolValue];
    pShaderGlass     = [LGBGetPref(@"shaderGlass", @YES) boolValue];
    pDragEnabled     = [LGBGetPref(@"dragEnabled", @YES) boolValue];
    pHaptics         = [LGBGetPref(@"haptics", @YES) boolValue];
    pDebug           = [LGBGetPref(@"debug", @YES) boolValue];
    pGlassAlpha      = [LGBGetPref(@"glassAlpha", @0.85) doubleValue];
    pBlobAlpha       = [LGBGetPref(@"blobAlpha", @0.95) doubleValue];
    pBlobWidthPct    = [LGBGetPref(@"blobWidthPct", @100.0) doubleValue];
    pBlobHeightPct   = [LGBGetPref(@"blobHeightPct", @100.0) doubleValue];
    pPillInset       = [LGBGetPref(@"pillInset", @8.0) doubleValue];
    if (pBlobWidthPct < 50 || pBlobWidthPct > 150) pBlobWidthPct = 100.0;
    if (pBlobHeightPct < 40 || pBlobHeightPct > 150) pBlobHeightPct = 100.0;
    if (pPillInset < 0 || pPillInset > 30) pPillInset = 8.0;
    pSpringPct       = [LGBGetPref(@"springPct", @55.0) doubleValue];
    pStretchPct      = [LGBGetPref(@"stretchPct", @60.0) doubleValue];
    if (pSpringPct < 0 || pSpringPct > 100) pSpringPct = 55.0;
    if (pStretchPct < 0 || pStretchPct > 100) pStretchPct = 60.0;
    pSelectedColorHex = LGBGetPref(@"selectedColorHex", @"#0084FF");
    pGlassTintHex     = LGBGetPref(@"glassTintHex", @"#FFFFFF");
    if (![pSelectedColorHex isKindOfClass:[NSString class]]) pSelectedColorHex = @"#0084FF";
    if (![pGlassTintHex isKindOfClass:[NSString class]]) pGlassTintHex = @"#FFFFFF";
}

static UIColor *LGBColorFromHex(NSString *hexStr, UIColor *fallback) {
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

static UIColor *LGBSelectedColor(void) {
    return LGBColorFromHex(pSelectedColorHex, [UIColor colorWithRed:0.0 green:0.52 blue:1.0 alpha:1.0]);
}

static UIColor *LGBGlassTintColor(void) {
    return LGBColorFromHex(pGlassTintHex, [UIColor whiteColor]);
}

// ------------------------------------------------------------------ asset kính
// Asset kính VẼ SẴN bằng code (vẽ 1 lần cho mỗi kích thước, có lưu đệm):
// nền gradient có chiều sâu + quầng sáng góc trên + vệt bóng gương +
// tối nhẹ ở đáy + viền sáng gradient. Đắp asset này lên lớp blur mỏng
// thì ra chất kính thật hơn hẳn lớp trắng phẳng của bản cũ, mà lại nhẹ
// nên kéo trượt mượt (không phải vẽ lại blur theo từng milimét di chuyển).
static UIImage *LGBGlassImageForSize(CGSize size) {
    if (size.width < 10 || size.height < 10) return nil;
    static NSMutableDictionary<NSString *, UIImage *> *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ cache = [NSMutableDictionary dictionary]; });
    NSString *key = NSStringFromCGSize(size);
    UIImage *cached = cache[key];
    if (cached) return cached;

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        CGRect rect = CGRectMake(0, 0, size.width, size.height);
        CGFloat radius = size.height / 2.0;
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius];
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();

        // 1) nền kính: gradient dọc trắng, sáng ở trên, trong dần xuống dưới
        [path addClip];
        CGFloat loc1[] = {0.0, 0.45, 1.0};
        CGFloat comp1[] = {1,1,1,0.20,  1,1,1,0.10,  1,1,1,0.04};
        CGGradientRef g1 = CGGradientCreateWithColorComponents(cs, comp1, loc1, 3);
        CGContextDrawLinearGradient(c, g1, CGPointMake(0, 0), CGPointMake(0, size.height), 0);
        CGGradientRelease(g1);

        // 2) quầng sáng ở góc trên-trái (điểm sáng hắt lên mặt kính)
        CGFloat loc2[] = {0.0, 1.0};
        CGFloat comp2[] = {1,1,1,0.22,  1,1,1,0.0};
        CGGradientRef g2 = CGGradientCreateWithColorComponents(cs, comp2, loc2, 2);
        CGPoint glowCenter = CGPointMake(size.width * 0.30, size.height * 0.16);
        CGContextDrawRadialGradient(c, g2, glowCenter, 0, glowCenter, size.width * 0.55, 0);
        CGGradientRelease(g2);

        // 3) vệt bóng gương: dải sáng mềm ở nửa trên
        CGContextSaveGState(c);
        CGContextClipToRect(c, CGRectMake(0, 0, size.width, size.height * 0.52));
        CGFloat loc3[] = {0.0, 1.0};
        CGFloat comp3[] = {1,1,1,0.30,  1,1,1,0.0};
        CGGradientRef g3 = CGGradientCreateWithColorComponents(cs, comp3, loc3, 2);
        CGContextDrawLinearGradient(c, g3, CGPointMake(0, 0), CGPointMake(0, size.height * 0.52), 0);
        CGGradientRelease(g3);
        CGContextRestoreGState(c);

        // 4) tối nhẹ ở đáy cho có chiều sâu
        CGFloat loc4[] = {0.0, 1.0};
        CGFloat comp4[] = {0,0,0,0.0,  0,0,0,0.16};
        CGGradientRef g4 = CGGradientCreateWithColorComponents(cs, comp4, loc4, 2);
        CGContextDrawLinearGradient(c, g4, CGPointMake(0, size.height * 0.70), CGPointMake(0, size.height), 0);
        CGGradientRelease(g4);

        // 5) viền sáng gradient (sáng ở trên, mờ dần xuống dưới)
        CGContextSaveGState(c);
        UIBezierPath *rim = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(rect, 0.75, 0.75)
                                                       cornerRadius:MAX(1.0, radius - 0.75)];
        CGContextSetLineWidth(c, 1.5);
        CGContextAddPath(c, rim.CGPath);
        CGContextReplacePathWithStrokedPath(c);
        CGContextClip(c);
        CGFloat loc5[] = {0.0, 1.0};
        CGFloat comp5[] = {1,1,1,0.85,  1,1,1,0.25};
        CGGradientRef g5 = CGGradientCreateWithColorComponents(cs, comp5, loc5, 2);
        CGContextDrawLinearGradient(c, g5, CGPointMake(0, 0), CGPointMake(0, size.height), 0);
        CGGradientRelease(g5);
        CGContextRestoreGState(c);

        CGColorSpaceRelease(cs);
    }];
    if (image) {
        if (cache.count > 16) [cache removeAllObjects];
        cache[key] = image;
    }
    return image;
}

// View này có trông giống huy hiệu (badge) không: nhỏ, bo tròn mạnh, nền
// đỏ rõ. Nếu giống thì KHÔNG nhuộm màu cây con của nó.
static BOOL LGBLooksLikeBadge(UIView *v) {
    if (v.bounds.size.width <= 0 || v.bounds.size.width > 30 || v.bounds.size.height > 30) return NO;
    UIColor *bg = v.backgroundColor;
    if (!bg) return NO;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![bg getRed:&r green:&g blue:&b alpha:&a]) return NO;
    if (a < 0.5) return NO;
    return (r > 0.75 && g < 0.45 && b < 0.45 && v.layer.cornerRadius >= v.bounds.size.height * 0.35);
}

// ------------------------------------------------------------------ manager
@interface LGBManager : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UITabBar *tabBar;
@property (nonatomic, weak) UIView *customBar;
@property (nonatomic, strong) NSArray<UIView *> *customItems;
@property (nonatomic, assign) NSInteger customSelectedIndex;
@property (nonatomic, assign) NSInteger previewIndex;
@property (nonatomic, assign) BOOL dragEngaged;
@property (nonatomic, assign) CGFloat dragStartX;
@property (nonatomic, assign) CGFloat lastDragX;
@property (nonatomic, assign) CGFloat dragSettledCenterX;
@property (nonatomic, weak) UIView *dragBlob;
@property (nonatomic, strong) NSTimer *scanTimer;
@property (nonatomic, assign) NSInteger scanCount;
@property (nonatomic, copy) NSString *diagState;
@property (nonatomic, assign) BOOL dumpedBottomHierarchy;
@property (nonatomic, copy) NSString *loggedCandidateSignature;
+ (instancetype)shared;
- (void)start;
- (void)writeDiagState:(NSString *)state;
- (void)reloadPrefs;
- (void)styleTabBar:(UITabBar *)bar;
- (void)styleCustomBar:(UIView *)bar items:(NSArray<UIView *> *)items;
- (void)tabBarSelectionChanged:(UITabBar *)bar;
- (void)tabBarSelectionChangedCustom;
- (void)handlePan:(UILongPressGestureRecognizer *)pan;
- (void)customItemTapped:(UIControl *)sender;
- (void)scanTick:(NSTimer *)timer;
- (UIView *)pillBackgroundInBar:(UIView *)bar frame:(CGRect)frame belowItems:(NSArray<UIView *> *)items;
- (UIView *)indicatorInBar:(UIView *)bar belowItems:(NSArray<UIView *> *)items;
- (NSInteger)glassInsertIndexInBar:(UIView *)bar items:(NSArray<UIView *> *)items;
- (void)placeGlassViewsInBar:(UIView *)bar belowItems:(NSArray<UIView *> *)items;
- (BOOL)updateSpecularInHolder:(UIView *)holder size:(CGSize)size intensity:(CGFloat)intensity alpha:(CGFloat)alpha;
- (void)refreshIndicator:(UIView *)ind;
- (CGRect)pillFrameForBar:(UIView *)bar;
- (CGRect)indicatorFrameForItemFrame:(CGRect)itemFrame limitRect:(CGRect)limit;
- (CGRect)contentRectForItem:(UIView *)item inBar:(UIView *)bar;
- (CGRect)targetFrameForIndex:(NSInteger)idx bar:(UIView *)bar items:(NSArray<UIView *> *)items;
- (CGFloat)springDamping;
- (void)animateIndicatorToIndex:(NSInteger)idx bar:(UIView *)bar items:(NSArray<UIView *> *)items completion:(void (^)(void))completion;
- (void)attachPanToBar:(UIView *)bar;
- (void)hapticTick;
- (NSArray<UIView *> *)tabBarButtons:(UITabBar *)bar;
- (NSInteger)nearestIndex:(CGFloat)x centers:(NSArray<NSNumber *> *)centers;
- (void)finishDragToIndex:(NSInteger)idx bar:(UIView *)bar isTabBar:(BOOL)isTab;
- (void)selectTabBarIndex:(NSInteger)idx bar:(UITabBar *)bar;
- (void)selectCustomIndex:(NSInteger)idx;
- (void)applyCustomSelectionVisual;
- (void)tintTree:(UIView *)v color:(UIColor *)color selected:(BOOL)selected;
- (UIWindow *)activeWindow;
- (void)appDidBecomeActive:(NSNotification *)note;
- (BOOL)viewLooksLikeTabItem:(UIView *)v;
- (void)dumpBottomHierarchy:(UIWindow *)win;
- (void)dumpView:(UIView *)v window:(UIWindow *)win depth:(NSInteger)depth into:(NSMutableString *)out lines:(NSInteger *)lines;
- (BOOL)subtree:(UIView *)v hasIconOrLabelAtDepth:(NSInteger)depth;
- (void)collectCandidatesInView:(UIView *)v window:(UIWindow *)win depth:(NSInteger)depth best:(UIView **)best bestScore:(NSInteger *)bestScore bestItems:(NSArray<UIView *> **)bestItems;
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other;
@end

@implementation LGBManager

+ (instancetype)shared {
    static LGBManager *inst = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [[LGBManager alloc] init]; });
    return inst;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _customSelectedIndex = 0;
        _previewIndex = -1;
    }
    return self;
}

- (void)writeDiagState:(NSString *)state {
    if (!state || [state isEqualToString:self.diagState]) return;
    self.diagState = state;
    LGBDiagWrite(@"diag_barState", state);
}

- (void)start {
    LGBDiagWrite(@"diag_lastLoadAt", LGBNowString());
    LGBDiagWrite(@"diag_process", [[NSBundle mainBundle] bundleIdentifier] ?: @"?");
    [self writeDiagState:@"Da nap vao Messenger, dang quet thanh bar..."];
    LGBLog(@"Khoi dong trong process %@ (enabled=%d)", [[NSBundle mainBundle] bundleIdentifier], pEnabled);
    LGBLog(@"Duong dan log: %@", LGBLogFilePath());
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    self.scanTimer = [NSTimer scheduledTimerWithTimeInterval:1.5
                                                      target:self
                                                    selector:@selector(scanTick:)
                                                    userInfo:nil
                                                     repeats:YES];
}

- (void)reloadPrefs {
    LGBLoadPrefs();
    LGBLog(@"Nap lai prefs: enabled=%d shader=%d drag=%d mauChon=%@ mauKinh=%@ alpha=%.2f blobAlpha=%.2f rong=%.0f%% cao=%.0f%% le=%.0f nay=%.0f gian=%.0f",
           pEnabled, pShaderGlass, pDragEnabled, pSelectedColorHex, pGlassTintHex, pGlassAlpha,
           pBlobAlpha, pBlobWidthPct, pBlobHeightPct, pPillInset, pSpringPct, pStretchPct);
    if (self.tabBar) [self styleTabBar:self.tabBar];
    if (self.customBar) [self styleCustomBar:self.customBar items:self.customItems];
}

// ---------------------------------------------------------- tiện ích chung
// Vị trí chèn lớp kính: ngay DƯỚI mục đầu tiên của bar. Bản 1.0.x chèn ở
// index 0/1 nên bị lớp nền đặc của thanh bar Messenger đè lên che mất —
// kéo vẫn chạy (gesture gắn trên bar), icon vẫn đổi màu (icon ở lớp trên
// cùng), riêng kính thì không thấy. Từ 1.1.0: kính nằm TRÊN mọi lớp nền
// của bar nhưng DƯỚI các mục.
- (NSInteger)glassInsertIndexInBar:(UIView *)bar items:(NSArray<UIView *> *)items {
    for (UIView *item in items) {
        if (item.superview == bar) return (NSInteger)[bar.subviews indexOfObject:item];
    }
    return 0;
}

- (void)placeGlassViewsInBar:(UIView *)bar belowItems:(NSArray<UIView *> *)items {
    if (!bar || items.count == 0) return;
    UIView *pill = [bar viewWithTag:LGB_BG_TAG];
    UIView *ind = [bar viewWithTag:LGB_INDICATOR_TAG];
    if (pill && pill.superview != bar) pill = nil;
    if (ind && ind.superview != bar) ind = nil;
    if (!pill && !ind) return;
    UIView *firstItem = nil;
    for (UIView *item in items) {
        if (item.superview == bar) { firstItem = item; break; }
    }
    if (!firstItem) return;
    NSInteger firstIdx = (NSInteger)[bar.subviews indexOfObject:firstItem];
    NSInteger pillIdx = pill ? (NSInteger)[bar.subviews indexOfObject:pill] : NSNotFound;
    NSInteger indIdx = ind ? (NSInteger)[bar.subviews indexOfObject:ind] : NSNotFound;
    // Đúng chỗ rồi thì thôi, tránh chèn đi chèn lại gây vòng lặp layout:
    // thứ tự phải là [..., pill, indicator, mục đầu tiên, ...] liền nhau.
    BOOL pillOK = (pillIdx != NSNotFound && pillIdx < firstIdx && (firstIdx - pillIdx) <= 2);
    BOOL indOK = (!ind || indIdx == pillIdx + 1 || (pillIdx == NSNotFound && indIdx == firstIdx - 1));
    if (pillOK && indOK) return;
    if (pill) [pill removeFromSuperview];
    if (ind) [ind removeFromSuperview];
    firstIdx = (NSInteger)[bar.subviews indexOfObject:firstItem];
    if (pill) [bar insertSubview:pill atIndex:firstIdx];
    if (ind) [bar insertSubview:ind atIndex:firstIdx + (pill ? 1 : 0)];
}

// Lớp vệt sáng shader (1.4.0): render 1 ảnh tĩnh cho đúng kích thước
// rồi để UIImageView nằm trên cùng của holder (trên asset tĩnh). Trả về
// YES nếu lớp shader đang hiện; khi đó asset tĩnh được giảm độ rõ để
// hai lớp viền sáng không chồng lên nhau thành quá chói. Nơi gọi PHẢI
// đặt alpha cho asset TRƯỚC khi gọi hàm này (mọi đường refresh hiện tại
// đều vậy) để phép giảm không bị cộng dồn qua nhiều lần refresh.
// Kéo trượt không đụng vào lớp này: nó là con của cục glass, đi theo
// transform chung — không tốn thêm chi phí theo từng khung hình.
- (BOOL)updateSpecularInHolder:(UIView *)holder size:(CGSize)size intensity:(CGFloat)intensity alpha:(CGFloat)alpha {
    UIImageView *spec = (UIImageView *)[holder viewWithTag:LGB_SPEC_TAG];
    UIImage *img = nil;
    if (pShaderGlass && size.width >= 10 && size.height >= 10) {
        img = LGBSpecularImage(size, [UIScreen mainScreen].scale, intensity);
    }
    if (!img) {
        if (spec) spec.hidden = YES;
        return NO;
    }
    if (!spec) {
        spec = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, size.width, size.height)];
        spec.tag = LGB_SPEC_TAG;
        spec.userInteractionEnabled = NO;
        spec.contentMode = UIViewContentModeScaleToFill;
        [holder addSubview:spec];
    }
    spec.frame = CGRectMake(0, 0, size.width, size.height);
    spec.image = img;
    spec.alpha = alpha;
    spec.hidden = NO;
    [holder bringSubviewToFront:spec];
    UIImageView *asset = (UIImageView *)[holder viewWithTag:LGB_ASSET_TAG];
    if (asset) asset.alpha *= 0.55;
    return YES;
}

// Khung viên thuốc nền: đo theo vùng nội dung thật của bar (trừ phần
// tai thỏ/home indicator) và lề do người dùng chỉnh trong Cài đặt — bản
// cũ tự trừ 14pt + cao tối đa 56 nên nhỏ hơn nền gốc của Messenger.
- (CGRect)pillFrameForBar:(UIView *)bar {
    CGFloat bottomInset = 0;
    UIWindow *win = bar.window;
    if (win && CGRectGetMaxY([bar convertRect:bar.bounds toView:win]) >= win.bounds.size.height - 1.0) {
        bottomInset = win.safeAreaInsets.bottom;
    }
    CGFloat contentH = bar.bounds.size.height - bottomInset;
    CGFloat pillH = contentH - 8.0;
    if (pillH < 30.0) pillH = MAX(26.0, contentH - 4.0);
    CGFloat inset = MIN(MAX(pPillInset, 0.0), bar.bounds.size.width / 4.0);
    return CGRectMake(inset, (contentH - pillH) / 2.0,
                      bar.bounds.size.width - inset * 2.0, pillH);
}

- (UIView *)pillBackgroundInBar:(UIView *)bar frame:(CGRect)frame belowItems:(NSArray<UIView *> *)items {
    UIView *existing = [bar viewWithTag:LGB_BG_TAG];
    if (existing) {
        existing.frame = frame;
        UIVisualEffectView *fx = nil;
        for (UIView *sub in existing.subviews) {
            if ([sub isKindOfClass:[UIVisualEffectView class]]) { fx = (UIVisualEffectView *)sub; break; }
        }
        if (fx) {
            fx.layer.cornerRadius = frame.size.height / 2.0;
            for (UIView *sub in fx.contentView.subviews) {
                sub.backgroundColor = [LGBGlassTintColor() colorWithAlphaComponent:0.14];
                sub.frame = fx.bounds;
            }
            fx.alpha = pGlassAlpha;
        }
        UIImageView *asset = (UIImageView *)[existing viewWithTag:LGB_ASSET_TAG];
        if (asset) {
            asset.frame = existing.bounds;
            asset.image = LGBGlassImageForSize(existing.bounds.size);
            asset.alpha = 0.55 * pGlassAlpha;
        }
        [self updateSpecularInHolder:existing size:existing.bounds.size intensity:0.8 alpha:pGlassAlpha];
        [self placeGlassViewsInBar:bar belowItems:items];
        return existing;
    }
    UIView *holder = [[UIView alloc] initWithFrame:frame];
    holder.tag = LGB_BG_TAG;
    holder.userInteractionEnabled = NO;
    holder.backgroundColor = [UIColor clearColor];

    UIVisualEffectView *fx = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
    fx.frame = holder.bounds;
    fx.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    fx.layer.cornerRadius = frame.size.height / 2.0;
    fx.layer.masksToBounds = YES;
    fx.layer.borderWidth = 0.8;
    fx.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
    fx.alpha = pGlassAlpha;
    UIView *tint = [[UIView alloc] initWithFrame:fx.bounds];
    tint.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tint.backgroundColor = [LGBGlassTintColor() colorWithAlphaComponent:0.14];
    tint.userInteractionEnabled = NO;
    [fx.contentView addSubview:tint];
    [holder addSubview:fx];
    UIImageView *asset = [[UIImageView alloc] initWithFrame:holder.bounds];
    asset.tag = LGB_ASSET_TAG;
    asset.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    asset.image = LGBGlassImageForSize(holder.bounds.size);
    asset.alpha = 0.55 * pGlassAlpha;
    asset.userInteractionEnabled = NO;
    [holder addSubview:asset];
    NSInteger idx = [self glassInsertIndexInBar:bar items:items];
    [bar insertSubview:holder atIndex:idx];
    [self updateSpecularInHolder:holder size:frame.size intensity:0.8 alpha:pGlassAlpha];
    return holder;
}

// Cục glass chọn ở 1.3.0: blur SỐNG trở lại bên trong (để nhìn xuyên
// qua và làm mờ nội dung phía sau như kính thật trong ảnh mẫu của anh)
// + nhuộm nhẹ màu chọn + asset kính trong hơn đắp trên cùng. Kéo vẫn
// mượt vì từ 1.3.0 cục glass di chuyển bằng transform, không đổi frame.
- (void)refreshIndicator:(UIView *)ind {
    if (!ind) return;
    ind.backgroundColor = [UIColor clearColor];
    CGFloat h = ind.bounds.size.height;
    ind.layer.shadowColor = [UIColor blackColor].CGColor;
    ind.layer.shadowOpacity = 0.22;
    ind.layer.shadowRadius = 7.0;
    ind.layer.shadowOffset = CGSizeMake(0, 2);
    if (ind.bounds.size.width > 0 && h > 0) {
        ind.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:ind.bounds
                                                          cornerRadius:h / 2.0].CGPath;
    }
    for (UIView *sub in ind.subviews) {
        if ([sub isKindOfClass:[UIVisualEffectView class]]) {
            UIVisualEffectView *fx = (UIVisualEffectView *)sub;
            fx.frame = ind.bounds;
            fx.layer.cornerRadius = h / 2.0;
            fx.alpha = pBlobAlpha;
            for (UIView *s2 in fx.contentView.subviews) {
                if (s2.tag == LGB_TINT_COLOR_TAG) {
                    s2.frame = fx.bounds;
                    s2.backgroundColor = [LGBSelectedColor() colorWithAlphaComponent:0.18];
                }
            }
        } else if (sub.tag == LGB_ASSET_TAG) {
            sub.frame = ind.bounds;
            ((UIImageView *)sub).image = LGBGlassImageForSize(ind.bounds.size);
            sub.alpha = pBlobAlpha;
        }
    }
    [self updateSpecularInHolder:ind size:ind.bounds.size intensity:1.0 alpha:pBlobAlpha];
}

- (UIView *)indicatorInBar:(UIView *)bar belowItems:(NSArray<UIView *> *)items {
    UIView *ind = [bar viewWithTag:LGB_INDICATOR_TAG];
    if (ind) {
        if (self.previewIndex < 0) [self placeGlassViewsInBar:bar belowItems:items];
        return ind;
    }
    ind = [[UIView alloc] initWithFrame:CGRectZero];
    ind.tag = LGB_INDICATOR_TAG;
    ind.userInteractionEnabled = NO;
    ind.backgroundColor = [UIColor clearColor];

    UIVisualEffectView *fx = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
    fx.frame = ind.bounds;
    fx.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    fx.layer.masksToBounds = YES;
    fx.layer.borderWidth = 0.9;
    fx.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.38].CGColor;
    fx.alpha = pBlobAlpha;
    UIView *colorTint = [[UIView alloc] initWithFrame:fx.bounds];
    colorTint.tag = LGB_TINT_COLOR_TAG;
    colorTint.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    colorTint.backgroundColor = [LGBSelectedColor() colorWithAlphaComponent:0.18];
    colorTint.userInteractionEnabled = NO;
    [fx.contentView addSubview:colorTint];
    [ind addSubview:fx];

    UIImageView *asset = [[UIImageView alloc] initWithFrame:ind.bounds];
    asset.tag = LGB_ASSET_TAG;
    asset.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    asset.alpha = pBlobAlpha;
    asset.userInteractionEnabled = NO;
    [ind addSubview:asset];

    NSInteger idx = [self glassInsertIndexInBar:bar items:items];
    [bar insertSubview:ind atIndex:idx];
    [self placeGlassViewsInBar:bar belowItems:items];
    return ind;
}

// Khung cục glass: đo theo khung Ô MỤC THẬT (gồm cả chữ bên dưới icon)
// nhân với tỉ lệ % người dùng chỉnh, rồi KẸP cho nằm gọn trong viên
// thuốc nền — bản cũ tự tính số cứng nên glass nhỏ hơn ô và nhô ra
// ngoài nền ở mục cuối (ảnh anh chụp ở mục Menu).
- (CGRect)indicatorFrameForItemFrame:(CGRect)itemFrame limitRect:(CGRect)limit {
    CGFloat w = itemFrame.size.width * (pBlobWidthPct / 100.0);
    CGFloat h = itemFrame.size.height * (pBlobHeightPct / 100.0);
    w = MIN(MAX(w, 40.0), MAX(40.0, limit.size.width - 6.0));
    h = MIN(MAX(h, 26.0), MAX(26.0, limit.size.height - 4.0));
    CGFloat cx = CGRectGetMidX(itemFrame);
    CGFloat minCx = CGRectGetMinX(limit) + w / 2.0 + 3.0;
    CGFloat maxCx = CGRectGetMaxX(limit) - w / 2.0 - 3.0;
    cx = (maxCx >= minCx) ? MIN(MAX(cx, minCx), maxCx) : CGRectGetMidX(limit);
    CGFloat cy = CGRectGetMidY(itemFrame);
    CGFloat minCy = CGRectGetMinY(limit) + h / 2.0 + 2.0;
    CGFloat maxCy = CGRectGetMaxY(limit) - h / 2.0 - 2.0;
    cy = (maxCy >= minCy) ? MIN(MAX(cy, minCy), maxCy) : CGRectGetMidY(limit);
    return CGRectMake(cx - w / 2.0, cy - h / 2.0, w, h);
}

// Khung NỘI DUNG THẬT của một mục, tính trong hệ toạ độ của bar: hợp
// nhất khung của chính mục + mọi icon/chữ trong cây con của nó (chữ có
// thể tràn ra ngoài khung mục) + nhãn anh em nằm cùng cột ngay dưới mục
// (Messenger để chữ tách khỏi ô icon). Bản 1.2.0 chỉ đo khung mục nên
// glass hụt mất phần chữ.
- (CGRect)contentRectForItem:(UIView *)item inBar:(UIView *)bar {
    CGRect r = item.frame;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:item];
    while (stack.count > 0) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if (v != item) {
            // Bỏ qua cả cây con của huy hiệu (cục đỏ "30+" nằm trong ô
            // mục): không tính vào khung nội dung, kẻo glass phình lên
            // theo huy hiệu. Huy hiệu dạng viên thuốc có thể rộng hơn
            // 30pt nên soi thêm nền đỏ đặc kích thước nhỏ.
            BOOL skip = LGBLooksLikeBadge(v);
            if (!skip) {
                UIColor *bg = v.backgroundColor;
                CGFloat rr = 0, gg = 0, bb = 0, aa = 0;
                if (bg && [bg getRed:&rr green:&gg blue:&bb alpha:&aa] && aa >= 0.5 &&
                    rr > 0.75 && gg < 0.45 && bb < 0.45 &&
                    v.bounds.size.height <= 32 && v.bounds.size.width <= 52) {
                    skip = YES;
                }
            }
            if (skip) continue;
            BOOL isIconOrLabel = [v isKindOfClass:[UIImageView class]] ||
                                 [v isKindOfClass:[UILabel class]] ||
                                 [NSStringFromClass([v class]) containsString:@"Label"];
            if (isIconOrLabel) {
                r = CGRectUnion(r, [v convertRect:v.bounds toView:bar]);
            }
        }
        for (UIView *sub in v.subviews) {
            if (sub.tag != LGB_BG_TAG && sub.tag != LGB_INDICATOR_TAG) [stack addObject:sub];
        }
    }
    // nhãn anh em: subview trực tiếp của bar, cùng cột với mục, ở dưới mục
    for (UIView *sub in bar.subviews) {
        if (![sub isKindOfClass:[UILabel class]]) continue;
        if ([sub isDescendantOfView:item]) continue;
        CGRect lf = sub.frame;
        CGFloat lcx = CGRectGetMidX(lf);
        if (lcx >= CGRectGetMinX(item.frame) - 8 && lcx <= CGRectGetMaxX(item.frame) + 8 &&
            CGRectGetMinY(lf) >= CGRectGetMinY(item.frame) - 6) {
            r = CGRectUnion(r, lf);
        }
    }
    return r;
}

- (CGRect)targetFrameForIndex:(NSInteger)idx bar:(UIView *)bar items:(NSArray<UIView *> *)items {
    CGRect pill = [self pillFrameForBar:bar];
    CGRect content = [self contentRectForItem:items[idx] inBar:bar];
    return [self indicatorFrameForItemFrame:content limitRect:pill];
}

// Độ nảy từ Cài đặt: 0% = không nảy (damping 1.0), 100% = nảy mạnh (0.45).
- (CGFloat)springDamping {
    return 1.0 - 0.55 * (pSpringPct / 100.0);
}

// Di chuyển cục glass bằng TRANSFORM (frame giữ nguyên = vị trí đã chốt
// của mục hiện tại), hết hiệu ứng thì mới chốt frame mới. Đổi frame theo
// từng nhịp chạm như bản cũ bắt thanh bar của Messenger tính lại bố cục
// liên tục — đó là thủ phạm gây khựng giật khi kéo.
- (void)animateIndicatorToIndex:(NSInteger)idx bar:(UIView *)bar items:(NSArray<UIView *> *)items completion:(void (^)(void))completion {
    UIView *ind = [self indicatorInBar:bar belowItems:items];
    CGRect target = [self targetFrameForIndex:idx bar:bar items:items];
    CGFloat dx = CGRectGetMidX(target) - CGRectGetMidX(ind.frame);
    if (fabs(dx) < 0.5 && CGAffineTransformIsIdentity(ind.transform)) {
        ind.frame = target;
        [self refreshIndicator:ind];
        if (completion) completion();
        return;
    }
    [UIView animateWithDuration:0.5 delay:0
         usingSpringWithDamping:[self springDamping] initialSpringVelocity:0.5
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
                         ind.transform = CGAffineTransformMakeTranslation(dx, 0);
                     }
                     completion:^(__unused BOOL finished) {
                         ind.frame = target;
                         ind.transform = CGAffineTransformIdentity;
                         [self refreshIndicator:ind];
                         if (completion) completion();
                     }];
}

- (void)attachPanToBar:(UIView *)bar {
    if (!pDragEnabled) return;
    for (UIGestureRecognizer *gr in bar.gestureRecognizers) {
        if ([gr isKindOfClass:[UILongPressGestureRecognizer class]] && gr.delegate == self) return;
    }
    // Nhấn-giữ với thời gian 0 = nhận diện NGAY khi chạm (bản cũ dùng
    // pan phải chờ qua ngưỡng nhận diện nên đầu cú kéo bị trễ rồi nhảy).
    // Chạm thường vẫn nguyên vẹn: chỉ khi ngón tay di chuyển >= 4pt thì
    // mới tính là kéo (xem handlePan), chạm nhả ngay thì không đụng gì.
    UILongPressGestureRecognizer *pan = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    pan.delegate = self;
    pan.minimumPressDuration = 0;
    pan.allowableMovement = CGFLOAT_MAX;
    pan.cancelsTouchesInView = NO;
    [bar addGestureRecognizer:pan];
    LGBLog(@"Da gan cu chi keo truot len bar class %@", NSStringFromClass([bar class]));
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

- (void)hapticTick {
    if (!pHaptics) return;
    UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [gen prepare];
    [gen impactOccurred];
}

// ---------------------------------------------------------- đường A: UITabBar
- (NSArray<UIView *> *)tabBarButtons:(UITabBar *)bar {
    NSMutableArray<UIView *> *out = [NSMutableArray array];
    for (UIView *sub in bar.subviews) {
        if ([NSStringFromClass([sub class]) isEqualToString:@"UITabBarButton"]) [out addObject:sub];
    }
    [out sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return a.frame.origin.x < b.frame.origin.x ? NSOrderedAscending : NSOrderedDescending;
    }];
    return out;
}

- (void)styleTabBar:(UITabBar *)bar {
    if (!pEnabled || bar.bounds.size.width < 50) return;
    self.tabBar = bar;
    bar.backgroundImage = [[UIImage alloc] init];
    bar.shadowImage = [[UIImage alloc] init];
    bar.backgroundColor = [UIColor clearColor];
    bar.translucent = YES;
    bar.tintColor = LGBSelectedColor();
    if (@available(iOS 10.0, *)) {
        bar.unselectedItemTintColor = [UIColor colorWithWhite:0.62 alpha:1.0];
    }

    CGRect pillFrame = [self pillFrameForBar:bar];
    NSArray<UIView *> *buttons = [self tabBarButtons:bar];
    [self pillBackgroundInBar:bar frame:pillFrame belowItems:buttons];

    if (buttons.count == 0 || bar.items.count == 0) return;
    NSInteger sel = bar.selectedItem ? (NSInteger)[bar.items indexOfObject:bar.selectedItem] : 0;
    if (sel == NSNotFound) sel = 0;
    if (sel >= (NSInteger)buttons.count) sel = (NSInteger)buttons.count - 1;
    UIView *ind = [self indicatorInBar:bar belowItems:buttons];
    CGRect target = [self targetFrameForIndex:sel bar:bar items:buttons];
    if (self.previewIndex < 0) { // đang kéo thì handlePan tự lo vị trí
        ind.frame = target;
        ind.transform = CGAffineTransformIdentity;
    }
    [self refreshIndicator:ind];
    [self attachPanToBar:bar];
    [self writeDiagState:[NSString stringWithFormat:@"Da thay UITabBar chuan (%lu muc) — da ap kinh",
                          (unsigned long)bar.items.count]];
}

- (void)tabBarSelectionChanged:(UITabBar *)bar {
    if (self.previewIndex >= 0) return; // đang kéo, thả tay mới chốt
    NSArray<UIView *> *buttons = [self tabBarButtons:bar];
    if (buttons.count == 0 || bar.items.count == 0 || !bar.selectedItem) return;
    NSInteger sel = (NSInteger)[bar.items indexOfObject:bar.selectedItem];
    if (sel == NSNotFound || sel >= (NSInteger)buttons.count) return;
    [self animateIndicatorToIndex:sel bar:bar items:buttons completion:nil];
}

- (void)selectTabBarIndex:(NSInteger)idx bar:(UITabBar *)bar {
    if (idx < 0 || idx >= (NSInteger)bar.items.count) return;
    UITabBarItem *item = bar.items[idx];
    id delegate = bar.delegate;
    if ([delegate isKindOfClass:[UITabBarController class]]) {
        ((UITabBarController *)delegate).selectedIndex = idx;
    } else {
        bar.selectedItem = item;
        if ([delegate respondsToSelector:@selector(tabBar:didSelectItem:)]) {
            [delegate tabBar:bar didSelectItem:item];
        }
    }
    LGBLog(@"Chon muc UITabBar thu %ld", (long)idx);
}

// ---------------------------------------------------------- đường B: bar tự chế
// Nhuộm màu một cây view con (icon + chữ), bỏ qua huy hiệu và bỏ qua hai
// lớp kính của chính tweak này.
- (void)tintTree:(UIView *)v color:(UIColor *)color selected:(BOOL)selected {
    if (v.tag == LGB_BG_TAG || v.tag == LGB_INDICATOR_TAG) return;
    if (LGBLooksLikeBadge(v)) return;
    if ([v isKindOfClass:[UIImageView class]]) {
        v.tintColor = color;
        UIImage *img = ((UIImageView *)v).image;
        if (img && img.renderingMode == UIImageRenderingModeAlwaysOriginal) {
            ((UIImageView *)v).image = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        }
    } else if ([v isKindOfClass:[UILabel class]]) {
        UILabel *lab = (UILabel *)v;
        UIColor *bg = lab.backgroundColor;
        CGFloat rr = 0, gg = 0, bb = 0, aa = 0;
        BOOL hasBg = bg && [bg getRed:&rr green:&gg blue:&bb alpha:&aa] && aa >= 0.5;
        if (!hasBg) {
            lab.textColor = color; // nhãn có nền đặc (kiểu huy hiệu) thì giữ nguyên
        }
    }
    for (UIView *sub in v.subviews) [self tintTree:sub color:color selected:selected];
}

- (void)applyCustomSelectionVisual {
    if (!self.customBar || !self.customItems) return;
    UIColor *sel = LGBSelectedColor();
    UIColor *unsel = [UIColor colorWithWhite:0.62 alpha:1.0];
    NSInteger active = (self.previewIndex >= 0) ? self.previewIndex : self.customSelectedIndex;
    for (NSInteger i = 0; i < (NSInteger)self.customItems.count; i++) {
        [self tintTree:self.customItems[i] color:(i == active ? sel : unsel) selected:(i == active)];
    }
    UIView *ind = [self indicatorInBar:self.customBar belowItems:self.customItems];
    [self refreshIndicator:ind];
}

- (void)styleCustomBar:(UIView *)bar items:(NSArray<UIView *> *)items {
    if (!pEnabled || !bar || items.count < 2) return;
    BOOL isNewBar = (self.customBar != bar);
    self.customBar = bar;
    self.customItems = items;
    if (self.customSelectedIndex >= (NSInteger)items.count) self.customSelectedIndex = 0;

    CGRect pillFrame = [self pillFrameForBar:bar];
    [self pillBackgroundInBar:bar frame:pillFrame belowItems:items];

    UIView *ind = [self indicatorInBar:bar belowItems:items];
    CGRect target = [self targetFrameForIndex:self.customSelectedIndex bar:bar items:items];
    if (self.previewIndex < 0) {
        ind.frame = target;
        ind.transform = CGAffineTransformIdentity;
    }
    [self refreshIndicator:ind];
    [self applyCustomSelectionVisual];
    [self attachPanToBar:bar];

    if (isNewBar) {
        for (UIView *item in items) {
            UIControl *ctrl = [item isKindOfClass:[UIControl class]] ? (UIControl *)item : nil;
            if (!ctrl) {
                for (UIView *sub in item.subviews) {
                    if ([sub isKindOfClass:[UIControl class]]) { ctrl = (UIControl *)sub; break; }
                }
            }
            if (ctrl) [ctrl addTarget:self action:@selector(customItemTapped:) forControlEvents:UIControlEventTouchUpInside];
        }
        NSMutableString *sig = [NSMutableString stringWithString:NSStringFromClass([bar class])];
        for (UIView *item in items) [sig appendFormat:@"|%@", NSStringFromClass([item class])];
        if (![sig isEqualToString:self.loggedCandidateSignature]) {
            self.loggedCandidateSignature = sig;
            LGBLog(@"Da ap kinh len bar tu che: %@ (frame %@, %lu muc)",
                   sig, NSStringFromCGRect(bar.frame), (unsigned long)items.count);
        }
        [self writeDiagState:[NSString stringWithFormat:@"Da thay bar tu che %@ (%lu muc) — da ap kinh",
                              NSStringFromClass([bar class]), (unsigned long)items.count]];
    }
}

- (void)customItemTapped:(UIControl *)sender {
    if (!self.customBar || !self.customItems) return;
    for (NSInteger i = 0; i < (NSInteger)self.customItems.count; i++) {
        UIView *item = self.customItems[i];
        if (sender == (UIControl *)item || [sender isDescendantOfView:item] || [item isDescendantOfView:sender]) {
            self.customSelectedIndex = i;
            [self tabBarSelectionChangedCustom];
            return;
        }
    }
}

- (void)selectCustomIndex:(NSInteger)idx {
    if (!self.customBar || idx < 0 || idx >= (NSInteger)self.customItems.count) return;
    self.customSelectedIndex = idx;
    UIView *item = self.customItems[idx];
    UIControl *ctrl = [item isKindOfClass:[UIControl class]] ? (UIControl *)item : nil;
    if (!ctrl) {
        for (UIView *sub in item.subviews) {
            if ([sub isKindOfClass:[UIControl class]]) { ctrl = (UIControl *)sub; break; }
        }
    }
    if (ctrl) {
        [ctrl sendActionsForControlEvents:UIControlEventTouchUpInside];
        LGBLog(@"Chon muc tu che thu %ld qua UIControl %@", (long)idx, NSStringFromClass([ctrl class]));
    } else {
        LGBLog(@"Chon muc tu che thu %ld: muc khong phai UIControl (class %@) — chua mo phong cham duoc, chi doi mau + glass",
               (long)idx, NSStringFromClass([item class]));
    }
    [self applyCustomSelectionVisual];
}

// ---------------------------------------------------------- kéo trượt
- (void)tabBarSelectionChangedCustom {
    if (!self.customBar || !self.customItems || self.previewIndex >= 0) return;
    [self animateIndicatorToIndex:self.customSelectedIndex bar:self.customBar items:self.customItems completion:nil];
    [self applyCustomSelectionVisual];
}

- (NSInteger)nearestIndex:(CGFloat)x centers:(NSArray<NSNumber *> *)centers {
    NSInteger best = 0;
    CGFloat bestDist = CGFLOAT_MAX;
    for (NSInteger i = 0; i < (NSInteger)centers.count; i++) {
        CGFloat d = fabs(x - centers[i].doubleValue);
        if (d < bestDist) { bestDist = d; best = i; }
    }
    return best;
}

- (void)handlePan:(UILongPressGestureRecognizer *)pan {
    if (!pEnabled || !pDragEnabled) return;
    UIView *bar = pan.view;
    if (!bar) return;
    BOOL isTab = [bar isKindOfClass:[UITabBar class]];
    NSArray<UIView *> *items = nil;
    if (isTab) items = [self tabBarButtons:(UITabBar *)bar];
    else if (bar == self.customBar) items = self.customItems;
    if (!items || items.count < 2) return;

    NSMutableArray<NSNumber *> *centers = [NSMutableArray array];
    for (UIView *it in items) [centers addObject:@(CGRectGetMidX(it.frame))];
    CGFloat x = [pan locationInView:bar].x;
    CGFloat minX = centers.firstObject.doubleValue;
    CGFloat maxX = centers.lastObject.doubleValue;
    CGFloat clampedX = MIN(MAX(x, minX), maxX);
    NSInteger nearIdx = [self nearestIndex:clampedX centers:centers];

    UIView *ind = [self indicatorInBar:bar belowItems:items];
    CGRect pill = [self pillFrameForBar:bar];

    switch (pan.state) {
        case UIGestureRecognizerStateBegan: {
            // Mới chạm xuống: ghi điểm bắt đầu, CHƯA tính là kéo.
            self.dragEngaged = NO;
            self.dragBlob = nil;
            self.dragStartX = x;
            self.lastDragX = x;
            break;
        }
        case UIGestureRecognizerStateChanged: {
            if (!self.dragEngaged) {
                if (fabs(x - self.dragStartX) < 4.0) return; // vẫn là chạm thường
                if (ind.frame.size.width < 10) return; // glass chưa được tạo khung
                self.dragEngaged = YES;
                self.previewIndex = nearIdx;
                self.dragBlob = ind;
                self.dragSettledCenterX = CGRectGetMidX(ind.frame);
                [UIView animateWithDuration:0.16 animations:^{
                    ind.transform = CGAffineTransformMakeScale(1.05, 1.05);
                }];
                [self hapticTick];
                if (!isTab) [self applyCustomSelectionVisual];
            }
            // Di chuyển bằng TRANSFORM: frame giữ nguyên (vị trí đã chốt),
            // chỉ dời lớp đồ hoạ theo tay — không bắt bar tính lại bố cục.
            UIView *blob = self.dragBlob ?: ind;
            CGFloat tx = clampedX - self.dragSettledCenterX;
            CGFloat txMin = CGRectGetMinX(pill) + 3.0 - CGRectGetMinX(blob.frame);
            CGFloat txMax = CGRectGetMaxX(pill) - 3.0 - CGRectGetMaxX(blob.frame);
            tx = MIN(MAX(tx, txMin), txMax);
            // Hiệu ứng "kính dẻo": kéo càng nhanh cục glass càng giãn
            // ngang ra (mức giãn chỉnh được trong Cài đặt), chậm lại tự co.
            CGFloat dx = x - self.lastDragX;
            self.lastDragX = x;
            CGFloat maxStretch = 0.30 * (pStretchPct / 100.0);
            CGFloat stretch = (maxStretch > 0.001)
                ? MIN(maxStretch, fabs(dx) / 110.0 * (maxStretch / 0.20)) : 0;
            CGFloat sx = 1.05 * (1.0 + stretch);
            CGFloat sy = 1.05 / (1.0 + stretch * 0.55);
            CGAffineTransform tr = CGAffineTransformMakeTranslation(tx, 0);
            tr = CGAffineTransformScale(tr, sx, sy);
            blob.transform = tr;
            if (nearIdx != self.previewIndex) {
                self.previewIndex = nearIdx;
                [self hapticTick];
                if (!isTab) [self applyCustomSelectionVisual];
            }
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            if (!self.dragEngaged) return; // chạm thường: để app tự xử lý
            NSInteger target = nearIdx;
            self.dragEngaged = NO;
            self.dragBlob = nil;
            self.previewIndex = -1;
            [self finishDragToIndex:target bar:bar isTabBar:isTab];
            break;
        }
        default:
            break;
    }
}

- (void)finishDragToIndex:(NSInteger)idx bar:(UIView *)bar isTabBar:(BOOL)isTab {
    NSArray<UIView *> *items = isTab ? [self tabBarButtons:(UITabBar *)bar] : self.customItems;
    if (!items || idx < 0 || idx >= (NSInteger)items.count) return;
    [self animateIndicatorToIndex:idx bar:bar items:items completion:^{
        if (isTab) [self selectTabBarIndex:idx bar:(UITabBar *)bar];
        else [self selectCustomIndex:idx];
    }];
}

// ---------------------------------------------------------- quét bar tự chế
- (void)appDidBecomeActive:(NSNotification *)note {
    (void)note;
    // Quay lại Messenger là nạp lại thông số mới nhất + áp lại ngay —
    // dự phòng cho trường hợp tín hiệu báo thay đổi từ Cài đặt thất lạc.
    [self reloadPrefs];
    [self scanTick:nil];
}

- (UIWindow *)activeWindow {
    UIApplication *app = [UIApplication sharedApplication];
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        if (ws.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *w in ws.windows) {
            if (w.isKeyWindow) return w;
        }
        if (ws.windows.count > 0) return ws.windows.firstObject;
    }
    return nil;
}

- (void)dumpBottomHierarchy:(UIWindow *)win {
    if (self.dumpedBottomHierarchy || !win) return;
    self.dumpedBottomHierarchy = YES;
    NSMutableString *out = [NSMutableString stringWithString:@"--- Cay view vung day (chan doan bar tu che) ---\n"];
    NSInteger lines = 0;
    [self dumpView:win window:win depth:0 into:out lines:&lines];
    LGBLog(@"%@", out);
}

// Đệ quy bằng method thường — KHÔNG dùng block tự gọi chính nó: dưới ARC
// + -Werror, block bắt chính nó bị lỗi -Warc-retain-cycles lúc biên dịch
// (đã dính thật ở bản build đầu của LiquidGlassBar, dòng 629/646).
- (void)dumpView:(UIView *)v window:(UIWindow *)win depth:(NSInteger)depth into:(NSMutableString *)out lines:(NSInteger *)lines {
    if (*lines > 220) return;
    CGRect inWin = [v convertRect:v.bounds toView:win];
    if (CGRectGetMaxY(inWin) > win.bounds.size.height * 0.62 && v.bounds.size.width > 24) {
        (*lines)++;
        NSMutableString *pad = [NSMutableString string];
        for (NSInteger i = 0; i < depth; i++) [pad appendString:@"  "];
        [out appendFormat:@"%@%@ %@\n", pad, NSStringFromClass([v class]), NSStringFromCGRect(v.frame)];
    }
    if (depth < 14) {
        for (UIView *sub in v.subviews) {
            [self dumpView:sub window:win depth:depth + 1 into:out lines:lines];
        }
    }
}

- (BOOL)subtree:(UIView *)v hasIconOrLabelAtDepth:(NSInteger)depth {
    if ([v isKindOfClass:[UIImageView class]] || [v isKindOfClass:[UILabel class]]) return YES;
    if (depth >= 4) return NO;
    for (UIView *sub in v.subviews) {
        if ([self subtree:sub hasIconOrLabelAtDepth:depth + 1]) return YES;
    }
    return NO;
}

// Một view con có "trông giống mục của tab bar" không: có icon hoặc chữ,
// hoặc chính nó là nút bấm.
- (BOOL)viewLooksLikeTabItem:(UIView *)v {
    if ([v isKindOfClass:[UIControl class]]) return YES;
    if (v.gestureRecognizers.count > 0) return YES;
    return [self subtree:v hasIconOrLabelAtDepth:0];
}

- (void)collectCandidatesInView:(UIView *)v window:(UIWindow *)win depth:(NSInteger)depth
                           best:(UIView **)best bestScore:(NSInteger *)bestScore
                      bestItems:(NSArray<UIView *> **)bestItems {
    if (!v || depth > 14 || v.tag == LGB_BG_TAG || v.tag == LGB_INDICATOR_TAG) return;
    if ([v isKindOfClass:[UITabBar class]]) return; // đường A lo riêng
    CGRect inWin = [v convertRect:v.bounds toView:win];
    CGFloat w = v.bounds.size.width, h = v.bounds.size.height;
    BOOL inBottom = CGRectGetMaxY(inWin) > win.bounds.size.height - 150.0;
    BOOL sizeOK = (h >= 40 && h <= 115 && w > win.bounds.size.width * 0.6);
    NSInteger rawCount = 0; // không đếm 2 lớp kính của tweak khi quét lại bar đã áp kính
    for (UIView *sub in v.subviews) {
        if (sub.tag != LGB_BG_TAG && sub.tag != LGB_INDICATOR_TAG) rawCount++;
    }
    if (inBottom && sizeOK && rawCount >= 3 && rawCount <= 8) {
        NSMutableArray<UIView *> *items = [NSMutableArray array];
        for (UIView *sub in v.subviews) {
            if (sub.tag == LGB_BG_TAG || sub.tag == LGB_INDICATOR_TAG) continue;
            if (sub.bounds.size.width < 26 || sub.bounds.size.height < 20) continue;
            if (![self viewLooksLikeTabItem:sub]) continue;
            [items addObject:sub];
        }
        if (items.count >= 3 && items.count <= 7) {
            [items sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
                return a.frame.origin.x < b.frame.origin.x ? NSOrderedAscending : NSOrderedDescending;
            }];
            // điểm cộng: các mục cách đều nhau
            NSInteger score = 10;
            CGFloat firstW = items.firstObject.bounds.size.width;
            BOOL even = YES;
            for (UIView *it in items) {
                if (fabs(it.bounds.size.width - firstW) > firstW * 0.6 + 12) even = NO;
            }
            if (even) score += 5;
            if ([v isKindOfClass:[UIControl class]]) score -= 4;
            if (score > *bestScore) {
                *bestScore = score;
                *best = v;
                *bestItems = [items copy];
            }
        }
    }
    for (UIView *sub in v.subviews) {
        [self collectCandidatesInView:sub window:win depth:depth + 1 best:best bestScore:bestScore bestItems:bestItems];
    }
}

- (void)scanTick:(NSTimer *)timer {
    (void)timer;
    // Nạp lại thông số ở MỖI vòng quét (1,5 giây): đổi tuỳ chọn trong
    // Cài đặt là Messenger ăn theo gần như ngay, kể cả khi tín hiệu
    // Darwin báo thay đổi bị thất lạc — sửa triệt để vụ "chỉnh mà
    // không áp dụng" anh báo ở bản 1.2.0.
    LGBLoadPrefs();
    if (!pEnabled) return;
    self.scanCount++;
    if (self.scanCount % 10 == 1) {
        LGBDiagWrite(@"diag_scanCount", @(self.scanCount));
        if (!self.tabBar && !self.customBar) {
            [self writeDiagState:[NSString stringWithFormat:@"Da nap nhung CHUA thay thanh bar nao (da quet %ld lan)",
                                  (long)self.scanCount]];
        }
    }
    // Đã có UITabBar chuẩn đang được áp kính thì khỏi quét đường B.
    if (self.tabBar && self.tabBar.window) return;
    if (self.customBar && self.customBar.window) {
        if (self.previewIndex >= 0) return; // đang kéo: đừng đụng vào bar, tránh giật
        [self styleCustomBar:self.customBar items:self.customItems];
        return;
    }
    UIWindow *win = [self activeWindow];
    if (!win) return;
    [self dumpBottomHierarchy:win];
    UIView *best = nil;
    NSInteger bestScore = -1;
    NSArray<UIView *> *bestItems = nil;
    [self collectCandidatesInView:win window:win depth:0 best:&best bestScore:&bestScore bestItems:&bestItems];
    if (best && bestItems) {
        [self styleCustomBar:best items:bestItems];
    }
}

@end

// ------------------------------------------------------------------ hooks
%hook UITabBar
- (void)layoutSubviews {
    %orig;
    [[LGBManager shared] styleTabBar:self];
}
- (void)setSelectedItem:(UITabBarItem *)item {
    %orig;
    [[LGBManager shared] tabBarSelectionChanged:self];
}
%end

// ------------------------------------------------------------------ ctor
static void LGBPrefsChanged(CFNotificationCenterRef center, void *observer,
                            CFStringRef name, const void *object,
                            CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[LGBManager shared] reloadPrefs];
    });
}

%ctor {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
        if (![bid isEqualToString:@"com.facebook.Messenger"]) return;
        LGBLoadPrefs();
        [[LGBManager shared] start];
        // Biên dịch shader kính sẵn ở luồng nền để lần hiện đầu tiên
        // không khựng; kết quả ghi vào chẩn đoán trong Cài đặt.
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            BOOL ok = LGBGlassShaderWarmUp();
            LGBLog(@"Shader kinh (phong LiquidGlaze): %@", ok ? @"san sang" : @"khong dung duoc - lui ve kinh 1.3.0");
            LGBDiagWrite(@"diag_shaderGlass", ok ? @"OK" : @"FAIL");
        });
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            LGBPrefsChanged, (__bridge CFStringRef)LGB_PREFS_NOTIFICATION, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
