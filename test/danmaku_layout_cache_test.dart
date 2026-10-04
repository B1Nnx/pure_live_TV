import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/style/bundled_fonts.dart';
import 'package:pure_live/pkg/canvas_danmaku/models/danmaku_content_item.dart';
import 'package:pure_live/pkg/canvas_danmaku/models/danmaku_item.dart';
import 'package:pure_live/pkg/canvas_danmaku/utils/utils.dart';
import 'package:pure_live/plugins/emoji_manager.dart';

DanmakuLayout _acquire(String text, {bool stroke = false, bool cache = true}) {
  return Utils.acquireLayout(DanmakuContentItem(text), 16, 4, stroke, cache: cache);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(Utils.clearCache);
  tearDown(() {
    Utils.clearCache();
    EmojiManager.instance.clearCache();
  });

  test('cache hits share one main paragraph without unnecessary stroke layout', () {
    final first = _acquire('same content');
    final second = _acquire('same content');
    expect(second, same(first));
    expect(second.mainParagraph, same(first.mainParagraph));
    expect(first.strokeParagraph, isNull);
    expect(first.refCount, 2);
    expect(Utils.cacheLength, 1);

    first.release();
    expect(second.refCount, 1);
    expect(second.isDisposed, isFalse);
    second.release();
    expect(first.refCount, 0);
    expect(first.isDisposed, isFalse);
    Utils.clearCache();
    expect(first.isDisposed, isTrue);
  });

  test('LRU evicts one entry while active leases remain usable', () {
    final recentlyUsed = _acquire('recently used');
    final oldest = _acquire('oldest after hit');
    for (var entry = 0; entry < 298; entry++) {
      _acquire('filler $entry').release();
    }
    expect(Utils.cacheLength, 300);
    final hit = _acquire('recently used');
    expect(hit, same(recentlyUsed));
    hit.release();

    final newcomer = _acquire('new cache entry');
    expect(Utils.cacheLength, 300);
    expect(oldest.isCached, isFalse);
    expect(oldest.isDisposed, isFalse);
    expect(recentlyUsed.isCached, isTrue);
    expect(recentlyUsed.isDisposed, isFalse);

    final recorder = ui.PictureRecorder();
    Utils.drawLayout(Canvas(recorder), oldest, Offset.zero, false, null);
    recorder.endRecording().dispose();
    oldest.release();
    expect(oldest.isDisposed, isTrue);

    newcomer.release();
    recentlyUsed.release();
    Utils.clearCache();
    expect(newcomer.isDisposed, isTrue);
    expect(recentlyUsed.isDisposed, isTrue);
  });

  test('clearing the cache preserves active leases until their last release', () {
    final first = _acquire('two users', stroke: true);
    final second = _acquire('two users', stroke: true);
    expect(first.strokeParagraph, isNotNull);
    Utils.clearCache();
    expect(Utils.cacheLength, 0);
    expect(first.isCached, isFalse);
    expect(first.isDisposed, isFalse);
    first.release();
    expect(second.isDisposed, isFalse);
    second.release();
    expect(first.refCount, 0);
    expect(first.isDisposed, isTrue);
  });

  test('uncached measurement layouts release native paragraphs immediately', () {
    final layout = _acquire('not admitted to a track', cache: false);
    expect(Utils.cacheLength, 0);
    expect(layout.isCached, isFalse);
    expect(layout.isDisposed, isFalse);
    layout.release();
    expect(layout.refCount, 0);
    expect(layout.isDisposed, isTrue);
  });

  test('admitting a previously uncached layout reuses its native paragraph', () {
    final measured = _acquire('measured then admitted', cache: false);
    final paragraph = measured.mainParagraph;
    Utils.cacheLayout(measured);
    final active = _acquire('measured then admitted');
    expect(active, same(measured));
    expect(active.mainParagraph, same(paragraph));
    expect(Utils.cacheLength, 1);
    measured.release();
    active.release();
    Utils.clearCache();
    expect(measured.isDisposed, isTrue);
  });

  test('disposing an item twice releases only its own shared-layout lease', () {
    final first = _acquire('shared item layout');
    final second = _acquire('shared item layout');
    final item = DanmakuItem(
      content: DanmakuContentItem('shared item layout'),
      creationTime: 0,
      width: first.width,
      height: first.height,
      layout: first,
    );
    Utils.clearCache();
    item.dispose();
    item.dispose();
    expect(item.layout, isNull);
    expect(second.refCount, 1);
    expect(second.isDisposed, isFalse);
    second.release();
    expect(first.isDisposed, isTrue);
  });

  test('Unicode and Douyu image emoji preserve mixed content across layout reuse', () async {
    const manifestPath = 'assets/emo/json/douyu.json';
    const imagePath = 'assets/emo/images/douyu/test.png';
    final manifest = Uint8List.fromList(
      utf8.encode(jsonEncode({
        '测试表情': {'local_file': 'test.png', 'img_url': ''},
      })),
    );
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
    );
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    rootBundle.evict(manifestPath);
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final path = utf8.decode(message!.buffer.asUint8List(message.offsetInBytes, message.lengthInBytes));
      final bytes = path == manifestPath ? manifest : path == imagePath ? png : null;
      return bytes == null ? null : ByteData.sublistView(bytes);
    });

    try {
      const unicode = '😂 🥹 ❤️ 👨‍👩‍👧‍👦';
      final plainContent = DanmakuContentItem('$unicode[测试表情]结束', fontFamily: bundledEmojiFontFamily);
      final beforePreload = Utils.acquireLayout(plainContent, 16, 4, true);
      expect(beforePreload.emojiKeys, isEmpty);
      await EmojiManager.instance.preload('douyu');
      expect(EmojiManager.getEmoji('[测试表情]'), isNotNull);
      final content = DanmakuContentItem('$unicode[测试表情]结束', fontFamily: bundledEmojiFontFamily);
      expect(content.mixedContent.map((part) => part.value).join(), content.text);
      expect(content.mixedContent.map((part) => part.type),
          [ContentType.text, ContentType.emoji, ContentType.text]);
      final first = Utils.acquireLayout(content, 16, 4, true);
      final second = Utils.acquireLayout(content, 16, 4, true);
      expect(second, same(first));
      expect(first, isNot(same(beforePreload)));
      expect(first.emojiKeys, ['[测试表情]']);
      expect(first.emojiBoxes, hasLength(1));
      expect(first.width, greaterThan(0));
      expect(first.mainParagraph.debugDisposed, isFalse);
      expect(first.strokeParagraph!.debugDisposed, isFalse);

      final recorder = ui.PictureRecorder();
      Utils.drawLayout(Canvas(recorder), first, Offset.zero, false, null);
      recorder.endRecording().dispose();
      first.release();
      second.release();
      beforePreload.release();
      Utils.clearCache();
      expect(first.isDisposed, isTrue);
    } finally {
      messenger.setMockMessageHandler('flutter/assets', null);
      rootBundle.evict(manifestPath);
      EmojiManager.instance.clearCache();
    }
  });
}
