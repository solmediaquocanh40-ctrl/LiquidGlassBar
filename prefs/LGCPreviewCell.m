#import "LGCPreviewCell.h"
#import <QuartzCore/QuartzCore.h>
#import "LGBGlassShader.h"

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

// Bản sao hàm vẽ asset kính của Tweak.x (cùng thông số đã chỉnh trong
// suốt ở 1.3.0) để preview trông y hệt kính thật trong Messenger.
static UIImage *LGCGlassImageForSize(CGSize size) {
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

        [path addClip];
        CGFloat loc1[] = {0.0, 0.45, 1.0};
        CGFloat comp1[] = {1,1,1,0.20,  1,1,1,0.10,  1,1,1,0.04};
        CGGradientRef g1 = CGGradientCreateWithColorComponents(cs, comp1, loc1, 3);
        CGContextDrawLinearGradient(c, g1, CGPointMake(0, 0), CGPointMake(0, size.height), 0);
        CGGradientRelease(g1);

        CGFloat loc2[] = {0.0, 1.0};
        CGFloat comp2[] = {1,1,1,0.22,  1,1,1,0.0};
        CGGradientRef g2 = CGGradientCreateWithColorComponents(cs, comp2, loc2, 2);
        CGPoint glowCenter = CGPointMake(size.width * 0.30, size.height * 0.16);
        CGContextDrawRadialGradient(c, g2, glowCenter, 0, glowCenter, size.width * 0.55, 0);
        CGGradientRelease(g2);

        CGContextSaveGState(c);
        CGContextClipToRect(c, CGRectMake(0, 0, size.width, size.height * 0.52));
        CGFloat loc3[] = {0.0, 1.0};
        CGFloat comp3[] = {1,1,1,0.30,  1,1,1,0.0};
        CGGradientRef g3 = CGGradientCreateWithColorComponents(cs, comp3, loc3, 2);
        CGContextDrawLinearGradient(c, g3, CGPointMake(0, 0), CGPointMake(0, size.height * 0.52), 0);
        CGGradientRelease(g3);
        CGContextRestoreGState(c);

        CGFloat loc4[] = {0.0, 1.0};
        CGFloat comp4[] = {0,0,0,0.0,  0,0,0,0.16};
        CGGradientRef g4 = CGGradientCreateWithColorComponents(cs, comp4, loc4, 2);
        CGContextDrawLinearGradient(c, g4, CGPointMake(0, size.height * 0.70), CGPointMake(0, size.height), 0);
        CGGradientRelease(g4);

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

@interface LGCPreviewCell ()
@property (nonatomic, strong) UIView *stageView;
@property (nonatomic, strong) UIView *circleA;
@property (nonatomic, strong) UIView *circleB;
@property (nonatomic, strong) NSArray<UIView *> *fakeRows;
@property (nonatomic, strong) UIVisualEffectView *pillFx;
@property (nonatomic, strong) UIView *pillTint;
@property (nonatomic, strong) UIImageView *pillAsset;
@property (nonatomic, strong) UIImageView *pillSpec;
@property (nonatomic, strong) UIVisualEffectView *blobFx;
@property (nonatomic, strong) UIView *blobTint;
@property (nonatomic, strong) UIImageView *blobAsset;
@property (nonatomic, strong) UIImageView *blobSpec;
@property (nonatomic, strong) NSArray<UIImageView *> *iconViews;
@property (nonatomic, strong) NSArray<UILabel *> *labelViews;
@property (nonatomic, copy) NSString *lastHash;
@end

static void LGCPreviewPrefsChanged(CFNotificationCenterRef center, void *observer,
                                   CFStringRef name, const void *object,
                                   CFDictionaryRef userInfo) {
    (void)center; (void)name; (void)object; (void)userInfo;
    LGCPreviewCell *cell = (__bridge LGCPreviewCell *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [cell refreshPreview];
    });
}

@implementation LGCPreviewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        [self buildPreview];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge void *)self, LGCPreviewPrefsChanged,
            (__bridge CFStringRef)LGC_PREFS_NOTIFICATION, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    return self;
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge void *)self, (__bridge CFStringRef)LGC_PREFS_NOTIFICATION, NULL);
}

