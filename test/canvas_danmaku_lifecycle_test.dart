import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/pkg/canvas_danmaku/danmaku_controller.dart';
import 'package:pure_live/pkg/canvas_danmaku/danmaku_screen.dart';
import 'package:pure_live/pkg/canvas_danmaku/models/danmaku_content_item.dart';
import 'package:pure_live/pkg/canvas_danmaku/models/danmaku_item.dart';
import 'package:pure_live/pkg/canvas_danmaku/models/danmaku_option.dart';
import 'package:pure_live/pkg/canvas_danmaku/scroll_danmaku_painter.dart';
import 'package:pure_live/pkg/canvas_danmaku/utils/utils.dart';

Widget _screen(
  DanmakuController controller, {
  int duration = 1,
  bool massiveMode = false,
  double height = 480,
}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: SizedBox(
        width: 800,
        height: height,
        child: DanmakuScreen(
          controller: controller,
          option: DanmakuOption(
            duration: duration,
            showStroke: false,
            massiveMode: massiveMode,
          ),
        ),
      ),
    ),
  );
}

List<DanmakuItem> _visibleItems(WidgetTester tester) {
  final paints = tester.widgetList<CustomPaint>(
    find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is ScrollDanmakuPainter,
    ),
  );
  if (paints.isEmpty) return <DanmakuItem>[];
  final painter = paints.single.painter! as ScrollDanmakuPainter;
  return List<DanmakuItem>.of(painter.scrollDanmakuItems);
}

void main() {
  setUp(Utils.clearCache);
  tearDown(Utils.clearCache);

  testWidgets('long playback retains only unexpired messages and bounded layouts', (tester) async {
    final controller = DanmakuController();
    await tester.pumpWidget(_screen(controller, massiveMode: true));
    final layouts = <DanmakuLayout>[];

    // Cross the layout-cache capacity repeatedly without real-time waiting.
    for (var batch = 0; batch < 120; batch++) {
      for (var message = 0; message < 10; message++) {
        controller.addDanmaku(DanmakuContentItem('batch $batch message $message 😂'));
      }
      await tester.pump();
      final active = _visibleItems(tester);
      expect(active, hasLength(10), reason: 'old messages survived batch $batch');
      final batchLayouts = active.map((item) => item.layout!).toList();
      layouts.addAll(batchLayouts);

      await tester.pump(const Duration(milliseconds: 1100));
      expect(_visibleItems(tester), isEmpty);
      expect(batchLayouts.every((layout) => layout.refCount == 0), isTrue);
      expect(Utils.cacheLength, lessThanOrEqualTo(300));
    }

    Utils.clearCache();
    expect(layouts.every((layout) => layout.isDisposed), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
    controller.onClose();
  });

  testWidgets('pause and repeated resume keep one frame driver and preserve lifetime', (tester) async {
    final controller = DanmakuController();
    await tester.pumpWidget(_screen(controller, duration: 4));
    controller.addDanmaku(DanmakuContentItem('pause and resume'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(_visibleItems(tester), hasLength(1));

    for (var cycle = 0; cycle < 30; cycle++) {
      controller.pause();
      controller.resume();
      controller.resume();
      expect(tester.binding.transientCallbackCount, lessThanOrEqualTo(1));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(_visibleItems(tester), hasLength(1));

    controller.pause();
    final pausedPosition = _visibleItems(tester).single.xPosition;
    await tester.pump(const Duration(seconds: 10));
    expect(_visibleItems(tester), hasLength(1));
    expect(_visibleItems(tester).single.xPosition, pausedPosition);
    expect(tester.binding.transientCallbackCount, 0);

    controller.resume();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(_visibleItems(tester), hasLength(1));
    await tester.pump(const Duration(milliseconds: 2500));
    expect(_visibleItems(tester), isEmpty);
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
    controller.onClose();
  });

  testWidgets('clear releases shared active layouts even while paused', (tester) async {
    final controller = DanmakuController();
    await tester.pumpWidget(_screen(controller, duration: 10));
    controller.addDanmaku(DanmakuContentItem('same message'));
    controller.addDanmaku(DanmakuContentItem('same message'));
    await tester.pump();

    final items = _visibleItems(tester);
    expect(items, hasLength(2));
    final layout = items.first.layout!;
    expect(items.last.layout, same(layout));
    expect(layout.refCount, 2);
    Utils.clearCache();
    expect(layout.isDisposed, isFalse);

    controller.pause();
    controller.clear();
    await tester.pump();
    expect(_visibleItems(tester), isEmpty);
    expect(layout.refCount, 0);
    expect(layout.isDisposed, isTrue);
    expect(tester.binding.transientCallbackCount, 0);

    controller.resume();
    controller.addDanmaku(DanmakuContentItem('message after clear'));
    await tester.pump();
    expect(_visibleItems(tester), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
    controller.onClose();
  });

  testWidgets('unmount releases active native layouts and stops scheduling frames', (tester) async {
    final controller = DanmakuController();
    await tester.pumpWidget(_screen(controller, duration: 10));
    controller.addDanmaku(DanmakuContentItem('active at unmount ❤️'));
    await tester.pump();
    final layout = _visibleItems(tester).single.layout!;
    Utils.clearCache();
    expect(layout.refCount, 1);
    expect(layout.isDisposed, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(layout.refCount, 0);
    expect(layout.isDisposed, isTrue);
    expect(tester.binding.transientCallbackCount, 0);
    controller.addDanmaku(DanmakuContentItem('after unmount'));
    controller.clear();
    controller.pause();
    controller.resume();
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
    controller.onClose();
  });

  testWidgets('messages rejected by a full track do not pollute the layout cache', (tester) async {
    final controller = DanmakuController();
    await tester.pumpWidget(_screen(controller, duration: 10, height: 24));
    controller.addDanmaku(DanmakuContentItem('accepted'));
    await tester.pump();
    expect(_visibleItems(tester), hasLength(1));
    final cacheBefore = Utils.cacheLength;

    for (var message = 0; message < 500; message++) {
      controller.addDanmaku(DanmakuContentItem('rejected message $message'));
    }
    await tester.pump();
    expect(_visibleItems(tester), hasLength(1));
    expect(Utils.cacheLength, cacheBefore);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
    controller.onClose();
  });
}
