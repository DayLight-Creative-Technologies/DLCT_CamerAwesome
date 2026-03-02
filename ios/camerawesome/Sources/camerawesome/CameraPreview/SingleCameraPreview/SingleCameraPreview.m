//
//  CameraPreview.m
//  camerawesome
//
//  Created by Dimitri Dessus on 23/07/2020.
//

#import "SingleCameraPreview.h"

@implementation SingleCameraPreview {
  dispatch_queue_t _dispatchQueue;
}

- (instancetype)initWithCameraSensor:(PigeonSensorPosition)sensor
                        videoOptions:(nullable CupertinoVideoOptions *)videoOptions
                    recordingQuality:(VideoRecordingQuality)recordingQuality
                        streamImages:(BOOL)streamImages
                   mirrorFrontCamera:(BOOL)mirrorFrontCamera
                enablePhysicalButton:(BOOL)enablePhysicalButton
                     aspectRatioMode:(AspectRatio)aspectRatioMode
                         captureMode:(CaptureModes)captureMode
                          completion:(nonnull void (^)(NSNumber * _Nullable, FlutterError * _Nullable))completion
                       dispatchQueue:(dispatch_queue_t)dispatchQueue {
  self = [super init];
  
  _completion = completion;
  _dispatchQueue = dispatchQueue;
  
  _previewTexture = [[CameraPreviewTexture alloc] init];
  
  _cameraSensorPosition = sensor;
  _aspectRatio = aspectRatioMode;
  _mirrorFrontCamera = mirrorFrontCamera;
  _videoOptions = videoOptions;
  _recordingQuality = recordingQuality;
  
  // Creating capture session
  _captureSession = [[AVCaptureSession alloc] init];

  // CRITICAL FIX: Disable automatic AVAudioSession configuration
  // Fixes iOS bug where subsequent video recordings lose audio (#30689, #131553)
  // CameraAwesome's auto-configuration interferes with proper audio session management
  // By disabling this, we rely on the app's proper AVAudioSession setup in AppDelegate
  _captureSession.automaticallyConfiguresApplicationAudioSession = NO;

  _captureVideoOutput = [AVCaptureVideoDataOutput new];
  _captureVideoOutput.videoSettings = @{(NSString*)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
  [_captureVideoOutput setAlwaysDiscardsLateVideoFrames:YES];
  [_captureVideoOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
  // NOTE: Do NOT add _captureVideoOutput here. initCameraPreview: adds it via
  // system-managed addOutput: (required for virtual multi-lens devices).
  // Adding here with addOutputWithNoConnections: creates a hybrid managed/unmanaged
  // state that breaks audio input/output management.
  
  [self initCameraPreview:sensor];
  
  [_captureConnection setAutomaticallyAdjustsVideoMirroring:NO];
  if (mirrorFrontCamera && [_captureConnection isVideoMirroringSupported]) {
    [_captureConnection setVideoMirrored:mirrorFrontCamera];
  }
  
  _captureMode = captureMode;
  
  // By default enable auto flash mode
  _flashMode = AVCaptureFlashModeOff;
  _torchMode = AVCaptureTorchModeOff;
  
  _previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:_captureSession];
  _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
  
  // Controllers init
  _videoController = [[VideoController alloc] init];
  _imageStreamController = [[ImageStreamController alloc] initWithStreamImages:streamImages];
  _motionController = [[MotionController alloc] init];
  _locationController = [[LocationController alloc] init];
  _physicalButtonController = [[PhysicalButtonController alloc] init];
  
  [_motionController startMotionDetection];
  
  if (enablePhysicalButton) {
    [_physicalButtonController startListening];
  }

  // CRITICAL FIX: Add observers for session errors and interruptions
  // Fixes preview freeze after video recording stops (error -11800/-10868)
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleSessionRuntimeError:)
                                               name:AVCaptureSessionRuntimeErrorNotification
                                             object:_captureSession];

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleSessionDidStopRunning:)
                                               name:AVCaptureSessionDidStopRunningNotification
                                             object:_captureSession];

  [self setBestPreviewQuality];

  return self;
}

- (void)setAspectRatio:(AspectRatio)ratio {
  _aspectRatio = ratio;
}

/// Set image stream Flutter sink
- (void)setImageStreamEvent:(FlutterEventSink)imageStreamEventSink {
  if (_imageStreamController != nil) {
    [_imageStreamController setImageStreamEventSink:imageStreamEventSink];
  }
}

/// Set orientation stream Flutter sink
- (void)setOrientationEventSink:(FlutterEventSink)orientationEventSink {
  if (_motionController != nil) {
    [_motionController setOrientationEventSink:orientationEventSink];
  }
}

/// Set physical button Flutter sink
- (void)setPhysicalButtonEventSink:(FlutterEventSink)physicalButtonEventSink {
  if (_physicalButtonController != nil) {
    [_physicalButtonController setPhysicalButtonEventSink:physicalButtonEventSink];
  }
}

// TODO: move this to a QualityController
/// Assign the default preview qualities
- (void)setBestPreviewQuality {
  NSArray *qualities = [CameraQualities captureFormatsForDevice:_captureDevice];
  PreviewSize *firstPreviewSize = [qualities count] > 0 ? qualities.lastObject : [PreviewSize makeWithWidth:3840.0 height:2160.0];
  
  CGSize firstSize = CGSizeMake(firstPreviewSize.width, firstPreviewSize.height);
  [self setCameraPreset:firstSize];
}

