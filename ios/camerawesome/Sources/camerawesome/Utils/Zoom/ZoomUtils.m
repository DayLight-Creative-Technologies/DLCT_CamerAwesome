//
//  ZoomUtils.m
//  camerawesome
//
//  DLCT: one owner for the zoom scale the plugin reports to Dart (see ZoomUtils.h).
//

#import "ZoomUtils.h"

/// The device scale is capped here so the normalized range stays usable (activeFormat can report 100+).
static const CGFloat kMaxDeviceZoomFactor = 50.0;

@implementation ZoomUtils

+ (CGFloat)displayMultiplierWithSwitchOverFactors:(NSArray<NSNumber *> *)switchOverFactors
                               hasUltraWideConstituent:(BOOL)hasUltraWideConstituent {
  if (!hasUltraWideConstituent || switchOverFactors.count == 0) {
    return 1.0;
  }
  double wideTakesOver = switchOverFactors.firstObject.doubleValue;
  return wideTakesOver > 0.0 ? 1.0 / wideTakesOver : 1.0;
}

+ (CGFloat)displayMultiplierForDevice:(AVCaptureDevice *)device {
  if (device == nil) {
    return 1.0;
  }
  if (@available(iOS 18.0, *)) {
    CGFloat multiplier = device.displayVideoZoomFactorMultiplier;
    return multiplier > 0.0 ? multiplier : 1.0;
  }
  BOOL hasUltraWide = NO;
  if (@available(iOS 13.0, *)) {
    for (AVCaptureDevice *constituent in device.constituentDevices) {
      if ([constituent.deviceType isEqualToString:AVCaptureDeviceTypeBuiltInUltraWideCamera]) {
        hasUltraWide = YES;
        break;
      }
    }
    return [self displayMultiplierWithSwitchOverFactors:device.virtualDeviceSwitchOverVideoZoomFactors
                                hasUltraWideConstituent:hasUltraWide];
  }
  return 1.0;
}

+ (CGFloat)deviceMinZoomFactor:(AVCaptureDevice *)device {
  return device != nil ? device.minAvailableVideoZoomFactor : 1.0;
}

+ (CGFloat)deviceMaxZoomFactor:(AVCaptureDevice *)device {
  if (device == nil) {
    return 1.0;
  }
  CGFloat maxZoom = device.activeFormat.videoMaxZoomFactor;
  return maxZoom > kMaxDeviceZoomFactor ? kMaxDeviceZoomFactor : maxZoom;
}

+ (CGFloat)deviceOpticalMaxZoomFactor:(AVCaptureDevice *)device {
  if (@available(iOS 13.0, *)) {
    NSArray<NSNumber *> *switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors;
    if (switchOvers.count > 0) {
      return switchOvers.lastObject.doubleValue;
    }
  }
  return 1.0;
}

+ (CGFloat)deviceZoomFactorForNormalized:(double)normalized device:(AVCaptureDevice *)device {
  CGFloat minZoom = [self deviceMinZoomFactor:device];
  CGFloat maxZoom = [self deviceMaxZoomFactor:device];
  CGFloat scaled = normalized * (maxZoom - minZoom) + minZoom;
  return MAX(minZoom, MIN(maxZoom, scaled));
}

@end
