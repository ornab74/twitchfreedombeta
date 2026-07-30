import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_freedom_ultra/core/models.dart';
import 'package:twitch_freedom_ultra/ui/theme.dart';

void main() {
  test('all six theme profiles produce token sets', () {
    for (final profile in ThemeProfile.values) {
      final theme = FreedomTheme.fromProfile(profile);
      expect(theme.extension<FreedomTokens>(), isNotNull);
      expect(theme.useMaterial3, isTrue);
    }
  });
}