/// Save exif preferences when taking picture
- (void)setExifPreferencesGPSLocation:(bool)gpsLocation completion:(void(^)(NSNumber *_Nullable, FlutterError *_Nullable))completion {
  _saveGPSLocation = gpsLocation;
  
  if (_saveGPSLocation) {
    [_locationController requestWhenInUseAuthorizationOnGranted:^{
      completion(@(YES), nil);
    } declined:^{
      completion(@(NO), nil);
    }];
  } else {
    completion(@(YES), nil);
  }
}

/// Init camera preview with Front or Rear sensor.
/// Virtual multi-lens devices (triple/dual camera) require system-managed connections
/// via addInput/addOutput. Manual addInputWithNoConnections breaks multi-port virtual devices.
- (void)initCameraPreview:(PigeonSensorPosition)sensor {
  [_captureSession setSessionPreset:AVCaptureSessionPresetPhoto];

  NSError *error;
  _captureDevice = [AVCaptureDevice deviceWithUniqueID:[self selectAvailableCamera:sensor]];
  _captureVideoInput = [AVCaptureDeviceInput deviceInputWithDevice:_captureDevice error:&error];

  if (error != nil) {
    _completion(nil, [FlutterError errorWithCode:@"CANNOT_OPEN_CAMERA" message:@"can't attach device to input" details:[error localizedDescription]]);
    return;
  }

  // Use system-managed connections (addInput + addOutput) instead of manual
  // addInputWithNoConnections + addConnection. Virtual multi-lens devices have
  // multiple ports and the system must manage routing between constituent cameras.
  if ([_captureSession canAddInput:_captureVideoInput]) {
    [_captureSession addInput:_captureVideoInput];
  }

  if ([_captureSession canAddOutput:_captureVideoOutput]) {
    [_captureSession addOutput:_captureVideoOutput];
  }

  // Get the system-created connection for video
  _captureConnection = [_captureVideoOutput connectionWithMediaType:AVMediaTypeVideo];

  // Creating photo output
  _capturePhotoOutput = [AVCapturePhotoOutput new];
  [_capturePhotoOutput setHighResolutionCaptureEnabled:YES];
  [_captureSession addOutput:_capturePhotoOutput];

  // Mirror the preview only on portrait mode
  [_captureConnection setAutomaticallyAdjustsVideoMirroring:NO];
  [_captureConnection setVideoMirrored:(_cameraSensorPosition == PigeonSensorPositionFront)];
  [_captureConnection setVideoOrientation:AVCaptureVideoOrientationPortrait];
}

#pragma mark - Session Error Handling

/// Handle AVCaptureSession runtime errors (e.g., error -11800 after stopping video)
/// Automatically restarts the session to prevent frozen preview
- (void)handleSessionRuntimeError:(NSNotification *)notification {
  NSError *error = notification.userInfo[AVCaptureSessionErrorKey];
  NSLog(@"AVCaptureSession runtime error: %@", error);

  // Error -11800 (with underlying -10868) occurs after stopping video recording.
  // The session tries to reconfigure audio inputs/outputs and fails.
  // Restart the session to recover.
  if (error.code == AVErrorUnknown || error.code == -11800) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (![self->_captureSession isRunning]) {
        [self->_captureSession startRunning];
      }
    });
  }
}

/// Handle AVCaptureSession stopped unexpectedly — restart to prevent frozen preview
- (void)handleSessionDidStopRunning:(NSNotification *)notification {
  NSLog(@"AVCaptureSession stopped unexpectedly — restarting");
  dispatch_async(dispatch_get_main_queue(), ^{
    [self->_captureSession startRunning];
  });
}

- (void)dealloc {
  [self.motionController stopMotionDetection];
  [self.physicalButtonController stopListening];

  // Remove session error observers
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:AVCaptureSessionRuntimeErrorNotification
                                                object:_captureSession];
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:AVCaptureSessionDidStopRunningNotification
                                                object:_captureSession];
}

/// Set camera preview size
- (void)setCameraPreset:(CGSize)currentPreviewSize {
  CGSize targetSize = currentPreviewSize;

  // Determine the target size based on the current mode and settings
  if (_captureMode == Video || _videoController.isRecording) {
      // If recording video, prioritize the recording quality setting
      // TODO: Need a way to get the CGSize from the _recordingQuality enum or _videoOptions
      // For now, let's assume a helper function or default high quality if direct mapping isn't obvious.
      // Placeholder: If video options exist, try to use them, otherwise fall back.
      // If no direct mapping, maybe use the highest available preset suitable for video?
      // Or just pass CGSizeZero to let selectVideoCapturePreset pick the best for video?
      // For now, let's pass CGSizeZero to select the best default for video capture.
      if (_videoOptions != nil) {
         // Hypothetical: Get size from VideoOptions quality. Needs actual implementation.
         // targetSize = [CameraQualities sizeFromQuality:_recordingQuality];
         // If no direct mapping, maybe use the highest available preset suitable for video?
         // Or just pass CGSizeZero to let selectVideoCapturePreset pick the best for video?
         // For now, let's pass CGSizeZero to select the best default for video capture.
         targetSize = CGSizeZero; 
      } else if (!CGSizeEqualToSize(currentPreviewSize, CGSizeZero)){
         // Use provided size if valid and no video options
         targetSize = currentPreviewSize;
      } else {
         // Fallback to best quality if no specific size or options given
         targetSize = CGSizeZero;
      }
  } else if (_imageStreamController.streamImages) {
      // If only streaming (not recording), force 720p for potential stability (based on commit history)
      targetSize = CGSizeMake(720, 1280);
  } else if (CGSizeEqualToSize(currentPreviewSize, CGSizeZero)) {
      // If neither recording nor streaming, and no size provided, use best quality
      targetSize = CGSizeZero;
  } 
  // else: Use the non-zero currentPreviewSize passed in.

  NSString *presetSelected;
  if (!CGSizeEqualToSize(CGSizeZero, targetSize)) {
    // Try to get the quality requested based on the determined target size
    presetSelected = [CameraQualities selectVideoCapturePreset:targetSize session:_captureSession device:_captureDevice];
  } else {
    // Compute the best quality supported by the camera device if targetSize is Zero
    presetSelected = [CameraQualities selectVideoCapturePreset:_captureSession device:_captureDevice];
  }

  // Check if the preset needs to be changed
  if (![_captureSession.sessionPreset isEqualToString:presetSelected]) {
      [_captureSession setSessionPreset:presetSelected];
      _currentPreset = presetSelected;
  } else {
      _currentPreset = _captureSession.sessionPreset;
  }

  // Use the corrected method name
  _currentPreviewSize = [CameraQualities getSizeForPreset:_currentPreset];

  [_videoController setPreviewSize:_currentPreviewSize];
}

