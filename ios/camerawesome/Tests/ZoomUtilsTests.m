//
//  ZoomUtilsTests.m — DLCT: native test of the zoom display scale (ZoomUtils).
//
//  Runs on the Mac as Mac Catalyst (no Simulator, no device): ios/camerawesome/Tests/run_zoom_utils_tests.sh
//  Pins the device->displayed zoom multiplier: on a triple / dual-wide camera videoZoomFactor 1.0 is the
//  ultra-wide lens, so the displayed ("Camera app") scale is device factor / first switch-over.
//

#import <Foundation/Foundation.h>
#import "ZoomUtils.h"

static int failures = 0;

static void expectNear(CGFloat actual, CGFloat expected, NSString *name) {
  if (fabs(actual - expected) > 1e-9) {
    failures++;
    printf("FAIL %s: expected %.4f, got %.4f\n", name.UTF8String, expected, actual);
  } else {
    printf("ok   %s\n", name.UTF8String);
  }
}

int main(void) {
  @autoreleasepool {
    // iPhone 13 Pro / Pro Max triple camera: ultra-wide 13 mm, wide 26 mm (switch-over 2), tele 77 mm (6).
    CGFloat triple = [ZoomUtils displayMultiplierWithSwitchOverFactors:@[ @2, @6 ] hasUltraWideConstituent:YES];
    expectNear(triple, 0.5, @"triple camera: multiplier 0.5");
    expectNear(2.0 * triple, 1.0, @"triple camera: device 2.0 (wide lens) displays as 1x");
    expectNear(6.0 * triple, 3.0, @"triple camera: tele switch-over displays as 3x");
    expectNear(1.0 * triple, 0.5, @"triple camera: device min 1.0 (ultra-wide) displays as 0.5x");

    // iPhone 15 Pro Max style switch-overs (wide at 2, 5x tele at 10).
    CGFloat triple15 = [ZoomUtils displayMultiplierWithSwitchOverFactors:@[ @2, @10 ] hasUltraWideConstituent:YES];
    expectNear(10.0 * triple15, 5.0, @"15 Pro Max: tele switch-over displays as 5x");

    // Dual-wide camera (ultra-wide + wide).
    expectNear([ZoomUtils displayMultiplierWithSwitchOverFactors:@[ @2 ] hasUltraWideConstituent:YES], 0.5,
               @"dual-wide camera: multiplier 0.5");

    // Dual camera (wide + tele): device 1.0 is already the wide lens.
    expectNear([ZoomUtils displayMultiplierWithSwitchOverFactors:@[ @2 ] hasUltraWideConstituent:NO], 1.0,
               @"dual (wide+tele) camera: multiplier 1.0");

    // Single lens: no switch-overs.
    expectNear([ZoomUtils displayMultiplierWithSwitchOverFactors:@[] hasUltraWideConstituent:NO], 1.0,
               @"single lens: multiplier 1.0");
    expectNear([ZoomUtils displayMultiplierWithSwitchOverFactors:nil hasUltraWideConstituent:YES], 1.0,
               @"no switch-over list: multiplier 1.0");

    // A nil device (camera not created) reports the neutral scale rather than 0.
    expectNear([ZoomUtils displayMultiplierForDevice:nil], 1.0, @"nil device: multiplier 1.0");
    expectNear([ZoomUtils deviceZoomFactorForNormalized:0.5 device:nil], 1.0, @"nil device: zoom factor 1.0");
  }
  printf(failures == 0 ? "ALL PASSED\n" : "%d FAILED\n", failures);
  return failures == 0 ? 0 : 1;
}
