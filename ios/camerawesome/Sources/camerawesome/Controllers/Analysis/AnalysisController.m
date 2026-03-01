//
//  AnalysisController.m
//  camerawesome
//
//  Created by Dimitri Dessus on 04/04/2023.
//

#import "AnalysisController.h"

@implementation AnalysisController

+ (void)bgra8888toJpegBgra8888image:(nonnull AnalysisImageWrapper *)bgra8888image jpegQuality:(NSInteger)jpegQuality completion:(nonnull void (^)(AnalysisImageWrapper * _Nullable, FlutterError * _Nullable))completion {
  NSData *bgra8888Data = bgra8888image.bytes.data;
  NSMutableData *mutableData = [bgra8888Data mutableCopy];
  uint8_t *pixels = (uint8_t *)mutableData.mutableBytes;
  
// Swap red and blue channels
for (NSUInteger i = 0; i < mutableData.length; i += 4) {
  uint8_t temp = pixels[i]; // Blue
  pixels[i] = pixels[i + 2]; // Red
  pixels[i + 2] = temp; // Blue
}

  CFDataRef cfData = (__bridge CFDataRef)mutableData;
  CGDataProviderRef dataProvider = CGDataProviderCreateWithCFData(cfData);
  
  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  CGImageRef cgImage = CGImageCreate((size_t)bgra8888image.width,
                                     (size_t)bgra8888image.height,
                                     8,
                                     32,
                                     (size_t)bgra8888image.planes.firstObject.bytesPerRow,
                                     colorSpace,
                                     kCGBitmapByteOrder32Big |
                                     kCGImageAlphaPremultipliedLast,
                                     dataProvider,
                                     NULL,
                                     true,
                                     kCGRenderingIntentDefault);
  
  UIImage *image = [UIImage imageWithCGImage:cgImage];
  NSData *jpegData = UIImageJPEGRepresentation(image, (CGFloat)jpegQuality / 100.0);
  
  FlutterStandardTypedData *dataFlutter = [FlutterStandardTypedData typedDataWithBytes:jpegData];
  
  AnalysisImageWrapper *jpegImage = [AnalysisImageWrapper makeWithFormat:AnalysisImageFormatJpeg
                                                                   bytes:dataFlutter
                                                                   width:bgra8888image.width
                                                                  height:bgra8888image.height
                                                                  planes:bgra8888image.planes
                                                                cropRect:bgra8888image.cropRect
                                                                rotation:bgra8888image.rotation];
  
  completion(jpegImage, nil);
  
  CGColorSpaceRelease(colorSpace);
  CGImageRelease(cgImage);
  CGDataProviderRelease(dataProvider);
}
+ (void)nv21toJpegNv21Image:(nonnull AnalysisImageWrapper *)nv21Image jpegQuality:(NSInteger)jpegQuality completion:(nonnull void (^)(AnalysisImageWrapper * _Nullable, FlutterError * _Nullable))completion {
  completion(nil, [FlutterError errorWithCode:@"NOT_SUPPORTED" message:@"this format is currently not supported on iOS" details:nil]);
}

+ (void)yuv420toJpegYuvImage:(nonnull AnalysisImageWrapper *)yuvImage jpegQuality:(NSInteger)jpegQuality completion:(nonnull void (^)(AnalysisImageWrapper * _Nullable, FlutterError * _Nullable))completion {
  completion(nil, [FlutterError errorWithCode:@"NOT_SUPPORTED" message:@"this format is currently not supported on iOS" details:nil]);
}

+ (void)yuv420toNv21YuvImage:(nonnull AnalysisImageWrapper *)yuvImage completion:(nonnull void (^)(AnalysisImageWrapper * _Nullable, FlutterError * _Nullable))completion {
  completion(nil, [FlutterError errorWithCode:@"NOT_SUPPORTED" message:@"this format is currently not supported on iOS" details:nil]);
}

@end