/// Get current video prewiew size
- (CGSize)getEffectivPreviewSize {
  return _currentPreviewSize;
}

// Get min zoom level (< 1.0 on virtual multi-lens devices for ultra-wide)
- (CGFloat)getMinZoom {
  return _captureDevice.minAvailableVideoZoomFactor;
}

// Get max zoom level (digital + optical combined)
- (CGFloat)getMaxZoom {
  CGFloat maxZoom = _captureDevice.activeFormat.videoMaxZoomFactor;
  return maxZoom > 50.0 ? 50.0 : maxZoom;
}

// Get optical max zoom — the highest zoom factor before digital zoom begins.
// On virtual multi-lens devices, this is the last lens switch-over point.
// On single-lens devices, returns 1.0 (any zoom beyond 1x is digital).
- (CGFloat)getOpticalMaxZoom {
  NSArray<NSNumber *> *switchOvers = _captureDevice.virtualDeviceSwitchOverVideoZoomFactors;
  if (switchOvers != nil && switchOvers.count > 0) {
    return switchOvers.lastObject.doubleValue;
  }
  return 1.0;
}

/// Dispose camera inputs & outputs
- (void)dispose {
  [self stop];
  [self.physicalButtonController stopListening];

  for (AVCaptureInput *input in [_captureSession inputs]) {
    [_captureSession removeInput:input];
  }
  for (AVCaptureOutput *output in [_captureSession outputs]) {
    [_captureSession removeOutput:output];
  }

  // Restore audio session to .playback so volume buttons work for media playback
  [SingleCameraPreview restorePlaybackAudioSession];
}

/// Set preview size resolution
- (void)setPreviewSize:(CGSize)previewSize error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (_videoController.isRecording) {
    *error = [FlutterError errorWithCode:@"PREVIEW_SIZE" message:@"impossible to change preview size, video already recording" details:@""];
    return;
  }
  BOOL sessionIsRunning = _captureSession.isRunning;
  if (sessionIsRunning) {
      [_captureSession stopRunning];
  }
  [self setCameraPreset:previewSize];
  if (sessionIsRunning) {
    dispatch_async(_dispatchQueue, ^{
      [self->_captureSession startRunning];
    });
  }
}

/// Start camera preview
- (void)start {
  // Switch audio session to .playAndRecord for video recording capability
  [SingleCameraPreview activateRecordingAudioSession];
  dispatch_async(_dispatchQueue, ^{
    [self->_captureSession startRunning];
  });
}

/// Stop camera preview
- (void)stop {
  [_captureSession stopRunning];
}

#pragma mark - Audio Session Lifecycle

/// Switch AVAudioSession to .playAndRecord for camera use (recording + playback).
/// Called when the camera session starts. Restores via restorePlaybackAudioSession on dispose.
+ (void)activateRecordingAudioSession {
  AVAudioSession *session = [AVAudioSession sharedInstance];
  NSError *error = nil;

  AVAudioSessionCategoryOptions options = AVAudioSessionCategoryOptionMixWithOthers |
                                           AVAudioSessionCategoryOptionDefaultToSpeaker;

  [session setCategory:AVAudioSessionCategoryPlayAndRecord
                  mode:AVAudioSessionModeVideoRecording
               options:options
                 error:&error];
  if (error) {
    NSLog(@"Failed to set .playAndRecord audio session: %@", error);
    return;
  }

  [session setActive:YES error:&error];
  if (error) {
    NSLog(@"Failed to activate recording audio session: %@", error);
  }
}

/// Restore AVAudioSession to .playback for normal media consumption.
/// This ensures volume buttons control media volume (not ringer) during video playback.
+ (void)restorePlaybackAudioSession {
  AVAudioSession *session = [AVAudioSession sharedInstance];
  NSError *error = nil;

  [session setCategory:AVAudioSessionCategoryPlayback
                  mode:AVAudioSessionModeDefault
               options:AVAudioSessionCategoryOptionMixWithOthers
                 error:&error];
  if (error) {
    NSLog(@"Failed to set .playback audio session: %@", error);
    return;
  }

  [session setActive:YES error:&error];
  if (error) {
    NSLog(@"Failed to activate playback audio session: %@", error);
  }
}

