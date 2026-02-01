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
  NSLog(@"📸 PhysicalButtonController: Initializing JPSVolumeButtonHandler");
  self.volumeButtonHandler = [JPSVolumeButtonHandler volumeButtonHandlerWithUpBlock:^{
    NSLog(@"📸 PhysicalButtonController: Volume UP detected");
    [self tryToSendPhysicalEvent:volume_up];
  } downBlock:^{
    NSLog(@"📸 PhysicalButtonController: Volume DOWN detected");
    [self tryToSendPhysicalEvent:volume_down];
  }];
  NSLog(@"📸 PhysicalButtonController: Initialized successfully");
  return self;
}

- (void)tryToSendPhysicalEvent:(PhysicalButton)physicalButton {
  NSLog(@"📸 PhysicalButtonController: tryToSendPhysicalEvent called");
  if (debounceTimer != nil) {
    NSLog(@"📸 PhysicalButtonController: Canceling previous debounce timer");
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

      NSLog(@"📸 PhysicalButtonController: Sending event to Flutter: %@", physicalButtonString);
      self->_physicalButtonEventSink(physicalButtonString);
    } else {
      NSLog(@"❌ PhysicalButtonController: Event sink is nil - cannot send event!");
    }
  }];
}

- (void)startListening {
  NSLog(@"📸 PhysicalButtonController: Starting to listen for volume buttons");
  [self.volumeButtonHandler startHandler:YES];
  NSLog(@"📸 PhysicalButtonController: Now listening for volume button events");
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
