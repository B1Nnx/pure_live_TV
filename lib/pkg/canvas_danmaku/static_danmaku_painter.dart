import 'models/danmaku_item.dart';
import 'package:flutter/material.dart';
import 'package:pure_live/pkg/canvas_danmaku/utils/utils.dart';

class StaticDanmakuPainter extends CustomPainter {
  final double progress;
  final List<DanmakuItem> topDanmakuItems;
  final List<DanmakuItem> buttomDanmakuItems;
  final int danmakuDurationInSeconds;
  final double fontSize;
  final int fontWeight;
  final bool showStroke;
  final double danmakuHeight;
  final bool running;
  final int tick;
  final Paint selfSendPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = Colors.green;

  StaticDanmakuPainter(
    this.progress,
    this.topDanmakuItems,
    this.buttomDanmakuItems,
    this.danmakuDurationInSeconds,
    this.fontSize,
    this.fontWeight,
    this.showStroke,
    this.danmakuHeight,
    this.running,
    this.tick,
  );

  @override
  void paint(Canvas canvas, Size size) {
    // 绘制顶部弹幕
    for (var item in topDanmakuItems) {
      final layout = item.layout;
      if (layout == null) continue;
      item.xPosition = (size.width - item.width) / 2;
      Utils.drawLayout(canvas, layout, Offset(item.xPosition, item.yPosition), item.content.selfSend, selfSendPaint);
    }
    // 绘制底部弹幕 (翻转绘制)
    for (var item in buttomDanmakuItems) {
      final layout = item.layout;
      if (layout == null) continue;
      item.xPosition = (size.width - item.width) / 2;
      Utils.drawLayout(
        canvas,
        layout,
        Offset(item.xPosition, size.height - item.yPosition - danmakuHeight),
        item.content.selfSend,
        selfSendPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant StaticDanmakuPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        topDanmakuItems.length != oldDelegate.topDanmakuItems.length ||
        buttomDanmakuItems.length != oldDelegate.buttomDanmakuItems.length ||
        tick != oldDelegate.tick ||
        fontSize != oldDelegate.fontSize;
  }
}
