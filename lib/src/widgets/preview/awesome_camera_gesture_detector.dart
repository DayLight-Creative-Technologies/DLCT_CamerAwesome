import 'dart:async';
import 'dart:math' as math;

import 'package:camerawesome/pigeon.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:camerawesome/src/widgets/preview/awesome_focus_indicator.dart';

Widget _awesomeFocusBuilder(Offset tapPosition) {
  return AwesomeFocusIndicator(position: tapPosition);
}

class OnPreviewTapBuilder {
  // Use getters instead of storing the direct value to retrieve the data onTap
  final PreviewSize Function() pixelPreviewSizeGetter;
  final PreviewSize Function() flutterPreviewSizeGetter;
  final OnPreviewTap onPreviewTap;

  const OnPreviewTapBuilder({
    required this.pixelPreviewSizeGetter,
    required this.flutterPreviewSizeGetter,
    required this.onPreviewTap,
  });
}

class OnPreviewTap {
  final Function(Offset position, PreviewSize flutterPreviewSize,
      PreviewSize pixelPreviewSize) onTap;
  final Widget Function(Offset tapPosition)? onTapPainter;
  final Duration? tapPainterDuration;

  const OnPreviewTap({
    required this.onTap,
    this.onTapPainter = _awesomeFocusBuilder,
    this.tapPainterDuration = const Duration(milliseconds: 2000),
  });
}

class OnPreviewScale {
  final Function(double scale) onScale;

  const OnPreviewScale({
    required this.onScale,
  });
}

class AwesomeCameraGestureDetector extends StatefulWidget {
  final Widget child;
  final OnPreviewTapBuilder? onPreviewTapBuilder;
  final OnPreviewScale? onPreviewScale;
  final double initialZoom;

  const AwesomeCameraGestureDetector({
    super.key,
    required this.child,
    required this.onPreviewScale,
    this.onPreviewTapBuilder,
    this.initialZoom = 0,
  });

  @override
  State<StatefulWidget> createState() {
    return _AwesomeCameraGestureDetector();
  }
}

class _AwesomeCameraGestureDetector
    extends State<AwesomeCameraGestureDetector> {
  double _zoomScale = 0;

  // Logarithmic pinch-to-zoom: finger spread is mapped through log2 so that
  // doubling finger distance always produces the same zoom delta regardless of
  // current zoom level. Lower = more finger movement required.
  static const double _sensitivity = 0.20;
  double _gestureStartZoom = 0;

  Offset? _tapPosition;
  Timer? _timer;

  @override
  void initState() {
    _zoomScale = widget.initialZoom;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory>{
        if (widget.onPreviewScale != null)
          ScaleGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<ScaleGestureRecognizer>(
            () => ScaleGestureRecognizer()
              ..onStart = (_) {
                _gestureStartZoom = _zoomScale;
              }
              ..onUpdate = (ScaleUpdateDetails details) {
                // log2(scale): doubling finger spread = +1.0, halving = -1.0.
                // Multiplied by sensitivity to control how much zoom per spread.
                final logDelta =
                    math.log(details.scale.clamp(0.1, 10.0)) / math.ln2;
                _zoomScale =
                    (_gestureStartZoom + logDelta * _sensitivity).clamp(0, 1);
                widget.onPreviewScale!.onScale(_zoomScale);
              }
              ..onEnd = (_) {
                // Snapshot for next gesture
                _gestureStartZoom = _zoomScale;
              },
            (instance) {},
          ),
        if (widget.onPreviewTapBuilder != null)
          TapGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            () => TapGestureRecognizer()
              ..onTapUp = (details) {
                if (widget
                        .onPreviewTapBuilder!.onPreviewTap.tapPainterDuration !=
                    null) {
                  _timer?.cancel();
                  _timer = Timer(
                      widget.onPreviewTapBuilder!.onPreviewTap
                          .tapPainterDuration!, () {
                    setState(() {
                      _tapPosition = null;
                    });
                  });
                }
                setState(() {
                  _tapPosition = details.localPosition;
                });
                widget.onPreviewTapBuilder!.onPreviewTap.onTap(
                  _tapPosition!,
                  widget.onPreviewTapBuilder!.flutterPreviewSizeGetter(),
                  widget.onPreviewTapBuilder!.pixelPreviewSizeGetter(),
                );
              },
            (instance) {},
          ),
      },
      child: Stack(children: [
        Positioned.fill(child: widget.child),
        if (_tapPosition != null &&
            widget.onPreviewTapBuilder?.onPreviewTap.onTapPainter != null)
          widget.onPreviewTapBuilder!.onPreviewTap.onTapPainter!(_tapPosition!),
      ]),
    );
  }

  @override
  dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
