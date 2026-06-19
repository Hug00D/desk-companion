import 'package:flutter/material.dart';
import 'package:rive/rive.dart' as rv;

class RiveAssetBackground extends StatefulWidget {
  const RiveAssetBackground({
    super.key,
    required this.assetPath,
    this.motionIntensity = 10,
  });

  final String assetPath;
  final double motionIntensity;

  @override
  State<RiveAssetBackground> createState() => _RiveAssetBackgroundState();
}

class _RiveAssetBackgroundState extends State<RiveAssetBackground> {
  static const String _motionInputName = 'Bop amount';

  late rv.FileLoader _fileLoader;
  rv.NumberInput? _motionInput;
  bool _hasLoggedMotionInput = false;

  @override
  void initState() {
    super.initState();
    _fileLoader = rv.FileLoader.fromAsset(
      widget.assetPath,
      riveFactory: rv.Factory.rive,
    );
  }

  @override
  void didUpdateWidget(covariant RiveAssetBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath) {
      _motionInput = null;
      _fileLoader.dispose();
      _fileLoader = rv.FileLoader.fromAsset(
        widget.assetPath,
        riveFactory: rv.Factory.rive,
      );
    }
    if (oldWidget.motionIntensity != widget.motionIntensity) {
      _applyMotionIntensity();
    }
  }

  @override
  void dispose() {
    _fileLoader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return rv.RiveWidgetBuilder(
      fileLoader: _fileLoader,
      onFailed: (error, stackTrace) {
        debugPrint('Rive asset load failed (${widget.assetPath}): $error');
      },
      onLoaded: (state) {
        _motionInput = state.controller.stateMachine.number(_motionInputName);
        if (!_hasLoggedMotionInput) {
          _hasLoggedMotionInput = true;
          debugPrint(
            _motionInput == null
                ? 'Rive motion input not found: $_motionInputName'
                : 'Rive motion input ready: $_motionInputName',
          );
        }
        _applyMotionIntensity();
      },
      builder: (context, state) => switch (state) {
        rv.RiveLoaded() => rv.RiveWidget(
          controller: state.controller,
          fit: rv.Fit.cover,
        ),
        rv.RiveFailed() => const ColoredBox(color: Color(0xFF10283D)),
        rv.RiveLoading() => const ColoredBox(color: Color(0xFF10283D)),
      },
    );
  }

  void _applyMotionIntensity() {
    final input = _motionInput;
    if (input == null) return;
    input.value = widget.motionIntensity.clamp(0, 20).toDouble();
    debugPrint(
      'Rive motion intensity: ${input.value.toStringAsFixed(1)}',
    );
  }
}
