import 'dart:collection';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:pure_live/common/style/bundled_fonts.dart';
import 'package:pure_live/plugins/emoji_manager.dart';
import 'package:pure_live/pkg/canvas_danmaku/models/danmaku_content_item.dart';

/// Shared by active danmakus and the bounded cache. Cache eviction never
/// disposes paragraphs that still have an active lease.
class DanmakuLayout {
  final String _cacheKey;
  final ui.Paragraph mainParagraph;
  final ui.Paragraph? strokeParagraph;
  final double width;
  final double height;
  final List<String> emojiKeys;
  final List<ui.TextBox> emojiBoxes;
  final double emojiSize;
  int _refCount = 0;
  bool _cached = false;
  bool _disposed = false;

  DanmakuLayout._({
    required String cacheKey,
    required this.mainParagraph,
    required this.strokeParagraph,
    required this.width,
    required this.height,
    required List<String> emojiKeys,
    required List<ui.TextBox> emojiBoxes,
    required this.emojiSize,
  }) : _cacheKey = cacheKey,
       emojiKeys = List.unmodifiable(emojiKeys),
       emojiBoxes = List.unmodifiable(emojiBoxes);

  @visibleForTesting
  int get refCount => _refCount;

  @visibleForTesting
  bool get isDisposed => _disposed;

  @visibleForTesting
  bool get isCached => _cached;

  void _retain() {
    if (_disposed) throw StateError('Cannot retain a disposed danmaku layout.');
    _refCount++;
  }

  /// Release the lease returned by [Utils.acquireLayout].
  void release() {
    if (_refCount == 0) throw StateError('Danmaku layout has no lease to release.');
    _refCount--;
    _disposeIfUnused();
  }

  void _disposeIfUnused() {
    if (_disposed || _cached || _refCount != 0) return;
    _disposed = true;
    mainParagraph.dispose();
    strokeParagraph?.dispose();
  }
}

class Utils {
  static final Paint _emojiPaint = Paint()..filterQuality = FilterQuality.medium;
  static final List<FontWeight> _fontWeights = FontWeight.values;
  static final LinkedHashMap<String, DanmakuLayout> _paragraphCache = LinkedHashMap();
  static const int _maxCacheSize = 300;

  @visibleForTesting
  static int get cacheLength => _paragraphCache.length;

  static String _getParagraphKey(DanmakuContentItem content, double fontSize, int fontWeight, bool showStroke) {
    // Emoji parsing changes when platform preload completes. Include the parsed
    // tokens so a text-only layout does not hide newly recognized image tokens.
    return jsonEncode([
      content.text,
      fontSize,
      fontWeight,
      content.color.toARGB32(),
      showStroke,
      content.fontFamily,
      for (final part in content.mixedContent) [part.type.index, part.value],
    ]);
  }

  /// Acquire one active lease. Candidates measure with cache:false and only
  /// enter the cache once accepted, avoiding cache churn from dropped messages.
  static DanmakuLayout acquireLayout(
    DanmakuContentItem content,
    double fontSize,
    int fontWeight,
    bool showStroke, {
    bool cache = true,
  }) {
    final key = _getParagraphKey(content, fontSize, fontWeight, showStroke);
    final cached = _paragraphCache.remove(key);
    if (cached != null) {
      _paragraphCache[key] = cached;
      cached._retain();
      return cached;
    }

    final layout = _buildLayout(key, content, fontSize, fontWeight, showStroke);
    layout._retain();
    if (cache) cacheLayout(layout);
    return layout;
  }

  /// Keep an accepted layout in the bounded LRU cache.
  static void cacheLayout(DanmakuLayout layout) {
    if (layout._disposed) throw StateError('Cannot cache a disposed danmaku layout.');
    final previous = _paragraphCache.remove(layout._cacheKey);
    if (previous != null && !identical(previous, layout)) {
      previous._cached = false;
      previous._disposeIfUnused();
    }
    layout._cached = true;
    _paragraphCache[layout._cacheKey] = layout;

    while (_paragraphCache.length > _maxCacheSize) {
      final oldest = _paragraphCache.remove(_paragraphCache.keys.first)!;
      oldest._cached = false;
      oldest._disposeIfUnused();
    }
  }

