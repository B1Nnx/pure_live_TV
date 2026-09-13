import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/style/bundled_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled emoji fallback points to a packaged font asset', () async {
    expect(
      bundledEmojiFontFallback,
      const <String>[bundledEmojiFontFamily],
    );

    final font = await rootBundle.load(
      'assets/fonts/emoji/NotoColorEmoji.ttf',
    );

    expect(font.lengthInBytes, greaterThan(1024 * 1024));
  });
}