/// Set sensor between Front & Rear camera
- (void)setSensor:(PigeonSensor *)sensor {
  // Check if the session is running before changing the preset
  BOOL sessionIsRunning = _captureSession.isRunning;
  if (sessionIsRunning) {
      [_captureSession stopRunning];
  }
  // First remove all input & output
  [_captureSession beginConfiguration];
  
  // Only remove camera channel but keep audio
  for (AVCaptureInput *input in [_captureSession inputs]) {
    for (AVCaptureInputPort *port in input.ports) {
      if ([[port mediaType] isEqual:AVMediaTypeVideo]) {
        [_captureSession removeInput:input];
        break;
      }
    }
  }
  [_videoController setAudioIsDisconnected:YES];
  
  [_captureSession removeOutput:_capturePhotoOutput];
  [_captureSession removeOutput:_captureVideoOutput];
  
  _cameraSensorPosition = sensor.position;
  _captureDeviceId = sensor.deviceId;
  
  // Init the camera preview with the selected sensor
  [self initCameraPreview:sensor.position];
  
  [self setBestPreviewQuality];
  
  [_captureSession commitConfiguration];
  if (sessionIsRunning) {
    dispatch_async(_dispatchQueue, ^{
      [self->_captureSession startRunning];
    });
  }
}

/// Set zoom level. Maps normalized 0.0-1.0 to the device's full zoom range (minZoom...maxZoom).
- (void)setZoom:(float)value error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  CGFloat minZoom = [self getMinZoom];
  CGFloat maxZoom = [self getMaxZoom];
  CGFloat scaledZoom = value * (maxZoom - minZoom) + minZoom;
  scaledZoom = MAX(minZoom, MIN(maxZoom, scaledZoom));

  NSError *zoomError;
  if ([_captureDevice lockForConfiguration:&zoomError]) {
    _captureDevice.videoZoomFactor = scaledZoom;
    [_captureDevice unlockForConfiguration];
  } else {
    *error = [FlutterError errorWithCode:@"ZOOM_NOT_SET" message:@"can't set the zoom value" details:[zoomError localizedDescription]];
  }
}

- (void)setBrightness:(NSNumber *)brightness error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  NSError *brightnessError = nil;
  if ([_captureDevice lockForConfiguration:&brightnessError]) {
    AVCaptureExposureMode exposureMode = AVCaptureExposureModeContinuousAutoExposure;
    if ([_captureDevice isExposureModeSupported:exposureMode]) {
      [_captureDevice setExposureMode:exposureMode];
    }
    
    CGFloat minExposureTargetBias = _captureDevice.minExposureTargetBias;
    CGFloat maxExposureTargetBias = _captureDevice.maxExposureTargetBias;
    
    CGFloat exposureTargetBias = minExposureTargetBias + (maxExposureTargetBias - minExposureTargetBias) * [brightness floatValue];
    exposureTargetBias = MAX(minExposureTargetBias, MIN(maxExposureTargetBias, exposureTargetBias));
    
    [_captureDevice setExposureTargetBias:exposureTargetBias completionHandler:nil];
    [_captureDevice unlockForConfiguration];
  } else {
    *error = [FlutterError errorWithCode:@"BRIGHTNESS_NOT_SET" message:@"can't set the brightness value" details:[brightnessError localizedDescription]];
  }
}

// === MANUAL EXPOSURE ===

- (ExposureCapabilities *)getExposureCapabilities {
  BOOL isSupported = [_captureDevice isExposureModeSupported:AVCaptureExposureModeCustom];

  double minISO = isSupported ? (double)_captureDevice.activeFormat.minISO : 0;
  double maxISO = isSupported ? (double)_captureDevice.activeFormat.maxISO : 0;

  CMTime minDuration = _captureDevice.activeFormat.minExposureDuration;
  CMTime maxDuration = _captureDevice.activeFormat.maxExposureDuration;
  double minShutter = isSupported ? CMTimeGetSeconds(minDuration) : 0;
  double maxShutter = isSupported ? CMTimeGetSeconds(maxDuration) : 0;

  double currentISO = (double)_captureDevice.ISO;
  double currentShutter = CMTimeGetSeconds(_captureDevice.exposureDuration);

  return [ExposureCapabilities makeWithIsManualExposureSupported:isSupported
                                                         minISO:minISO
                                                         maxISO:maxISO
                                                minShutterSpeed:minShutter
                                                maxShutterSpeed:maxShutter
                                                     currentISO:currentISO
                                            currentShutterSpeed:currentShutter];
}