  /// Draw an acquired layout without cache lookup or repeated text layout.
  static void drawLayout(
    Canvas canvas,
    DanmakuLayout layout,
    Offset offset,
    bool selfSend,
    Paint? selfSendPaint,
  ) {
    if (layout._disposed) throw StateError('Cannot draw a disposed danmaku layout.');

    if (selfSend && selfSendPaint != null) {
      canvas.drawRect(offset & Size(layout.width, layout.height), selfSendPaint);
    }
    final strokeParagraph = layout.strokeParagraph;
    if (strokeParagraph != null) canvas.drawParagraph(strokeParagraph, offset);
    canvas.drawParagraph(layout.mainParagraph, offset);

    for (int i = 0; i < layout.emojiBoxes.length && i < layout.emojiKeys.length; i++) {
      final image = EmojiManager.getEmoji(layout.emojiKeys[i]);
      if (image == null) continue;
      final box = layout.emojiBoxes[i];
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(offset.dx + box.left, offset.dy + box.top, layout.emojiSize, layout.emojiSize),
        _emojiPaint,
      );
    }
  }

  static DanmakuLayout _buildLayout(
    String key,
    DanmakuContentItem content,
    double fontSize,
    int fontWeight,
    bool showStroke,
  ) {
    final targetFontWeight = _fontWeights[fontWeight.clamp(0, _fontWeights.length - 1).toInt()];
    final double emojiSize = fontSize * 1.2;
    final paragraphStyle = ui.ParagraphStyle(textAlign: TextAlign.left, textDirection: TextDirection.ltr, maxLines: 1);
    final mainBuilder = ui.ParagraphBuilder(paragraphStyle);
    final embeddedEmojis = <String>[];

    for (final item in content.mixedContent) {
      if (item.type == ContentType.text) {
        mainBuilder.pushStyle(
          ui.TextStyle(
            color: content.color,
            fontSize: fontSize,
            fontWeight: targetFontWeight,
            fontFamily: content.fontFamily,
            fontFamilyFallback: bundledEmojiFontFallback,
          ),
        );
        mainBuilder.addText(item.value);
        mainBuilder.pop();
      } else {
        mainBuilder.addPlaceholder(emojiSize, emojiSize, ui.PlaceholderAlignment.middle);
        embeddedEmojis.add(item.value);
      }
    }
    final mainParagraph = mainBuilder.build();
    ui.Paragraph? strokeParagraph;
    try {
      mainParagraph.layout(const ui.ParagraphConstraints(width: double.infinity));
      if (showStroke) {
        final strokeBuilder = ui.ParagraphBuilder(paragraphStyle);
        for (final item in content.mixedContent) {
          if (item.type == ContentType.text) {
            strokeBuilder.pushStyle(
              ui.TextStyle(
                fontSize: fontSize,
                fontWeight: targetFontWeight,
                fontFamily: content.fontFamily,
                fontFamilyFallback: bundledEmojiFontFallback,
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 2.0
                  ..color = Colors.black54,
              ),
            );
            strokeBuilder.addText(item.value);
            strokeBuilder.pop();
          } else {
            strokeBuilder.addPlaceholder(emojiSize, emojiSize, ui.PlaceholderAlignment.middle);
          }
        }
        strokeParagraph = strokeBuilder.build();
        strokeParagraph.layout(const ui.ParagraphConstraints(width: double.infinity));
      }

      return DanmakuLayout._(
        cacheKey: key,
        mainParagraph: mainParagraph,
        strokeParagraph: strokeParagraph,
        width: mainParagraph.longestLine,
        height: mainParagraph.height,
        emojiKeys: embeddedEmojis,
        emojiBoxes: embeddedEmojis.isEmpty ? const [] : mainParagraph.getBoxesForPlaceholders(),
        emojiSize: emojiSize,
      );
    } catch (_) {
      mainParagraph.dispose();
      strokeParagraph?.dispose();
      rethrow;
    }
  }

  /// Remove cache ownership; active items keep their layouts until release.
  static void clearCache() {
    final layouts = _paragraphCache.values.toList(growable: false);
    _paragraphCache.clear();
    for (final layout in layouts) {
      layout._cached = false;
      layout._disposeIfUnused();
    }
  }
}