- (void)buildPreview {
    self.stageView = [[UIView alloc] initWithFrame:CGRectZero];
    self.stageView.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1.0];
    self.stageView.layer.cornerRadius = 20;
    self.stageView.layer.masksToBounds = YES;
    [self.contentView addSubview:self.stageView];

    // Hai đốm màu + vài dòng chữ giả phía sau để kính blur xuyên qua cho
    // thấy hiệu ứng trong suốt giống trong Messenger.
    self.circleA = [[UIView alloc] initWithFrame:CGRectZero];
    self.circleA.backgroundColor = [UIColor colorWithRed:1.0 green:0.45 blue:0.15 alpha:0.9];
    [self.stageView addSubview:self.circleA];
    self.circleB = [[UIView alloc] initWithFrame:CGRectZero];
    self.circleB.backgroundColor = [UIColor colorWithRed:0.15 green:0.45 blue:1.0 alpha:0.9];
    [self.stageView addSubview:self.circleB];

    NSMutableArray<UIView *> *rows = [NSMutableArray array];
    for (NSInteger i = 0; i < 3; i++) {
        UIView *row = [[UIView alloc] initWithFrame:CGRectZero];
        row.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
        row.layer.cornerRadius = 4.5;
        [self.stageView addSubview:row];
        [rows addObject:row];
    }
    self.fakeRows = rows;

    self.pillFx = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
    self.pillFx.layer.masksToBounds = YES;
    self.pillFx.layer.borderWidth = 0.8;
    self.pillFx.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
    self.pillTint = [[UIView alloc] initWithFrame:CGRectZero];
    self.pillTint.userInteractionEnabled = NO;
    [self.pillFx.contentView addSubview:self.pillTint];
    [self.stageView addSubview:self.pillFx];
    self.pillAsset = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.pillAsset.userInteractionEnabled = NO;
    [self.stageView addSubview:self.pillAsset];
    self.pillSpec = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.pillSpec.userInteractionEnabled = NO;
    [self.stageView addSubview:self.pillSpec];

    self.blobFx = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
    self.blobFx.layer.masksToBounds = YES;
    self.blobFx.layer.borderWidth = 0.9;
    self.blobFx.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.38].CGColor;
    self.blobTint = [[UIView alloc] initWithFrame:CGRectZero];
    self.blobTint.userInteractionEnabled = NO;
    [self.blobFx.contentView addSubview:self.blobTint];
    [self.stageView addSubview:self.blobFx];
    self.blobAsset = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.blobAsset.userInteractionEnabled = NO;
    [self.stageView addSubview:self.blobAsset];
    self.blobSpec = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.blobSpec.userInteractionEnabled = NO;
    [self.stageView addSubview:self.blobSpec];

    // Biên dịch sẵn shader kính ở luồng nền để khung xem trước hiện
    // lớp vệt sáng ngay, không phải chờ biên dịch ở lần refresh đầu.
    static dispatch_once_t warmOnce;
    dispatch_once(&warmOnce, ^{
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            LGBGlassShaderWarmUp();
        });
    });

    NSArray<NSString *> *symbols = @[@"message.fill", @"person.2.fill", @"bell.fill", @"line.3.horizontal"];
    NSArray<NSString *> *names = @[@"Đoạn chat", @"Mọi người", @"Thông báo", @"Menu"];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:23 weight:UIImageSymbolWeightMedium];
    NSMutableArray<UIImageView *> *icons = [NSMutableArray array];
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    for (NSInteger i = 0; i < 4; i++) {
        UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbols[i] withConfiguration:cfg]];
        iv.contentMode = UIViewContentModeCenter;
        [self.stageView addSubview:iv];
        [icons addObject:iv];
        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectZero];
        lab.text = names[i];
        lab.font = [UIFont systemFontOfSize:9.5];
        lab.textAlignment = NSTextAlignmentCenter;
        [self.stageView addSubview:lab];
        [labels addObject:lab];
    }
    self.iconViews = icons;
    self.labelViews = labels;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.contentView.bounds.size.width;
    CGFloat H = self.contentView.bounds.size.height;
    self.stageView.frame = CGRectMake(14, 8, W - 28, H - 16);
    [self refreshPreview];
}

