#import "CRPTZXBridge.h"

#include <algorithm>
#include <string>

#include "ZXing/BarcodeFormat.h"
#include "ZXing/DecodeHints.h"
#include "ZXing/ImageView.h"
#include "ZXing/ReadBarcode.h"

@implementation CRPTZXBridge

+ (nullable NSString *)decodeInPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                        x1:(float)x1
                                        y1:(float)y1
                                        x2:(float)x2
                                        y2:(float)y2
                                       cls:(NSInteger)cls
{
    if (pixelBuffer == nil) {
        return nil;
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    @try {
        const int pbW = (int)CVPixelBufferGetWidth(pixelBuffer);
        const int pbH = (int)CVPixelBufferGetHeight(pixelBuffer);
        const int stride = (int)CVPixelBufferGetBytesPerRow(pixelBuffer);
        auto *base = static_cast<uint8_t *>(CVPixelBufferGetBaseAddress(pixelBuffer));
        if (base == nullptr || pbW <= 1 || pbH <= 1) {
            return nil;
        }

        // Same geometry as the Swift preprocessing path: center square in 640x480.
        const int side = std::min(pbW, pbH);
        const int xOff = (pbW - side) / 2;
        const int yOff = (pbH - side) / 2;

        int cx1 = xOff + (int)lroundf(x1 * (float)side);
        int cy1 = yOff + (int)lroundf(y1 * (float)side);
        int cx2 = xOff + (int)lroundf(x2 * (float)side);
        int cy2 = yOff + (int)lroundf(y2 * (float)side);

        cx1 = std::max(0, std::min(cx1, pbW - 1));
        cy1 = std::max(0, std::min(cy1, pbH - 1));
        cx2 = std::max(cx1 + 1, std::min(cx2, pbW));
        cy2 = std::max(cy1 + 1, std::min(cy2, pbH));

        const int cropW = cx2 - cx1;
        const int cropH = cy2 - cy1;
        if (cropW <= 1 || cropH <= 1) {
            return nil;
        }

        using namespace ZXing;

        auto hints = DecodeHints();
        hints.setTryHarder(true);
        hints.setTryRotate(true);
        hints.setTryInvert(true);
        hints.setTryDownscale(true);
        hints.setMaxNumberOfSymbols(1);

        switch ((int)cls) {
            case 0:
                hints.setFormats(BarcodeFormat::DataMatrix);
                break;
            case 1:
                hints.setFormats(BarcodeFormat::Code128);
                break;
            case 2:
                hints.setFormats(BarcodeFormat::PDF417);
                break;
            default:
                return nil;
        }

        // BGRA pixel buffer -> BGRX image view.
        const uint8_t *cropBase = base + cy1 * stride + cx1 * 4;
        ImageView iv(cropBase, cropW, cropH, ImageFormat::BGRX, stride);

        auto results = ReadBarcodes(iv, hints);
        if (results.empty()) {
            return nil;
        }

        const std::string text = results.front().text();
        if (text.empty()) {
            return nil;
        }
        return [[NSString alloc] initWithBytes:text.data()
                                        length:text.size()
                                      encoding:NSUTF8StringEncoding];
    } @catch (__unused NSException *e) {
        return nil;
    } @finally {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    }
}

@end