- (void)setManualISO:(double)iso completion:(void (^)(FlutterError * _Nullable))completion {
  if (![_captureDevice isExposureModeSupported:AVCaptureExposureModeCustom]) {
    completion([FlutterError errorWithCode:@"MANUAL_EXPOSURE_UNSUPPORTED" message:@"manual exposure is not supported on this device" details:nil]);
    return;
  }

  NSError *lockError;
  if ([_captureDevice lockForConfiguration:&lockError]) {
    if (iso < 0) {
      // Return to auto exposure
      [_captureDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
    } else {
      float clampedISO = MAX(_captureDevice.activeFormat.minISO, MIN(_captureDevice.activeFormat.maxISO, (float)iso));
      [_captureDevice setExposureModeCustomWithDuration:AVCaptureExposureDurationCurrent ISO:clampedISO completionHandler:^(CMTime syncTime) {
        completion(nil);
      }];
      [_captureDevice unlockForConfiguration];
      return;
    }
    [_captureDevice unlockForConfiguration];
    completion(nil);
  } else {
    completion([FlutterError errorWithCode:@"EXPOSURE_LOCK_FAILED" message:@"can't lock device for configuration" details:[lockError localizedDescription]]);
  }
}

- (void)setManualShutterSpeed:(double)durationInSeconds completion:(void (^)(FlutterError * _Nullable))completion {
  if (![_captureDevice isExposureModeSupported:AVCaptureExposureModeCustom]) {
    completion([FlutterError errorWithCode:@"MANUAL_EXPOSURE_UNSUPPORTED" message:@"manual exposure is not supported on this device" details:nil]);
    return;
  }

  NSError *lockError;
  if ([_captureDevice lockForConfiguration:&lockError]) {
    if (durationInSeconds < 0) {
      [_captureDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
    } else {
      CMTime minDuration = _captureDevice.activeFormat.minExposureDuration;
      CMTime maxDuration = _captureDevice.activeFormat.maxExposureDuration;
      CMTime targetDuration = CMTimeMakeWithSeconds(durationInSeconds, 1000000000);
      CMTime clampedDuration = CMTimeMaximum(minDuration, CMTimeMinimum(maxDuration, targetDuration));
      [_captureDevice setExposureModeCustomWithDuration:clampedDuration ISO:AVCaptureISOCurrent completionHandler:^(CMTime syncTime) {
        completion(nil);
      }];
      [_captureDevice unlockForConfiguration];
      return;
    }
    [_captureDevice unlockForConfiguration];
    completion(nil);
  } else {
    completion([FlutterError errorWithCode:@"EXPOSURE_LOCK_FAILED" message:@"can't lock device for configuration" details:[lockError localizedDescription]]);
  }
}

- (void)setManualExposure:(double)iso durationInSeconds:(double)durationInSeconds completion:(void (^)(FlutterError * _Nullable))completion {
  if (![_captureDevice isExposureModeSupported:AVCaptureExposureModeCustom]) {
    completion([FlutterError errorWithCode:@"MANUAL_EXPOSURE_UNSUPPORTED" message:@"manual exposure is not supported on this device" details:nil]);
    return;
  }

  NSError *lockError;
  if ([_captureDevice lockForConfiguration:&lockError]) {
    // Resolve ISO
    float resolvedISO;
    if (iso < 0) {
      resolvedISO = AVCaptureISOCurrent;
    } else {
      resolvedISO = MAX(_captureDevice.activeFormat.minISO, MIN(_captureDevice.activeFormat.maxISO, (float)iso));
    }

    // Resolve shutter speed
    CMTime resolvedDuration;
    if (durationInSeconds < 0) {
      resolvedDuration = AVCaptureExposureDurationCurrent;
    } else {
      CMTime minDuration = _captureDevice.activeFormat.minExposureDuration;
      CMTime maxDuration = _captureDevice.activeFormat.maxExposureDuration;
      CMTime targetDuration = CMTimeMakeWithSeconds(durationInSeconds, 1000000000);
      resolvedDuration = CMTimeMaximum(minDuration, CMTimeMinimum(maxDuration, targetDuration));
    }

    [_captureDevice setExposureModeCustomWithDuration:resolvedDuration ISO:resolvedISO completionHandler:^(CMTime syncTime) {
      completion(nil);
    }];
    [_captureDevice unlockForConfiguration];
  } else {
    completion([FlutterError errorWithCode:@"EXPOSURE_LOCK_FAILED" message:@"can't lock device for configuration" details:[lockError localizedDescription]]);
  }
}

- (void)setAutoExposure:(void (^)(FlutterError * _Nullable))completion {
  NSError *lockError;
  if ([_captureDevice lockForConfiguration:&lockError]) {
    if ([_captureDevice isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
      [_captureDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
    }
    [_captureDevice unlockForConfiguration];
    completion(nil);
  } else {
    completion([FlutterError errorWithCode:@"EXPOSURE_LOCK_FAILED" message:@"can't lock device for configuration" details:[lockError localizedDescription]]);
  }
}

// === SMOOTH ZOOM ===

- (void)setSmoothZoom:(float)zoom rate:(float)rate completion:(void (^)(FlutterError * _Nullable))completion {
  CGFloat minZoom = [self getMinZoom];
  CGFloat maxZoom = [self getMaxZoom];
  CGFloat scaledZoom = zoom * (maxZoom - minZoom) + minZoom;
  scaledZoom = MAX(minZoom, MIN(maxZoom, scaledZoom));

  NSError *lockError;
  if ([_captureDevice lockForConfiguration:&lockError]) {
    [_captureDevice rampToVideoZoomFactor:scaledZoom withRate:rate];
    [_captureDevice unlockForConfiguration];
    completion(nil);
  } else {
    completion([FlutterError errorWithCode:@"SMOOTH_ZOOM_NOT_SET" message:@"can't set smooth zoom" details:[lockError localizedDescription]]);
  }
}

- (void)setMirrorFrontCamera:(bool)value error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  _mirrorFrontCamera = value;

  if ([_captureConnection isVideoMirroringSupported]) {
      [_captureConnection setVideoMirrored:value];
  }
}

// === VIDEO CONFIGURATION ===

- (NSArray<VideoConfigurationOption *> *)getSupportedVideoConfigurations {
  NSMutableDictionary<NSString *, NSMutableSet<NSNumber *> *> *resolutionFpsMap = [NSMutableDictionary dictionary];
  NSMutableDictionary<NSString *, NSValue *> *resolvedSizes = [NSMutableDictionary dictionary];

  for (AVCaptureDeviceFormat *format in _captureDevice.formats) {
    CMVideoDimensions dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription);

    // Match by height to handle both 16:9 and other aspect ratios
    // 720p = height 720, 1080p = height 1080, 4K = height 2160
    NSString *matchedLabel = nil;
    if (dims.height == 720 && dims.width >= 1280) {
      matchedLabel = @"720p";
    } else if (dims.height == 1080 && dims.width >= 1920) {
      matchedLabel = @"1080p";
    } else if (dims.height == 2160 && dims.width >= 3840) {
      matchedLabel = @"4K";
    }
    if (matchedLabel == nil) continue;

    // Store the actual dimensions for this resolution tier
    if (resolvedSizes[matchedLabel] == nil) {
      resolvedSizes[matchedLabel] = [NSValue valueWithCGSize:CGSizeMake(dims.width, dims.height)];
    }

    // Collect supported fps values from this format
    for (AVFrameRateRange *range in format.videoSupportedFrameRateRanges) {
      NSMutableSet<NSNumber *> *fpsSet = resolutionFpsMap[matchedLabel];
      if (fpsSet == nil) {
        fpsSet = [NSMutableSet set];
        resolutionFpsMap[matchedLabel] = fpsSet;
      }
      // Add standard fps values that fall within this range
      NSArray<NSNumber *> *standardFps = @[@24, @25, @30, @50, @60];
      for (NSNumber *fps in standardFps) {
        if ([fps doubleValue] >= range.minFrameRate && [fps doubleValue] <= range.maxFrameRate) {
          [fpsSet addObject:fps];
        }
      }
    }
  }

  // Build result sorted by resolution ascending
  NSArray<NSString *> *sortOrder = @[@"720p", @"1080p", @"4K"];
  NSMutableArray<VideoConfigurationOption *> *results = [NSMutableArray array];

  for (NSString *label in sortOrder) {
    NSMutableSet<NSNumber *> *fpsSet = resolutionFpsMap[label];
    if (fpsSet == nil || fpsSet.count == 0) continue;

    CGSize size = [resolvedSizes[label] CGSizeValue];
    NSArray<NSNumber *> *sortedFps = [[fpsSet allObjects] sortedArrayUsingSelector:@selector(compare:)];

    VideoConfigurationOption *option = [VideoConfigurationOption makeWithLabel:label
                                                                        width:(NSInteger)size.width
                                                                       height:(NSInteger)size.height
                                                                 supportedFps:sortedFps];
    [results addObject:option];
  }

  return results;
}

- (void)setVideoConfiguration:(NSInteger)width height:(NSInteger)height fps:(NSInteger)fps error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  // Map dimensions to VideoRecordingQuality
  if (height <= 720) {
    _recordingQuality = VideoRecordingQualityHd;
  } else if (height <= 1080) {
    _recordingQuality = VideoRecordingQualityFhd;
  } else {
    _recordingQuality = VideoRecordingQualityUhd;
  }

  // Update stored video options fps
  if (_videoOptions != nil) {
    _videoOptions = [CupertinoVideoOptions makeWithFileType:_videoOptions.fileType
                                                      codec:_videoOptions.codec
                                                        fps:@(fps)];
  } else {
    _videoOptions = [CupertinoVideoOptions makeWithFileType:nil codec:nil fps:@(fps)];
  }

  // Apply format + fps immediately so the preview reflects the new configuration
  NSError *lockError;
  if ([_captureDevice lockForConfiguration:&lockError]) {
    CMTime frameDuration = CMTimeMake(1, (int32_t)fps);

    // Find a format that supports this resolution and fps (match by height)
    AVCaptureDeviceFormat *bestFormat = nil;
    for (AVCaptureDeviceFormat *format in _captureDevice.formats) {
      CMVideoDimensions dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
      if (dims.height == (int)height && dims.width >= (int)width) {
        for (AVFrameRateRange *range in format.videoSupportedFrameRateRanges) {
          if (fps >= range.minFrameRate && fps <= range.maxFrameRate) {
            bestFormat = format;
            break;
          }
        }
        if (bestFormat != nil) break;
      }
    }

    if (bestFormat != nil) {
      _captureDevice.activeFormat = bestFormat;
    }

    _captureDevice.activeVideoMinFrameDuration = frameDuration;
    _captureDevice.activeVideoMaxFrameDuration = frameDuration;
    [_captureDevice unlockForConfiguration];
  } else {
    *error = [FlutterError errorWithCode:@"VIDEO_CONFIG_ERROR" message:@"can't lock device for configuration" details:[lockError localizedDescription]];
  }
}

/// Set flash mode
- (void)setFlashMode:(CameraFlashMode)flashMode error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (![_captureDevice hasFlash]) {
    *error = [FlutterError errorWithCode:@"FLASH_UNSUPPORTED" message:@"flash is not supported on this device" details:@""];
    return;
  }
  
  if (_cameraSensorPosition == PigeonSensorPositionFront) {
    *error = [FlutterError errorWithCode:@"FLASH_UNSUPPORTED" message:@"can't set flash for portrait mode" details:@""];
    return;
  }
  
  NSError *lockError;
  [_captureDevice lockForConfiguration:&lockError];
  if (lockError != nil) {
    *error = [FlutterError errorWithCode:@"FLASH_ERROR" message:@"impossible to change configuration" details:@""];
    return;
  }
  
  switch (flashMode) {
    case None:
      _torchMode = AVCaptureTorchModeOff;
      _flashMode = AVCaptureFlashModeOff;
      break;
    case On:
      _torchMode = AVCaptureTorchModeOff;
      _flashMode = AVCaptureFlashModeOn;
      break;
    case Auto:
      _torchMode = AVCaptureTorchModeAuto;
      _flashMode = AVCaptureFlashModeAuto;
      break;
    case Always:
      _torchMode = AVCaptureTorchModeOn;
      _flashMode = AVCaptureFlashModeOn;
      break;
    default:
      _torchMode = AVCaptureTorchModeAuto;
      _flashMode = AVCaptureFlashModeAuto;
      break;
  }
  [_captureDevice setTorchMode:_torchMode];
  [_captureDevice unlockForConfiguration];
}

