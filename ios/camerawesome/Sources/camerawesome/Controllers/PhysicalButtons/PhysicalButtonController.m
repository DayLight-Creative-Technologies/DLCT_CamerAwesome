//
//  PhysicalButtonsController.m
//  Pods
//
//  Created by Dimitri Dessus on 20/03/2023.
//

#import "PhysicalButtonController.h"

@implementation PhysicalButtonController

- (instancetype)init {
  self = [super init];
  self.volumeButtonHandler = [JPSVolumeButtonHandler volumeButtonHandlerWithUpBlock:^{
    [self tryToSendPhysicalEvent:volume_up];
  } downBlock:^{
    [self tryToSendPhysicalEvent:volume_down];
  }];
  return self;
}

- (void)tryToSendPhysicalEvent:(PhysicalButton)physicalButton {
  // Ignore spurious events fired during arming (JPSVolumeButtonHandler
  // programmatically adjusts the system volume on startHandler:YES,
  // which triggers a KVO notification that looks like a button press).
  if (_isArming) {
    return;
  }

  if (debounceTimer != nil) {
    [debounceTimer invalidate];
    debounceTimer = nil;
  }

  debounceTimer = [NSTimer scheduledTimerWithTimeInterval:0.3
                                                     repeats:NO
                                                       block:^(NSTimer *timer) {
    if (self->_physicalButtonEventSink != nil) {
      NSString *physicalButtonString;
      switch (physicalButton) {
        case volume_up:
          physicalButtonString = @"VOLUME_UP";
          break;
        case volume_down:
          physicalButtonString = @"VOLUME_DOWN";
          break;
        default:
          return;
      }

      self->_physicalButtonEventSink(physicalButtonString);
    } else {
      NSLog(@"PhysicalButtonController: Event sink is nil - cannot send event");
    }
  }];
}

- (void)startListening {
  _isArming = YES;
  [self.volumeButtonHandler startHandler:YES];
  // Allow 1s for the volume-reset KVO notification to settle before
  // accepting real button presses.
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
    self->_isArming = NO;
  });
}

- (void)stopListening {
  if (self.volumeButtonHandler != nil) {
    [self.volumeButtonHandler stopHandler];
  }
}

- (void)setPhysicalButtonEventSink:(FlutterEventSink)physicalButtonEventSink {
  _physicalButtonEventSink = physicalButtonEventSink;
}

@end
