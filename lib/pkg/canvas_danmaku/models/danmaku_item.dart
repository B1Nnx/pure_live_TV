import 'package:pure_live/pkg/canvas_danmaku/models/danmaku_content_item.dart';
import 'package:pure_live/pkg/canvas_danmaku/utils/utils.dart';

class DanmakuItem {
  /// 弹幕内容
  final DanmakuContentItem content;

  /// 弹幕创建时间
  final int creationTime;

  /// 弹幕宽度
  final double width;

  /// 弹幕高度
  final double height;

  /// 弹幕水平方向位置
  double xPosition;

  /// 弹幕竖直方向位置
  double yPosition;

  /// One lease held for as long as this item remains active.
  DanmakuLayout? layout;
  bool _disposed = false;

  DanmakuItem({
    required this.content,
    required this.creationTime,
    required this.height,
    required this.width,
    this.xPosition = 0,
    this.yPosition = 0,
    this.layout,
  });

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    layout?.release();
    layout = null;
    final special = content;
    if (special is SpecialDanmakuContentItem) {
      special.painterCache?.dispose();
      special.painterCache = null;
    }
  }
}
