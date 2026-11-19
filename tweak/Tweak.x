// LiquidGlassBar 1.1.0 — thanh tab bar kiểu Liquid Glass cho Messenger:
// nền kính mờ dạng viên thuốc nổi, cục glass chọn kéo trượt ngang qua lại
// để chọn mục, icon của mục được chọn đổi sang màu tuỳ chọn trong Cài đặt.
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
static const NSInteger LGB_TINT_WHITE_TAG = 712011;
static const NSInteger LGB_TINT_COLOR_TAG = 712012;

static BOOL pEnabled = YES;
static BOOL pDragEnabled = YES;
static BOOL pHaptics = YES;
static BOOL pDebug = YES;
static CGFloat pGlassAlpha = 0.85;
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
    pDragEnabled     = [LGBGetPref(@"dragEnabled", @YES) boolValue];
    pHaptics         = [LGBGetPref(@"haptics", @YES) boolValue];
    pDebug           = [LGBGetPref(@"debug", @YES) boolValue];
    pGlassAlpha      = [LGBGetPref(@"glassAlpha", @0.85) doubleValue];
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
- (void)handlePan:(UIPanGestureRecognizer *)pan;
- (void)customItemTapped:(UIControl *)sender;
- (void)scanTick:(NSTimer *)timer;
- (UIView *)pillBackgroundInBar:(UIView *)bar frame:(CGRect)frame belowItems:(NSArray<UIView *> *)items;
- (UIView *)indicatorInBar:(UIView *)bar belowItems:(NSArray<UIView *> *)items;
- (NSInteger)glassInsertIndexInBar:(UIView *)bar items:(NSArray<UIView *> *)items;
- (void)placeGlassViewsInBar:(UIView *)bar belowItems:(NSArray<UIView *> *)items;
- (void)refreshIndicator:(UIView *)ind;
- (CGRect)indicatorFrameForItemFrame:(CGRect)itemFrame barHeight:(CGFloat)barHeight bottomInset:(CGFloat)bottomInset;
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
    LGBLog(@"Nap lai prefs: enabled=%d drag=%d mauChon=%@ mauKinh=%@ alpha=%.2f",
           pEnabled, pDragEnabled, pSelectedColorHex, pGlassTintHex, pGlassAlpha);
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
    NSInteger idx = [self glassInsertIndexInBar:bar items:items];
    [bar insertSubview:holder atIndex:idx];
    return holder;
}

// Cục glass chọn: từ 1.1.0 là kính TRẮNG MỜ SÁNG như clip mẫu (blur +
// lớp trắng + nhuộm nhẹ màu chọn + viền sáng + bóng đổ), thay cho lớp
// màu chọn alpha 0,25 gần như vô hình trên nền tối ở bản cũ.
- (void)refreshIndicator:(UIView *)ind {
    if (!ind) return;
    ind.backgroundColor = [UIColor clearColor];
    ind.layer.shadowColor = [UIColor blackColor].CGColor;
    ind.layer.shadowOpacity = 0.25;
    ind.layer.shadowRadius = 8.0;
    ind.layer.shadowOffset = CGSizeMake(0, 2);
    ind.layer.cornerRadius = ind.bounds.size.height / 2.0;
    for (UIView *sub in ind.subviews) {
        if (![sub isKindOfClass:[UIVisualEffectView class]]) continue;
        UIVisualEffectView *fx = (UIVisualEffectView *)sub;
        fx.layer.cornerRadius = ind.bounds.size.height / 2.0;
        fx.alpha = 1.0;
        for (UIView *s2 in fx.contentView.subviews) {
            if (s2.tag == LGB_TINT_WHITE_TAG) {
                s2.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.20];
            } else if (s2.tag == LGB_TINT_COLOR_TAG) {
                s2.backgroundColor = [LGBSelectedColor() colorWithAlphaComponent:0.22];
            }
        }
    }
}

