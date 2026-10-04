import 'dart:math';
import 'package:flutter/material.dart';
import 'package:pure_live/common/style/bundled_fonts.dart';
import 'package:pure_live/pkg/canvas_danmaku/utils/utils.dart';
import 'package:pure_live/pkg/canvas_danmaku/danmaku_controller.dart';
import 'package:pure_live/pkg/canvas_danmaku/models/danmaku_item.dart';
import 'package:pure_live/pkg/canvas_danmaku/models/danmaku_option.dart';
import 'package:pure_live/pkg/canvas_danmaku/scroll_danmaku_painter.dart';
import 'package:pure_live/pkg/canvas_danmaku/models/danmaku_content_item.dart';

class DanmakuScreen extends StatefulWidget {
  final DanmakuController controller;
  final DanmakuOption option;

  const DanmakuScreen({required this.controller, required this.option, super.key});

  @override
  State<DanmakuScreen> createState() => _DanmakuScreenState();
}

class _DanmakuScreenState extends State<DanmakuScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  double _viewWidth = 0;
  double _viewHeight = 0;
  late DanmakuController _controller;
  late final AnimationController _animationController;
  late DanmakuOption _option;

  final Map<double, List<DanmakuItem>> _scrollDanmakuByTrack = {};
  final List<DanmakuItem> _topDanmakuItems = [];
  final List<DanmakuItem> _bottomDanmakuItems = [];
  final List<DanmakuItem> _specialDanmakuItems = [];
  final List<DanmakuItem> _flattenedScrollDanmakus = [];
  final List<double> _trackYPositions = [];
  final _random = Random();
  double _danmakuHeight = 0;
  int _elapsedMilliseconds = 0;
  int _lastAnimationElapsedMilliseconds = 0;
  bool _running = true;

  int get _tick => _elapsedMilliseconds;
  int get _durationInSeconds => max(1, _option.duration);
  bool get _hasDanmakus => _scrollDanmakuByTrack.isNotEmpty ||
      _topDanmakuItems.isNotEmpty || _bottomDanmakuItems.isNotEmpty || _specialDanmakuItems.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _option = widget.option;
    _running = _controller.running;
    _controller.option = _option;
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(seconds: _durationInSeconds),
    )..addListener(_handleFrame);
    _bindControllerCallbacks();
    WidgetsBinding.instance.addObserver(this);
    _calculateTracksGeometry();
  }

  void _bindControllerCallbacks() {
    _controller.onAddDanmaku = addDanmaku;
    _controller.onUpdateOption = updateOption;
    _controller.onPause = pause;
    _controller.onResume = resume;
    _controller.onClear = clearDanmakus;
  }

  void _calculateTracksGeometry() {
    final textPainter = TextPainter(
      text: TextSpan(text: 'danmaku', style: TextStyle(fontSize: _option.fontSize)),
      textDirection: TextDirection.ltr,
    );
    try {
      textPainter.layout();
      _danmakuHeight = textPainter.height;
    } finally {
      textPainter.dispose();
    }
    _trackYPositions.clear();
    if (_viewWidth <= 0 || _viewHeight <= 0 || _danmakuHeight <= 0) return;
    final displayHeight = (_viewHeight - _option.topAreaDistance - _option.bottomAreaDistance) * _option.area;
    final trackCount = (displayHeight / _danmakuHeight).floor().clamp(0, 999);
    for (int i = 0; i < trackCount; i++) {
      _trackYPositions.add(_option.topAreaDistance + i * _danmakuHeight);
    }
  }

  void _startAnimation() {
    if (!_running || !_hasDanmakus || _animationController.isAnimating) return;
    _lastAnimationElapsedMilliseconds = 0;
    _animationController.repeat();
  }

  void _handleFrame() {
    if (!_running || !mounted) return;
    final elapsed = _animationController.lastElapsedDuration?.inMilliseconds ?? 0;
    _elapsedMilliseconds += max(0, elapsed - _lastAnimationElapsedMilliseconds);
    _lastAnimationElapsedMilliseconds = elapsed;

    final duration = _durationInSeconds * 1000;
    bool scrollChanged = false;
    _scrollDanmakuByTrack.removeWhere((_, items) {
      if (_removeExpired(items, duration)) scrollChanged = true;
      return items.isEmpty;
    });
    if (scrollChanged) _rebuildScrollList();
    _removeExpired(_topDanmakuItems, duration);
    _removeExpired(_bottomDanmakuItems, duration);
    _specialDanmakuItems.removeWhere((item) {
      if (_tick - item.creationTime < (item.content as SpecialDanmakuContentItem).duration) return false;
      item.dispose();
      return true;
    });
    if (!_hasDanmakus) _animationController.stop();
  }

  bool _removeExpired(List<DanmakuItem> items, int duration) {
    final oldLength = items.length;
    items.removeWhere((item) {
      if (_tick - item.creationTime < duration) return false;
      item.dispose();
      return true;
    });
    return oldLength != items.length;
  }

  void _rebuildScrollList() {
    _flattenedScrollDanmakus.clear();
    for (final items in _scrollDanmakuByTrack.values) {
      _flattenedScrollDanmakus.addAll(items);
    }
  }

  void _disposeItems(List<DanmakuItem> items) {
    for (final item in items) {
      item.dispose();
    }
    items.clear();
  }

  void _clearScrollItems() {
    for (final items in _scrollDanmakuByTrack.values) {
      _disposeItems(items);
    }
    _scrollDanmakuByTrack.clear();
    _flattenedScrollDanmakus.clear();
  }

  void _disposeAllDanmakus() {
    _clearScrollItems();
    _disposeItems(_topDanmakuItems);
    _disposeItems(_bottomDanmakuItems);
    _disposeItems(_specialDanmakuItems);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) pause();
    if (state == AppLifecycleState.resumed) resume();
  }

  @override
  void dispose() {
    _running = false;
    _controller.unbind(addDanmaku);
    WidgetsBinding.instance.removeObserver(this);
    _animationController.dispose();
    _disposeAllDanmakus();
    Utils.clearCache();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DanmakuScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != _controller) {
      _controller.unbind(addDanmaku);
      _disposeAllDanmakus();
      _animationController.stop();
      _controller = widget.controller;
      _running = _controller.running;
    }
    _bindControllerCallbacks();
    if (widget.option != oldWidget.option) updateOption(widget.option);
  }

  void addDanmaku(DanmakuContentItem content) {
    if (!_running || !mounted || _trackYPositions.isEmpty) return;
    if (content.type == DanmakuItemType.special) {
      if (_option.hideSpecial) return;
      final special = content as SpecialDanmakuContentItem;
      special.painterCache = TextPainter(
        text: TextSpan(
          text: special.text,
          style: TextStyle(
            color: special.color,
            fontSize: special.fontSize,
            fontWeight: FontWeight.values[_option.fontWeight.clamp(0, FontWeight.values.length - 1).toInt()],
            fontFamily: special.fontFamily,
            fontFamilyFallback: bundledEmojiFontFallback,
            shadows: special.hasStroke
                ? [Shadow(color: Colors.black.withAlpha((255 * (special.alphaTween?.begin ?? special.color.a)).toInt()), blurRadius: 2)]
                : null,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      _specialDanmakuItems.add(DanmakuItem(
        width: 0, height: 0, creationTime: _tick, content: content,
      ));
      _startAnimation();
      return;
    }
    if ((content.type == DanmakuItemType.scroll && _option.hideScroll) ||
        (content.type == DanmakuItemType.top && _option.hideTop) ||
        (content.type == DanmakuItemType.bottom && _option.hideBottom)) return;

    // Rejected messages do not evict the layouts of currently visible danmaku.
    final layout = Utils.acquireLayout(content, _option.fontSize, _option.fontWeight, _option.showStroke, cache: false);
    double? targetY;
    for (final y in _trackYPositions) {
      final canAdd = switch (content.type) {
        DanmakuItemType.scroll => _scrollCanAddToTrack(y, layout.width),
        DanmakuItemType.top => !_topDanmakuItems.any((item) => item.yPosition == y),
        DanmakuItemType.bottom => !_bottomDanmakuItems.any((item) => item.yPosition == y),
        DanmakuItemType.special => false,
      };
      if (canAdd) {
        targetY = y;
        break;
      }
    }
    if (targetY == null && content.type == DanmakuItemType.scroll) {
      if (content.selfSend) targetY = _trackYPositions.first;
      if (_option.massiveMode && targetY == null) targetY = _trackYPositions[_random.nextInt(_trackYPositions.length)];
    }
    if (targetY == null) {
      layout.release();
      return;
    }
    Utils.cacheLayout(layout);
    final item = DanmakuItem(
      yPosition: targetY, xPosition: _viewWidth, width: layout.width, height: layout.height,
      creationTime: _tick, content: content, layout: layout,
    );
    switch (content.type) {
      case DanmakuItemType.scroll:
        _scrollDanmakuByTrack.putIfAbsent(targetY, () => []).add(item);
        _flattenedScrollDanmakus.add(item);
      case DanmakuItemType.top:
        _topDanmakuItems.add(item);
      case DanmakuItemType.bottom:
        _bottomDanmakuItems.add(item);
      case DanmakuItemType.special:
        item.dispose();
    }
    _startAnimation();
  }

  void pause() {
    if (!mounted || !_running) return;
    _running = false;
    _animationController.stop();
    setState(() {});
  }

  void resume() {
    if (!mounted || _running) return;
    _running = true;
    _startAnimation();
    setState(() {});
  }

  void updateOption(DanmakuOption option) {
    final layoutChanged = option.fontSize != _option.fontSize || option.fontWeight != _option.fontWeight ||
        option.showStroke != _option.showStroke;
    if (layoutChanged) {
      _disposeAllDanmakus();
      Utils.clearCache();
    } else {
      if (option.hideScroll && !_option.hideScroll) _clearScrollItems();
      if (option.hideTop && !_option.hideTop) _disposeItems(_topDanmakuItems);
      if (option.hideBottom && !_option.hideBottom) _disposeItems(_bottomDanmakuItems);
      if (option.hideSpecial && !_option.hideSpecial) _disposeItems(_specialDanmakuItems);
    }
    _option = option;
    _controller.option = option;
    if (_animationController.duration != Duration(seconds: _durationInSeconds)) {
      _animationController.stop();
      _animationController.duration = Duration(seconds: _durationInSeconds);
    }
    _calculateTracksGeometry();
    if (!_hasDanmakus) _animationController.stop();
    _startAnimation();
    if (mounted) setState(() {});
  }

  void clearDanmakus() {
    if (!mounted) return;
    _animationController.stop();
    _disposeAllDanmakus();
    Utils.clearCache();
    setState(() {});
  }

  bool _scrollCanAddToTrack(double yPosition, double newDanmakuWidth) {
    final trackItems = _scrollDanmakuByTrack[yPosition];
    if (trackItems == null || trackItems.isEmpty) return true;
    final item = trackItems.last;
    final progress = (_tick - item.creationTime) / (_durationInSeconds * 1000);
    final currentX = _viewWidth + (-item.width - _viewWidth) * progress;
    if (_viewWidth - (currentX + item.width) < 0) return false;
    if (item.width < newDanmakuWidth &&
        (1 - ((_viewWidth - currentX) / (item.width + _viewWidth))) > (_viewWidth / (_viewWidth + newDanmakuWidth))) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth != _viewWidth || constraints.maxHeight != _viewHeight) {
        _viewWidth = constraints.maxWidth;
        _viewHeight = constraints.maxHeight;
        _calculateTracksGeometry();
      }
      return ClipRect(
        child: IgnorePointer(
          child: Opacity(
            opacity: _option.opacity,
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  if (!_hasDanmakus) return const SizedBox.shrink();
                  return CustomPaint(
                    size: Size(_viewWidth, _viewHeight),
                    painter: ScrollDanmakuPainter(
                      _animationController.value, _flattenedScrollDanmakus, _durationInSeconds,
                      _option.fontSize, _option.fontWeight, _option.showStroke,
                      _danmakuHeight, _running, _tick,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    });
  }
}
