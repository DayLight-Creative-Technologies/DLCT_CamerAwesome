// ignore_for_file: close_sinks

import 'dart:async';

import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:camerawesome/pigeon.dart';
import 'package:rxdart/rxdart.dart';

// TODO find a way to explain that this sensorconfig is not bound anymore (user changed sensor for example)
class SensorConfig {
  late BehaviorSubject<FlashMode> _flashModeController;

  late BehaviorSubject<SensorType> _sensorTypeController;

  late Stream<FlashMode> flashMode$;

  late Stream<SensorType> sensorType$;

  late BehaviorSubject<CameraAspectRatios> _aspectRatioController;

  late Stream<CameraAspectRatios> aspectRatio$;

  /// Zoom from native side. Must be between 0.0 and 1.0
  late Stream<double> zoom$;

  /// [back] or [front] camera
  final List<Sensor> sensors;

  // /// choose your photo size from the [selectDefaultSize] method
  // late Stream<Size?> previewSize;

  /// set brightness correction manually range [0,1] (optional)
  late Stream<double>? brightness$;

  late BehaviorSubject<double> _zoomController;

  /// Use this stream to debounce brightness events
  final BehaviorSubject<double> _brightnessController =
      BehaviorSubject<double>();
  StreamSubscription? _brightnessSubscription;

  SensorConfig.single({
    Sensor? sensor,
    FlashMode flashMode = FlashMode.none,
    double zoom = 0.0,
    CameraAspectRatios aspectRatio = CameraAspectRatios.ratio_4_3,
  }) : this._(
          sensors: [sensor ?? Sensor.position(SensorPosition.back)],
          flash: flashMode,
          currentZoom: zoom,
          aspectRatio: aspectRatio,
        );

  SensorConfig.multiple({
    required List<Sensor> sensors,
    FlashMode flashMode = FlashMode.none,
    double zoom = 0.0,
    CameraAspectRatios aspectRatio = CameraAspectRatios.ratio_4_3,
  }) : this._(
          sensors: sensors,
          flash: flashMode,
          currentZoom: zoom,
          aspectRatio: aspectRatio,
        );

  SensorConfig._({
    required this.sensors,
    FlashMode flash = FlashMode.none,
    CameraAspectRatios aspectRatio = CameraAspectRatios.ratio_4_3,

    /// Zoom must be between 0.0 (no zoom) and 1.0 (max zoom)
    double currentZoom = 0.0,
  }) {
    _flashModeController = BehaviorSubject<FlashMode>.seeded(flash);
    flashMode$ = _flashModeController.stream;

    _sensorTypeController = BehaviorSubject<SensorType>.seeded(
        sensors.first.type ?? SensorType.wideAngle);
    sensorType$ = _sensorTypeController.stream;

    _zoomController = BehaviorSubject<double>.seeded(currentZoom);
    zoom$ = _zoomController.stream;

    _aspectRatioController = BehaviorSubject.seeded(aspectRatio);
    aspectRatio$ = _aspectRatioController.stream;

    _brightnessSubscription = _brightnessController.stream
        .debounceTime(const Duration(milliseconds: 500))
        .listen((value) => CamerawesomePlugin.setBrightness(value));
  }

  Future<void> setZoom(double zoom) async {
    if (zoom < 0 || zoom > 1) {
      throw "Zoom value must be between 0 and 1";
    }
    await CamerawesomePlugin.setZoom(zoom);
    if (!_zoomController.isClosed) {
      _zoomController.sink.add(zoom);
    }
  }

  /// Returns the current zoom without stream
  double get zoom => _zoomController.value;

  /// Set manually the [FlashMode] between
  /// [FlashMode.none] no flash
  /// [FlashMode.on] always flashing when taking photo
  /// [FlashMode.auto] let the camera decide if it should use flash or not
  /// [FlashMode.always] flash light stays open
  Future<void> setFlashMode(FlashMode flashMode) async {
    await CamerawesomePlugin.setFlashMode(flashMode);
    _flashModeController.sink.add(flashMode);
  }

  /// Returns the current flash mode without stream
  FlashMode get flashMode => _flashModeController.value;