- (UIView *)indicatorInBar:(UIView *)bar belowItems:(NSArray<UIView *> *)items {
    UIView *ind = [bar viewWithTag:LGB_INDICATOR_TAG];
    if (ind) {
        [self placeGlassViewsInBar:bar belowItems:items];
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
    UIView *white = [[UIView alloc] initWithFrame:fx.bounds];
    white.tag = LGB_TINT_WHITE_TAG;
    white.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    white.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.20];
    white.userInteractionEnabled = NO;
    [fx.contentView addSubview:white];
    UIView *colorTint = [[UIView alloc] initWithFrame:fx.bounds];
    colorTint.tag = LGB_TINT_COLOR_TAG;
    colorTint.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    colorTint.backgroundColor = [LGBSelectedColor() colorWithAlphaComponent:0.22];
    colorTint.userInteractionEnabled = NO;
    [fx.contentView addSubview:colorTint];
    [ind addSubview:fx];

    NSInteger idx = [self glassInsertIndexInBar:bar items:items];
    [bar insertSubview:ind atIndex:idx];
    [self placeGlassViewsInBar:bar belowItems:items];
    return ind;
}

- (CGRect)indicatorFrameForItemFrame:(CGRect)itemFrame barHeight:(CGFloat)barHeight bottomInset:(CGFloat)bottomInset {
    CGFloat h = MIN(50.0, barHeight - bottomInset - 10.0);
    if (h < 30.0) h = MAX(30.0, barHeight - bottomInset - 6.0);
    CGFloat y = (barHeight - bottomInset - h) / 2.0;
    if (y < 2.0) y = 2.0;
    CGFloat w = MAX(52.0, itemFrame.size.width - 8.0);
    CGFloat x = CGRectGetMidX(itemFrame) - w / 2.0;
    return CGRectMake(x, y, w, h);
}

- (void)attachPanToBar:(UIView *)bar {
    if (!pDragEnabled) return;
    for (UIGestureRecognizer *gr in bar.gestureRecognizers) {
        if ([gr isKindOfClass:[UIPanGestureRecognizer class]] && gr.delegate == self) return;
    }
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    pan.delegate = self;
    pan.cancelsTouchesInView = NO;
    pan.maximumNumberOfTouches = 1;
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

    CGFloat bottomInset = 0;
    UIWindow *win = ((UIView *)bar).window;
    if (win && CGRectGetMaxY([bar convertRect:bar.bounds toView:win]) >= win.bounds.size.height - 1.0) {
        bottomInset = win.safeAreaInsets.bottom;
    }
    CGFloat pillH = MIN(56.0, bar.bounds.size.height - bottomInset - 8.0);
    if (pillH < 34.0) pillH = MAX(30.0, bar.bounds.size.height - bottomInset - 4.0);
    CGRect pillFrame = CGRectMake(14, (bar.bounds.size.height - bottomInset - pillH) / 2.0,
                                  bar.bounds.size.width - 28, pillH);
    NSArray<UIView *> *buttons = [self tabBarButtons:bar];
    [self pillBackgroundInBar:bar frame:pillFrame belowItems:buttons];

    if (buttons.count == 0 || bar.items.count == 0) return;
    NSInteger sel = bar.selectedItem ? (NSInteger)[bar.items indexOfObject:bar.selectedItem] : 0;
    if (sel == NSNotFound) sel = 0;
    if (sel >= (NSInteger)buttons.count) sel = (NSInteger)buttons.count - 1;
    UIView *ind = [self indicatorInBar:bar belowItems:buttons];
    CGRect target = [self indicatorFrameForItemFrame:buttons[sel].frame
                                          barHeight:bar.bounds.size.height
                                        bottomInset:bottomInset];
    if (self.previewIndex < 0) ind.frame = target; // đang kéo thì handlePan tự đặt frame
    ind.layer.cornerRadius = target.size.height / 2.0;
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
    CGFloat bottomInset = 0;
    UIWindow *win = ((UIView *)bar).window;
    if (win && CGRectGetMaxY([bar convertRect:bar.bounds toView:win]) >= win.bounds.size.height - 1.0) {
        bottomInset = win.safeAreaInsets.bottom;
    }
    UIView *ind = [self indicatorInBar:bar belowItems:buttons];
    CGRect target = [self indicatorFrameForItemFrame:buttons[sel].frame
                                          barHeight:bar.bounds.size.height
                                        bottomInset:bottomInset];
    [UIView animateWithDuration:0.45 delay:0
         usingSpringWithDamping:0.72 initialSpringVelocity:0.4
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ ind.frame = target; } completion:nil];
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

    CGFloat bottomInset = 0;
    UIWindow *win = bar.window;
    if (win && CGRectGetMaxY([bar convertRect:bar.bounds toView:win]) >= win.bounds.size.height - 1.0) {
        bottomInset = win.safeAreaInsets.bottom;
    }
    CGFloat pillH = MIN(56.0, bar.bounds.size.height - bottomInset - 8.0);
    if (pillH < 34.0) pillH = MAX(30.0, bar.bounds.size.height - bottomInset - 4.0);
    CGRect pillFrame = CGRectMake(14, (bar.bounds.size.height - bottomInset - pillH) / 2.0,
                                  bar.bounds.size.width - 28, pillH);
    [self pillBackgroundInBar:bar frame:pillFrame belowItems:items];

    UIView *ind = [self indicatorInBar:bar belowItems:items];
    CGRect target = [self indicatorFrameForItemFrame:items[self.customSelectedIndex].frame
                                          barHeight:bar.bounds.size.height
                                        bottomInset:bottomInset];
    if (self.previewIndex < 0) ind.frame = target;
    ind.layer.cornerRadius = target.size.height / 2.0;
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
    CGFloat bottomInset = 0;
    UIWindow *win = self.customBar.window;
    if (win && CGRectGetMaxY([self.customBar convertRect:self.customBar.bounds toView:win]) >= win.bounds.size.height - 1.0) {
        bottomInset = win.safeAreaInsets.bottom;
    }
    UIView *ind = [self indicatorInBar:self.customBar belowItems:self.customItems];
    CGRect target = [self indicatorFrameForItemFrame:self.customItems[self.customSelectedIndex].frame
                                          barHeight:self.customBar.bounds.size.height
                                        bottomInset:bottomInset];
    [UIView animateWithDuration:0.45 delay:0
         usingSpringWithDamping:0.72 initialSpringVelocity:0.4
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ ind.frame = target; } completion:nil];
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