/// Trigger focus on device at the specific point of the preview
- (void)focusOnPoint:(CGPoint)position preview:(CGSize)preview error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  NSError *lockError;
  if ([_captureDevice isFocusModeSupported:AVCaptureFocusModeAutoFocus] && [_captureDevice isFocusPointOfInterestSupported]) {
    if ([_captureDevice lockForConfiguration:&lockError]) {
      if (lockError != nil) {
        *error = [FlutterError errorWithCode:@"FOCUS_ERROR" message:@"impossible to set focus point" details:@""];
        return;
      }
      
      [_captureDevice setFocusPointOfInterest:position];
      [_captureDevice setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
      
      [_captureDevice unlockForConfiguration];
    }
  }
}

- (void)receivedImageFromStream {
  [self.imageStreamController receivedImageFromStream];
}

/// Get the best available camera on device (front or rear).
/// For back camera: prefers virtual triple/dual camera (spans ultra-wide through telephoto)
/// which exposes the full zoom range including sub-1.0 factors for ultra-wide.
- (NSString *)selectAvailableCamera:(PigeonSensorPosition)sensor {
  if (_captureDeviceId != nil) {
    return _captureDeviceId;
  }

  NSInteger cameraPosition = (sensor == PigeonSensorPositionFront) ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;

  // For back camera, try virtual multi-lens devices first (triple > dual wide > wide-angle)
  if (cameraPosition == AVCaptureDevicePositionBack) {
    // Triple camera (ultra-wide + wide + telephoto) — full zoom range
    AVCaptureDevice *tripleCamera = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInTripleCamera
                                                                       mediaType:AVMediaTypeVideo
                                                                        position:AVCaptureDevicePositionBack];
    if (tripleCamera != nil) return [tripleCamera uniqueID];

    // Dual wide camera (ultra-wide + wide) — still gets sub-1.0 zoom
    AVCaptureDevice *dualWideCamera = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInDualWideCamera
                                                                         mediaType:AVMediaTypeVideo
                                                                          position:AVCaptureDevicePositionBack];
    if (dualWideCamera != nil) return [dualWideCamera uniqueID];

    // Dual camera (wide + telephoto)
    AVCaptureDevice *dualCamera = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInDualCamera
                                                                     mediaType:AVMediaTypeVideo
                                                                      position:AVCaptureDevicePositionBack];
    if (dualCamera != nil) return [dualCamera uniqueID];
  }

  // Fallback: single wide-angle camera (all devices)
  AVCaptureDeviceDiscoverySession *discoverySession = [AVCaptureDeviceDiscoverySession
                                                       discoverySessionWithDeviceTypes:@[ AVCaptureDeviceTypeBuiltInWideAngleCamera ]
                                                       mediaType:AVMediaTypeVideo
                                                       position:AVCaptureDevicePositionUnspecified];

  for (AVCaptureDevice *device in discoverySession.devices) {
    if ([device position] == cameraPosition) {
      return [device uniqueID];
    }
  }
  return nil;
}