  /// Switch the flash according to the previous state
  void switchCameraFlash() {
    final FlashMode newFlashMode;
    switch (flashMode) {
      case FlashMode.none:
        newFlashMode = FlashMode.auto;
        break;
      case FlashMode.on:
        newFlashMode = FlashMode.always;
        break;
      case FlashMode.auto:
        newFlashMode = FlashMode.on;
        break;
      case FlashMode.always:
        newFlashMode = FlashMode.none;
        break;
    }
    setFlashMode(newFlashMode);
  }

  /// switch the camera preview / photo / video aspect ratio
  /// [CameraAspectRatios.ratio_16_9]
  /// [CameraAspectRatios.ratio_4_3]
  /// [CameraAspectRatios.ratio_1_1]
  Future<void> switchCameraRatio() async {
    if (aspectRatio == CameraAspectRatios.ratio_16_9) {
      setAspectRatio(CameraAspectRatios.ratio_4_3);
    } else if (aspectRatio == CameraAspectRatios.ratio_4_3) {
      setAspectRatio(CameraAspectRatios.ratio_1_1);
    } else {
      setAspectRatio(CameraAspectRatios.ratio_16_9);
    }
  }

  /// Change the current [CameraAspectRatios] one of
  /// [CameraAspectRatios.ratio_16_9]
  /// [CameraAspectRatios.ratio_4_3]
  /// [CameraAspectRatios.ratio_1_1]
  Future<void> setAspectRatio(CameraAspectRatios ratio) async {
    await CamerawesomePlugin.setAspectRatio(ratio.name);
    _aspectRatioController.add(ratio);
  }

  /// Returns the current camera aspect ratio without stream
  CameraAspectRatios get aspectRatio => _aspectRatioController.value;

  /// set brightness correction manually range [0,1] (optionnal)
  setBrightness(double brightness) {
    if (brightness < 0 || brightness > 1) {
      throw "Brightness value must be between 0 and 1";
    }
    // The stream will debounce before actually setting the brightness
    _brightnessController.sink.add(brightness);
  }

  /// Returns the current brightness without stream
  double get brightness => _brightnessController.value;

  // === MANUAL EXPOSURE ===

  /// Query device exposure capabilities (ISO range, shutter speed range, support)
  Future<ExposureCapabilities> getExposureCapabilities() {
    return CamerawesomePlugin.getExposureCapabilities();
  }

  /// Set ISO priority mode. Pass -1 to return to auto.
  Future<void> setManualISO(double iso) async {
    await CamerawesomePlugin.setManualISO(iso);
  }

  /// Set shutter speed priority mode. Duration in seconds. Pass -1 to return to auto.
  Future<void> setManualShutterSpeed(double durationInSeconds) async {
    await CamerawesomePlugin.setManualShutterSpeed(durationInSeconds);
  }

  /// Full manual mode. Pass -1 for either param to keep it auto.
  Future<void> setManualExposure(double iso, double durationInSeconds) async {
    await CamerawesomePlugin.setManualExposure(iso, durationInSeconds);
  }

  /// Return to fully automatic exposure.
  Future<void> setAutoExposure() async {
    await CamerawesomePlugin.setAutoExposure();
  }

  // === SMOOTH ZOOM ===

  /// Native-ramped smooth zoom. [zoom] normalized 0.0-1.0.
  /// iOS: [rateOrDuration] is the rate (1.0+, higher = faster).
  /// Android: [rateOrDuration] is animation duration in ms.
  Future<void> setSmoothZoom(double zoom, {double rateOrDuration = 4.0}) async {
    final clampedZoom = zoom.clamp(0.0, 1.0);
    await CamerawesomePlugin.setSmoothZoom(clampedZoom, rateOrDuration);
    if (!_zoomController.isClosed) {
      _zoomController.sink.add(clampedZoom);
    }
  }

  void dispose() {
    _brightnessSubscription?.cancel();
    _brightnessController.close();
    _sensorTypeController.close();
    _zoomController.close();
    _flashModeController.close();
    _aspectRatioController.close();
  }
}
