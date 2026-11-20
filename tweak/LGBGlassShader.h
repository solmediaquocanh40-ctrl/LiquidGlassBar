// LGBGlassShader.h — lớp vệt sáng kính bằng Metal cho LiquidGlassBar 1.4.0.
//
// Phần toán học của shader (hàm spherical, interval và đặc biệt là
// ls_highlight — highlight theo SDF của UberShader QuartzCore) được
// phỏng theo file GlassBackground17.metal trong gói LiquidGlaze
// (com.zege.liquidglaze) của tác giả zege; file gốc của họ ghi rõ shader
// đó được thu nạp từ Liquidify và tái dựng từ filter kính gốc
// glass_background_lpf của iOS 26 (bản 23C54). Ở đây chỉ lấy PHẦN TOÁN:
// SDF của viên thuốc được tính giải tích ngay trong shader (không cần
// texture SDF như bản gốc), và shader chỉ vẽ LỚP SÁNG (vệt specular ở
// viền + quầng sáng mặt trên) trong suốt đè lên lớp blur sống — vì trong
// tiến trình của một app bên thứ ba không lấy được texture hậu cảnh của
// render server để làm khúc xạ thật như đường ống cấp hệ thống của họ.
//
// Cách dùng: biên dịch shader MỘT LẦN lúc nạp tweak (LGBGlassShaderWarmUp
// chạy ở luồng nền), sau đó mỗi kích thước cục glass chỉ render 1 ảnh
// tĩnh (LGBSpecularImage) rồi để UIImageView mang theo — cục glass di
// chuyển bằng transform nên ảnh tĩnh này không tốn thêm gì khi kéo.
// Mọi lỗi Metal đều trả nil để nơi gọi tự lùi về kính bản 1.3.0.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <simd/simd.h>

