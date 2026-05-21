#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

@interface CRPTZXBridge : NSObject

+ (nullable NSString *)decodeInPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                        x1:(float)x1
                                        y1:(float)y1
                                        x2:(float)x2
                                        y2:(float)y2
                                       cls:(NSInteger)cls;

@end

NS_ASSUME_NONNULL_END