/// Set capture mode between Photo & Video mode
- (void)setCaptureMode:(CaptureModes)captureMode error:(FlutterError * _Nullable __autoreleasing * _Nonnull)error {
  if (_videoController.isRecording) {
    *error = [FlutterError errorWithCode:@"CAPTURE_MODE" message:@"impossible to change capture mode, video already recording" details:@""];
    return;
  }
  
  _captureMode = captureMode;
  
  if (captureMode == Video) {
    [self setUpCaptureSessionForAudioError:^(NSError *audioError) {
      *error = [FlutterError errorWithCode:@"VIDEO_ERROR" message:@"error when trying to setup audio" details:[audioError localizedDescription]];
    }];
  }
}

- (void)refresh {
  if ([_captureSession isRunning]) {
    [self stop];
  }
  [self start];
}

# pragma mark - Camera picture

/// Take the picture into the given path
- (void)takePictureAtPath:(NSString *)path completion:(nonnull void (^)(NSNumber * _Nullable, FlutterError * _Nullable))completion {
  // Instanciate camera picture obj
  CameraPictureController *cameraPicture = [[CameraPictureController alloc] initWithPath:path
                                                                             orientation:_motionController.deviceOrientation
                                                                          sensorPosition:_cameraSensorPosition
                                                                         saveGPSLocation:_saveGPSLocation
                                                                       mirrorFrontCamera:_mirrorFrontCamera
                                                                             aspectRatio:_aspectRatio
                                                                              completion:completion
                                                                                callback:^{
    // If flash mode is always on, restore it back after photo is taken
    if (self->_torchMode == AVCaptureTorchModeOn) {
      [self->_captureDevice lockForConfiguration:nil];
      [self->_captureDevice setTorchMode:AVCaptureTorchModeOn];
      [self->_captureDevice unlockForConfiguration];
    }
    
    completion(@(YES), nil);
  }];
  
  // Create settings instance
  AVCapturePhotoSettings *settings = [AVCapturePhotoSettings photoSettings];
  [settings setFlashMode:_flashMode];
  [settings setHighResolutionPhotoEnabled:YES];
  
  [_capturePhotoOutput capturePhotoWithSettings:settings
                                       delegate:cameraPicture];
  
}

# pragma mark - Camera video
/// Record video into the given path
- (void)recordVideoAtPath:(NSString *)path completion:(nonnull void (^)(FlutterError * _Nullable))completion {
  if (!_videoController.isRecording) {
    [_videoController recordVideoAtPath:path captureDevice:_captureDevice orientation:_motionController.deviceOrientation audioSetupCallback:^{
      [self setUpCaptureSessionForAudioError:^(NSError *error) {
        completion([FlutterError errorWithCode:@"VIDEO_ERROR" message:@"error when trying to setup audio" details:[error localizedDescription]]);
      }];
    } videoWriterCallback:^{
      if (self->_videoController.isAudioEnabled) {
        [self->_audioOutput setSampleBufferDelegate:self queue:self->_dispatchQueue];
      }
      [self->_captureVideoOutput setSampleBufferDelegate:self queue:self->_dispatchQueue];
      
      completion(nil);
    } options:_videoOptions quality: _recordingQuality completion:completion];
  } else {
    completion([FlutterError errorWithCode:@"VIDEO_ERROR" message:@"already recording video" details:@""]);
  }
}

