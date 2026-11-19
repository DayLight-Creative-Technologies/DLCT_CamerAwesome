//
//  ZoomUtils.h
//  camerawesome
//
//  DLCT: one owner for the zoom scale the plugin reports to Dart.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Zoom on iOS has two scales. `AVCaptureDevice.videoZoomFactor` is the DEVICE scale: on a virtual
/// device whose widest constituent is the ultra-wide lens (triple / dual-wide camera), factor 1.0 is
/// the ultra-wide field of view. The DISPLAYED scale is what the system Camera app labels "1x" (the
/// wide-angle lens): displayed = device factor x multiplier (0.5 on those devices, 1.0 elsewhere).
/// The plugin reports min/max/optical-max zoom to Dart in the displayed scale and drives the device in
/// the device scale; the normalized 0.0-1.0 zoom maps linearly over both, so the two agree.
@interface ZoomUtils : NSObject

/// Pure core of `displayMultiplierForDevice:` before iOS 18, separated so it is testable without a
/// camera. `switchOverFactors` is `virtualDeviceSwitchOverVideoZoomFactors`; the first entry is where
/// the wide-angle lens takes over from the ultra-wide.
+ (CGFloat)displayMultiplierWithSwitchOverFactors:(nullable NSArray<NSNumber *> *)switchOverFactors
                               hasUltraWideConstituent:(BOOL)hasUltraWideConstituent;

/// Displayed zoom = device zoom factor x this. iOS 18+: Apple's `displayVideoZoomFactorMultiplier`.
+ (CGFloat)displayMultiplierForDevice:(nullable AVCaptureDevice *)device;

/// Device-scale range the plugin drives (`videoZoomFactor` units).
+ (CGFloat)deviceMinZoomFactor:(nullable AVCaptureDevice *)device;
+ (CGFloat)deviceMaxZoomFactor:(nullable AVCaptureDevice *)device;
/// Last lens switch-over (device scale); 1.0 on a single-lens device.
+ (CGFloat)deviceOpticalMaxZoomFactor:(nullable AVCaptureDevice *)device;

/// Normalized 0.0-1.0 zoom -> device `videoZoomFactor`, clamped to the device range.
+ (CGFloat)deviceZoomFactorForNormalized:(double)normalized device:(nullable AVCaptureDevice *)device;

@end

NS_ASSUME_NONNULL_END