- (void)refreshPreview {
    if (self.stageView.bounds.size.width < 50) return;
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:LGC_DOMAIN];
    NSString *selHex = [d stringForKey:@"selectedColorHex"] ?: @"#0084FF";
    NSString *tintHex = [d stringForKey:@"glassTintHex"] ?: @"#FFFFFF";
    CGFloat glassAlpha = [d objectForKey:@"glassAlpha"] ? (CGFloat)[d doubleForKey:@"glassAlpha"] : 0.85;
    CGFloat blobAlpha = [d objectForKey:@"blobAlpha"] ? (CGFloat)[d doubleForKey:@"blobAlpha"] : 0.95;
    CGFloat wPct = [d objectForKey:@"blobWidthPct"] ? (CGFloat)[d doubleForKey:@"blobWidthPct"] : 100.0;
    CGFloat hPct = [d objectForKey:@"blobHeightPct"] ? (CGFloat)[d doubleForKey:@"blobHeightPct"] : 100.0;
    CGFloat inset = [d objectForKey:@"pillInset"] ? (CGFloat)[d doubleForKey:@"pillInset"] : 8.0;
    BOOL shaderOn = [d objectForKey:@"shaderGlass"] ? [d boolForKey:@"shaderGlass"] : YES;

    NSString *hash = [NSString stringWithFormat:@"%@|%@|%.2f|%.2f|%.0f|%.0f|%.0f|%d|%@",
                      selHex, tintHex, glassAlpha, blobAlpha, wPct, hPct, inset, shaderOn,
                      NSStringFromCGSize(self.stageView.bounds.size)];
    if ([hash isEqualToString:self.lastHash]) return;
    self.lastHash = hash;

    UIColor *selColor = LGCColorFromHex(selHex, [UIColor colorWithRed:0.0 green:0.52 blue:1.0 alpha:1.0]);
    UIColor *tintColor = LGCColorFromHex(tintHex, [UIColor whiteColor]);
    CGRect stage = self.stageView.bounds;

    // nền giả phía sau kính
    self.circleA.frame = CGRectMake(stage.size.width * 0.02, stage.size.height - 95, 110, 110);
    self.circleA.layer.cornerRadius = 55;
    self.circleB.frame = CGRectMake(stage.size.width * 0.72, stage.size.height - 130, 90, 90);
    self.circleB.layer.cornerRadius = 45;
    CGFloat rowW[] = {0.55, 0.75, 0.4};
    for (NSInteger i = 0; i < 3; i++) {
        self.fakeRows[i].frame = CGRectMake(16, 12 + i * 17, stage.size.width * rowW[i], 9);
    }

    // viên thuốc nền
    CGFloat pillH = 62;
    CGRect pill = CGRectMake(inset, stage.size.height - pillH - 10,
                             stage.size.width - inset * 2, pillH);
    self.pillFx.frame = pill;
    self.pillFx.layer.cornerRadius = pillH / 2.0;
    self.pillFx.alpha = glassAlpha;
    self.pillTint.frame = self.pillFx.bounds;
    self.pillTint.backgroundColor = [tintColor colorWithAlphaComponent:0.14];
    self.pillAsset.frame = pill;
    self.pillAsset.image = LGCGlassImageForSize(pill.size);
    self.pillSpec.frame = pill;
    self.pillSpec.image = shaderOn ? LGBSpecularImage(pill.size, [UIScreen mainScreen].scale, 0.8) : nil;
    BOOL pillSpecOn = self.pillSpec.image != nil;
    self.pillSpec.hidden = !pillSpecOn;
    self.pillSpec.alpha = glassAlpha;
    self.pillAsset.alpha = 0.55 * glassAlpha * (pillSpecOn ? 0.55 : 1.0);

    // các ô mục + cục glass ôm ô đầu tiên (icon + chữ)
    NSInteger n = 4;
    CGFloat slotW = pill.size.width / n;
    CGFloat contentH = 38; // icon 23 + khoảng 3 + chữ 12
    CGFloat contentY = CGRectGetMidY(pill) - contentH / 2.0;
    for (NSInteger i = 0; i < n; i++) {
        CGFloat cx = CGRectGetMinX(pill) + slotW * (i + 0.5);
        self.iconViews[i].frame = CGRectMake(cx - 14, contentY, 28, 23);
        self.labelViews[i].frame = CGRectMake(CGRectGetMinX(pill) + slotW * i, contentY + 26, slotW, 12);
        UIColor *c = (i == 0) ? selColor : [UIColor colorWithWhite:0.62 alpha:1.0];
        self.iconViews[i].tintColor = c;
        self.labelViews[i].textColor = c;
    }
    CGRect content0 = CGRectMake(CGRectGetMinX(pill) + 4, contentY, slotW - 8, contentH);
    CGFloat bw = MIN(MAX(content0.size.width * wPct / 100.0, 30.0), pill.size.width - 6);
    CGFloat bh = MIN(MAX(content0.size.height * hPct / 100.0, 24.0), pill.size.height - 4);
    CGFloat bcx = MIN(MAX(CGRectGetMidX(content0), CGRectGetMinX(pill) + bw / 2.0 + 3),
                      CGRectGetMaxX(pill) - bw / 2.0 - 3);
    CGFloat bcy = MIN(MAX(CGRectGetMidY(content0), CGRectGetMinY(pill) + bh / 2.0 + 2),
                      CGRectGetMaxY(pill) - bh / 2.0 - 2);
    CGRect blob = CGRectMake(bcx - bw / 2.0, bcy - bh / 2.0, bw, bh);
    self.blobFx.frame = blob;
    self.blobFx.layer.cornerRadius = bh / 2.0;
    self.blobFx.alpha = blobAlpha;
    self.blobTint.frame = self.blobFx.bounds;
    self.blobTint.backgroundColor = [selColor colorWithAlphaComponent:0.18];
    self.blobAsset.frame = blob;
    self.blobAsset.image = LGCGlassImageForSize(blob.size);
    self.blobSpec.frame = blob;
    self.blobSpec.image = shaderOn ? LGBSpecularImage(blob.size, [UIScreen mainScreen].scale, 1.0) : nil;
    BOOL blobSpecOn = self.blobSpec.image != nil;
    self.blobSpec.hidden = !blobSpecOn;
    self.blobSpec.alpha = blobAlpha;
    self.blobAsset.alpha = blobAlpha * (blobSpecOn ? 0.55 : 1.0);
}

@end