/// Pause video recording
- (void)pauseVideoRecording {
  [_videoController pauseVideoRecording];
}

/// Resume video recording after being paused
- (void)resumeVideoRecording {
  [_videoController resumeVideoRecording];
}

/// Stop recording video
- (void)stopRecordingVideo:(nonnull void (^)(NSNumber * _Nullable, FlutterError * _Nullable))completion {
  if (_videoController.isRecording) {
    [_videoController stopRecordingVideo:completion];
  } else {
    completion(@(NO), [FlutterError errorWithCode:@"VIDEO_ERROR" message:@"video is not recording" details:@""]);
  }
}

/// Set audio recording mode
- (void)setRecordingAudioMode:(bool)isAudioEnabled completion:(void(^)(NSNumber *_Nullable, FlutterError *_Nullable))completion {
  if (_videoController.isRecording) {
    completion(@(NO), [FlutterError errorWithCode:@"CHANGE_AUDIO_MODE" message:@"impossible to change audio mode, video already recording" details:@""]);
    return;
  }
  
  [_captureSession beginConfiguration];
  [_videoController setIsAudioEnabled:isAudioEnabled];
  [_videoController setIsAudioSetup:NO];
  [_videoController setAudioIsDisconnected:YES];
  
  // Only remove audio channel input but keep video
  for (AVCaptureInput *input in [_captureSession inputs]) {
    for (AVCaptureInputPort *port in input.ports) {
      if ([[port mediaType] isEqual:AVMediaTypeAudio]) {
        [_captureSession removeInput:input];
        break;
      }
    }
  }
  // Only remove audio channel output but keep video
  [_captureSession removeOutput:_audioOutput];
  
  if (_videoController.isRecording) {
    [self setUpCaptureSessionForAudioError:^(NSError *error) {
      completion(@(NO), [FlutterError errorWithCode:@"VIDEO_ERROR" message:@"error when trying to setup audio" details:[error localizedDescription]]);
    }];
  }
  
  [_captureSession commitConfiguration];
  completion(@(YES), nil);
}

# pragma mark - Audio
/// Setup audio channel to record audio
- (void)setUpCaptureSessionForAudioError:(nonnull void (^)(NSError *))error {
  // Batch all configuration changes to prevent intermediate session reconfigurations
  // This prevents preview flicker and ensures smooth user experience
  [_captureSession beginConfiguration];

  // CRITICAL FIX: Remove existing audio inputs before adding new ones
  // Fixes issue where subsequent video recordings fail because audio input already exists
  // This is the actual root cause of Flutter issues #30689 and #131553
  for (AVCaptureInput *input in [_captureSession inputs]) {
    for (AVCaptureInputPort *port in input.ports) {
      if ([[port mediaType] isEqual:AVMediaTypeAudio]) {
        [_captureSession removeInput:input];
        break;
      }
    }
  }

  // Remove existing audio output if present
  if (_audioOutput != nil) {
    [_captureSession removeOutput:_audioOutput];
  }

  NSError *audioError = nil;
  // Create a device input with the device and add it to the session.
  // Setup the audio input.
  AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
  AVCaptureDeviceInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice
                                                                           error:&audioError];
  if (audioError) {
    [_captureSession commitConfiguration];
    error(audioError);
    return;
  }

  // Setup the audio output.
  _audioOutput = [[AVCaptureAudioDataOutput alloc] init];

  if ([_captureSession canAddInput:audioInput]) {
    [_captureSession addInput:audioInput];

    if ([_captureSession canAddOutput:_audioOutput]) {
      [_captureSession addOutput:_audioOutput];
      [_videoController setIsAudioSetup:YES];
    } else {
      [_videoController setIsAudioSetup:NO];
      [_captureSession commitConfiguration];
      error([NSError errorWithDomain:@"CameraAwesome" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Cannot add audio output to capture session"}]);
      return;
    }
  } else {
    // CRITICAL: If we can't add audio input, mark audio as not setup and report error
    // This prevents the recording from starting in an invalid state
    [_videoController setIsAudioSetup:NO];
    [_captureSession commitConfiguration];
    error([NSError errorWithDomain:@"CameraAwesome" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Cannot add audio input to capture session"}]);
    return;
  }

  // Commit all changes atomically
  [_captureSession commitConfiguration];
}

# pragma mark - Camera Delegates

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
  if (output == _captureVideoOutput) {
    [self.previewTexture updateBuffer:sampleBuffer];
    if (_onPreviewFrameAvailable) {
      _onPreviewFrameAvailable();
    }

    // Send to image stream controller if enabled
    if (_imageStreamController.streamImages) {
        [_imageStreamController captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection orientation:_motionController.deviceOrientation];
    }

    // Send to video recording controller if recording
    if (_videoController.isRecording) {
      // Ensure VideoController's captureOutput can handle being called multiple times for the same timestamp (once for video, once for audio)
      // or ensure it only processes the video buffer here.
      // Assuming it can differentiate based on 'output' or buffer type.
      [_videoController captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection captureVideoOutput:_captureVideoOutput];
    }
  } else if (output == _audioOutput) {
    // Send audio buffers only to video recording controller if recording & audio enabled
    if (_videoController.isRecording && _videoController.isAudioEnabled) {
      [_videoController captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection captureVideoOutput:nil]; // Pass nil for video output for audio
    }
  }
}

@end