static NSString *const kLGBGlassShaderSource =
@"#include <metal_stdlib>\n"
@"using namespace metal;\n"
@"\n"
@"struct LGBUniforms {\n"
@"    float2 size;      // kich thuoc vien thuoc (diem)\n"
@"    float intensity;  // cuong do vet sang 0..1\n"
@"    float pad;\n"
@"};\n"
@"\n"
@"struct LGBVertexOut {\n"
@"    float4 position [[position]];\n"
@"    float2 uv;\n"
@"};\n"
@"\n"
@"vertex LGBVertexOut lgb_vertex(uint vid [[vertex_id]]) {\n"
@"    float2 pos[4] = { float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0), float2(1.0, 1.0) };\n"
@"    float2 uvs[4] = { float2(0.0, 0.0), float2(1.0, 0.0), float2(0.0, 1.0), float2(1.0, 1.0) };\n"
@"    LGBVertexOut out;\n"
@"    out.position = float4(pos[vid], 0.0, 1.0);\n"
@"    out.uv = uvs[vid];\n"
@"    return out;\n"
@"}\n"
@"\n"
@"// --- cac ham lay tu GlassBackground17.metal (doi ten tien to lgb_) ---\n"
@"float lgb_spherical(float d, float invHeight) {\n"
@"    float t = saturate(-d * invHeight);\n"
@"    return 1.0 - saturate(sqrt(t * (2.0 - t)));\n"
@"}\n"
@"float lgb_interval(float d, float a, float b) {\n"
@"    return a == b ? float(d >= b) : saturate((d - a) / (b - a));\n"
@"}\n"
@"// QuartzCore UberShader sdf_key_fill_highlight (ban goc: ls_highlight).\n"
@"// distance = do sau vao trong hinh (duong khi o trong), normal huong ra ngoai.\n"
@"float lgb_highlight(float distance, float2 normal, float width, float height, float angle, float spread) {\n"
@"    float u = saturate(distance / height);\n"
@"    float fade = mix((u < 1.0) ? 1.0 : 0.0, 1.0 - u, 0.7);\n"
@"    float coverage = saturate(0.5 + distance / width) * saturate(0.5 + (height - distance) / width);\n"
@"    float light = saturate((dot(normal, float2(sin(angle), -cos(angle))) - cos(spread)) / max(1.0 - cos(spread), 0.0001));\n"
@"    return distance < -5.0 ? 0.0 : fade * coverage * light;\n"
@"}\n"
@"// ----------------------------------------------------------------------\n"
@"\n"
@"fragment float4 lgb_specular(LGBVertexOut in [[stage_in]],\n"
@"                             constant LGBUniforms &u [[buffer(0)]]) {\n"
@"    float2 size = u.size;\n"
@"    if (size.x < 4.0 || size.y < 4.0) return float4(0.0);\n"
@"    // p: toa do diem anh, goc tren-trai, y huong xuong (khop anh UIImage)\n"
@"    float2 p = in.uv * size;\n"
@"    float radius = size.y * 0.5;\n"
@"    float2 c = size * 0.5;\n"
@"    float2 pc = p - c;\n"
@"    float2 b = c - float2(radius);\n"
@"    float2 q = abs(pc) - b;\n"
@"    float2 m = max(q, float2(0.0));\n"
@"    float d = length(m) + min(max(q.x, q.y), 0.0) - radius; // <0 o trong\n"
@"    float depth = -d;\n"
@"    float2 sgn = float2(pc.x >= 0.0 ? 1.0 : -1.0, pc.y >= 0.0 ? 1.0 : -1.0);\n"
@"    float2 nrm = length(m) > 0.0001 ? normalize(sgn * m)\n"
@"                                    : (q.x > q.y ? float2(sgn.x, 0.0) : float2(0.0, sgn.y));\n"
@"    float aa = max(fwidth(d), 0.6);\n"
@"    float coverage = saturate(0.5 - d / max(fwidth(d), 0.0001));\n"
@"    if (coverage <= 0.001) return float4(0.0);\n"
@"    // Vet sang vien: anh sang chinh tu tren, anh sang phu tu duoi (yeu hon)\n"
@"    float rim = lgb_highlight(depth, nrm, aa, size.y, 0.0, 1.05)\n"
@"              + 0.5 * lgb_highlight(depth, nrm, aa, size.y, M_PI_F, 1.05);\n"
@"    // Quang sang mem o mat tren kinh (falloff cau theo cong thuc goc)\n"
@"    float sph = lgb_spherical(d, 1.0 / size.y);\n"
@"    float topness = saturate(1.0 - (p.y / size.y) * 1.35);\n"
@"    float sheen = pow(sph, 2.0) * 0.15 * topness;\n"
@"    // Duong sang sac ngay sat vien\n"
@"    float edgeLine = exp(-abs(d) / 1.1) * 0.5;\n"
@"    float spec = saturate(rim) * 0.9;\n"
@"    float alpha = saturate(spec + sheen + edgeLine * 0.8) * u.intensity * coverage;\n"
@"    float3 rgb = float3(1.0);\n"
@"    return float4(rgb * alpha, alpha);\n"
@"}\n";

static id<MTLDevice> LGBMetalDevice(void) {
    static id<MTLDevice> device = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        device = MTLCreateSystemDefaultDevice();
    });
    return device;
}

static id<MTLCommandQueue> LGBMetalQueue(void) {
    static id<MTLCommandQueue> queue = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        id<MTLDevice> dev = LGBMetalDevice();
        if (dev) queue = [dev newCommandQueue];
    });
    return queue;
}

// Biên dịch pipeline 1 lần duy nhất; lỗi thì ghi nhận luôn là không dùng
// được (không thử lại liên tục gây tốn pin).
static id<MTLRenderPipelineState> LGBSpecularPipeline(void) {
    static id<MTLRenderPipelineState> pipeline = nil;
    static BOOL tried = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        tried = YES;
        id<MTLDevice> dev = LGBMetalDevice();
        if (!dev) return;
        NSError *err = nil;
        id<MTLLibrary> lib = [dev newLibraryWithSource:kLGBGlassShaderSource options:nil error:&err];
        if (!lib) return;
        id<MTLFunction> vfn = [lib newFunctionWithName:@"lgb_vertex"];
        id<MTLFunction> ffn = [lib newFunctionWithName:@"lgb_specular"];
        if (!vfn || !ffn) return;
        MTLRenderPipelineDescriptor *pd = [[MTLRenderPipelineDescriptor alloc] init];
        pd.vertexFunction = vfn;
        pd.fragmentFunction = ffn;
        pd.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
        pipeline = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
    });
    (void)tried;
    return pipeline;
}

