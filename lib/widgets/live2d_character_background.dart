import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_live2d/flutter_live2d.dart';

import '../companion/character_reaction.dart';

class Live2DCharacterBackground extends StatefulWidget {
  const Live2DCharacterBackground({
    super.key,
    this.mood = CompanionCharacterMood.neutral,
    this.reaction = CompanionCharacterReaction.none,
    this.reactionSerial = 0,
    this.paused = false,
  });

  final CompanionCharacterMood mood;
  final CompanionCharacterReaction reaction;
  final int reactionSerial;

  /// 由外部要求暫停算圖（例如切換到其他畫面時）。實際是否暫停還會併入
  /// App 生命週期狀態一起判斷。
  final bool paused;

  @override
  State<Live2DCharacterBackground> createState() =>
      _Live2DCharacterBackgroundState();
}

class _Live2DCharacterBackgroundState extends State<Live2DCharacterBackground>
    with WidgetsBindingObserver {
  static const String _modelDir = 'assets/March 7th/';
  static const String _modelFileName = 'march 7th.model3.json';

  final Live2DViewController _controller = Live2DViewController();
  Timer? _reactionTimer;
  int _commandGeneration = 0;
  bool _appResumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeModel());
  }

  Future<void> _initializeModel() async {
    try {
      await _controller.whenAttached;
      var loaded = false;
      for (var attempt = 1; attempt <= 4 && mounted && !loaded; attempt++) {
        loaded = await _controller.loadModel(
          modelDir: _modelDir,
          modelFileName: _modelFileName,
        );
        debugPrint('Live2D model load attempt $attempt: $loaded');
        if (!loaded) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
      if (!mounted || !loaded) return;
      await _applyMood();
      if (widget.reaction != CompanionCharacterReaction.none) {
        await _playReaction(widget.reaction);
      }
      _syncRenderingPaused();
    } catch (error) {
      debugPrint('Live2D model load failed: $error');
    }
  }

  @override
  void didUpdateWidget(covariant Live2DCharacterBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_controller.value.isLoaded) return;

    if (oldWidget.reactionSerial != widget.reactionSerial &&
        widget.reaction != CompanionCharacterReaction.none) {
      unawaited(_playReaction(widget.reaction));
      return;
    }
    if (oldWidget.mood != widget.mood && _reactionTimer == null) {
      unawaited(_applyMood());
    }
    if (oldWidget.paused != widget.paused) {
      _syncRenderingPaused();
    }
  }

  Future<void> _playReaction(CompanionCharacterReaction reaction) async {
    final generation = ++_commandGeneration;
    _reactionTimer?.cancel();
    _reactionTimer = null;

    try {
      final expressionIndex = reaction.expressionIndex;
      if (expressionIndex != null) {
        await _controller.setExpression(expressionIndex);
      } else {
        await _applyMood();
      }

      final motionGroup = reaction.motionGroup;
      if (motionGroup != null) {
        await _controller.startMotion(group: motionGroup, priority: 3);
      }
    } catch (error) {
      debugPrint('Live2D reaction failed (${reaction.name}): $error');
      return;
    }

    if (!mounted || generation != _commandGeneration) return;
    final holdDuration = reaction.holdDuration;
    if (holdDuration == Duration.zero) return;
    _reactionTimer = Timer(holdDuration, () {
      _reactionTimer = null;
      if (mounted && generation == _commandGeneration) {
        unawaited(_applyMood());
      }
    });
  }

  Future<void> _applyMood() async {
    try {
      await _controller.setExpression(widget.mood.expressionIndex);
    } catch (error) {
      debugPrint('Live2D mood update failed (${widget.mood.name}): $error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    _syncRenderingPaused();
  }

  /// 只要 App 進入背景，或外部要求 [Live2DCharacterBackground.paused]，就暫停算圖。
  void _syncRenderingPaused() {
    if (!_controller.value.isLoaded) return;
    unawaited(_setRenderingPaused(widget.paused || !_appResumed));
  }

  Future<void> _setRenderingPaused(bool paused) async {
    try {
      await _controller.setRenderingPaused(paused);
    } catch (error) {
      debugPrint('Live2D render lifecycle update failed: $error');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reactionTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF10283D),
      child: IgnorePointer(child: Live2DView(controller: _controller)),
    );
  }
}
