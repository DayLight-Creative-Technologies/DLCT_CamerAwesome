//
//  MotionController.m
//  camerawesome
//
//  Created by Dimitri Dessus on 17/12/2020.
//

#import "MotionController.h"

@implementation MotionController

- (instancetype)init {
  self = [super init];
  _motionManager = [[CMMotionManager alloc] init];
  _motionManager.deviceMotionUpdateInterval = 0.2f;
  return self;
}

- (void)setOrientationEventSink:(FlutterEventSink)orientationEventSink {
  _orientationEventSink = orientationEventSink;

  // Replay the current orientation to a sink that connects after the initial
  // Unknown->current transition has already fired. That transition emits exactly
  // once and the stream is change-only with no replay, so a late or re-wired
  // subscriber would otherwise never learn the current orientation until the
  // user physically rotates the device. This seeds orientation reliably
  // regardless of when (or in which channel order) the sink attaches.
  if (orientationEventSink != nil && _deviceOrientation != UIDeviceOrientationUnknown) {
    NSString *orientationString = [self orientationStringForDeviceOrientation:_deviceOrientation];
    if (orientationString != nil) {
      orientationEventSink(orientationString);
    }
  }
}

/// Maps a gravity-derived device orientation to the orientation channel's string
/// value. Returns nil for orientations the camera UI does not represent (face
/// up/down) so callers can skip emitting an unmapped value to the Dart side.
- (NSString *)orientationStringForDeviceOrientation:(UIDeviceOrientation)orientation {
  switch (orientation) {
    case UIDeviceOrientationLandscapeLeft:
      return @"LANDSCAPE_LEFT";
    case UIDeviceOrientationLandscapeRight:
      return @"LANDSCAPE_RIGHT";
    case UIDeviceOrientationPortrait:
      return @"PORTRAIT_UP";
    case UIDeviceOrientationPortraitUpsideDown:
      return @"PORTRAIT_DOWN";
    default:
      return nil;
  }
}

/// Start live motion detection
- (void)startMotionDetection {
  [_motionManager startDeviceMotionUpdatesToQueue:[NSOperationQueue mainQueue]
                                      withHandler:^(CMDeviceMotion *data, NSError *error) {
    UIDeviceOrientation newOrientation;
    if(fabs(data.gravity.x) > fabs(data.gravity.y)) {
      // Landscape
      newOrientation = (data.gravity.x >= 0) ? UIDeviceOrientationLandscapeLeft : UIDeviceOrientationLandscapeRight;
    } else {
      // Portrait
      newOrientation = (data.gravity.y >= 0) ? UIDeviceOrientationPortraitUpsideDown : UIDeviceOrientationPortrait;
    }
    if (self->_deviceOrientation != newOrientation) {
      self->_deviceOrientation = newOrientation;

      NSString *orientationString = [self orientationStringForDeviceOrientation:newOrientation];
      if (self->_orientationEventSink != nil && orientationString != nil) {
        self->_orientationEventSink(orientationString);
      }
    }
  }];
}

/// Stop motion update
- (void)stopMotionDetection {
  [_motionManager stopDeviceMotionUpdates];
}

@end