static inline BOOL LGBGlassShaderAvailable(void) {
    return LGBSpecularPipeline() != nil && LGBMetalQueue() != nil;
}

static NSMutableDictionary<NSString *, UIImage *> *LGBSpecularCache(void) {
    static NSMutableDictionary<NSString *, UIImage *> *cache = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });
    return cache;
}

// Render lớp vệt sáng cho 1 kích thước viên thuốc. Trả nil nếu Metal
// không sẵn sàng — nơi gọi tự lùi về asset kính tĩnh của bản 1.3.0.
static inline UIImage *LGBSpecularImage(CGSize sizePt, CGFloat scale, CGFloat intensity) {
    if (sizePt.width < 10 || sizePt.height < 10 || scale < 1) return nil;
    if (!LGBGlassShaderAvailable()) return nil;
    NSInteger bucket = (NSInteger)lround(intensity * 20.0);
    NSString *key = [NSString stringWithFormat:@"%.0fx%.0f@%.1f#%ld",
                     sizePt.width, sizePt.height, scale, (long)bucket];
    NSMutableDictionary<NSString *, UIImage *> *cache = LGBSpecularCache();
    @synchronized (cache) {
        UIImage *hit = cache[key];
        if (hit) return hit;
    }
    id<MTLDevice> dev = LGBMetalDevice();
    id<MTLCommandQueue> queue = LGBMetalQueue();
    id<MTLRenderPipelineState> pipeline = LGBSpecularPipeline();
    if (!dev || !queue || !pipeline) return nil;

    NSUInteger w = (NSUInteger)lround(sizePt.width * scale);
    NSUInteger h = (NSUInteger)lround(sizePt.height * scale);
    if (w == 0 || h == 0 || w > 4096 || h > 4096) return nil;
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                  width:w height:h mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    td.storageMode = MTLStorageModeShared;
    id<MTLTexture> tex = [dev newTextureWithDescriptor:td];
    if (!tex) return nil;

    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = tex;
    rp.colorAttachments[0].loadAction = MTLLoadActionClear;
    rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
    rp.colorAttachments[0].storeAction = MTLStoreActionStore;

    id<MTLCommandBuffer> cmd = [queue commandBuffer];
    id<MTLRenderCommandEncoder> enc = [cmd renderCommandEncoderWithDescriptor:rp];
    if (!enc) return nil;
    [enc setRenderPipelineState:pipeline];
    struct { simd_float2 size; float intensity; float pad; } uni;
    uni.size = simd_make_float2((float)sizePt.width, (float)sizePt.height);
    uni.intensity = (float)intensity;
    uni.pad = 0;
    [enc setFragmentBytes:&uni length:sizeof(uni) atIndex:0];
    [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    [enc endEncoding];
    [cmd commit];
    [cmd waitUntilCompleted];
    if (cmd.status != MTLCommandBufferStatusCompleted) return nil;

    NSUInteger bpr = w * 4;
    NSMutableData *data = [NSMutableData dataWithLength:bpr * h];
    [tex getBytes:data.mutableBytes bytesPerRow:bpr fromRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGImageRef cg = CGImageCreate(w, h, 8, 32, bpr, cs,
                                  kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big,
                                  provider, NULL, NO, kCGRenderingIntentDefault);
    CGColorSpaceRelease(cs);
    CGDataProviderRelease(provider);
    if (!cg) return nil;
    UIImage *img = [UIImage imageWithCGImage:cg scale:scale orientation:UIImageOrientationUp];
    CGImageRelease(cg);
    if (img) {
        @synchronized (cache) {
            if (cache.count > 12) [cache removeAllObjects];
            cache[key] = img;
        }
    }
    return img;
}

// Biên dịch sẵn + render thử 1 ảnh nhỏ để lần render thật đầu tiên
// không bị khựng. Gọi từ luồng nền lúc nạp tweak. Trả YES nếu sẵn sàng.
static inline BOOL LGBGlassShaderWarmUp(void) {
    if (!LGBGlassShaderAvailable()) return NO;
    return LGBSpecularImage(CGSizeMake(132, 56), 2.0, 1.0) != nil;
}