- (void)handlePan:(UIPanGestureRecognizer *)pan {
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
    CGFloat bottomInset = 0;
    UIWindow *win = bar.window;
    if (win && CGRectGetMaxY([bar convertRect:bar.bounds toView:win]) >= win.bounds.size.height - 1.0) {
        bottomInset = win.safeAreaInsets.bottom;
    }

    switch (pan.state) {
        case UIGestureRecognizerStateBegan: {
            self.previewIndex = nearIdx;
            [UIView animateWithDuration:0.18 animations:^{
                ind.transform = CGAffineTransformMakeScale(1.07, 1.07);
            }];
            [self hapticTick];
            break;
        }
        case UIGestureRecognizerStateChanged: {
            CGRect f = ind.frame;
            f.origin.x = clampedX - f.size.width / 2.0;
            ind.frame = f;
            if (nearIdx != self.previewIndex) {
                self.previewIndex = nearIdx;
                [self hapticTick];
                if (!isTab) [self applyCustomSelectionVisual];
            }
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            NSInteger target = nearIdx;
            self.previewIndex = -1;
            ind.transform = CGAffineTransformIdentity;
            [self finishDragToIndex:target bar:bar isTabBar:isTab];
            break;
        }
        default:
            break;
    }
    (void)bottomInset;
}

- (void)finishDragToIndex:(NSInteger)idx bar:(UIView *)bar isTabBar:(BOOL)isTab {
    NSArray<UIView *> *items = isTab ? [self tabBarButtons:(UITabBar *)bar] : self.customItems;
    if (!items || idx < 0 || idx >= (NSInteger)items.count) return;
    CGFloat bottomInset = 0;
    UIWindow *win = bar.window;
    if (win && CGRectGetMaxY([bar convertRect:bar.bounds toView:win]) >= win.bounds.size.height - 1.0) {
        bottomInset = win.safeAreaInsets.bottom;
    }
    UIView *ind = [self indicatorInBar:bar belowItems:items];
    CGRect target = [self indicatorFrameForItemFrame:items[idx].frame
                                          barHeight:bar.bounds.size.height
                                        bottomInset:bottomInset];
    [UIView animateWithDuration:0.5 delay:0
         usingSpringWithDamping:0.68 initialSpringVelocity:0.5
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ ind.frame = target; }
                     completion:^(__unused BOOL finished) {
        if (isTab) [self selectTabBarIndex:idx bar:(UITabBar *)bar];
        else [self selectCustomIndex:idx];
    }];
}

// ---------------------------------------------------------- quét bar tự chế
- (void)appDidBecomeActive:(NSNotification *)note {
    (void)note;
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
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            LGBPrefsChanged, (__bridge CFStringRef)LGB_PREFS_NOTIFICATION, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
