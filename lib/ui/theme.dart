import 'package:flutter/material.dart';

import '../core/models.dart';

@immutable
final class FreedomTokens extends ThemeExtension<FreedomTokens> {
  const FreedomTokens({
    required this.canvas,
    required this.panel,
    required this.panelElevated,
    required this.border,
    required this.glow,
    required this.good,
    required this.warning,
    required this.danger,
    required this.chatBackground,
  });

  final Color canvas;
  final Color panel;
  final Color panelElevated;
  final Color border;
  final Color glow;
  final Color good;
  final Color warning;
  final Color danger;
  final Color chatBackground;

  @override
  FreedomTokens copyWith({
    Color? canvas,
    Color? panel,
    Color? panelElevated,
    Color? border,
    Color? glow,
    Color? good,
    Color? warning,
    Color? danger,
    Color? chatBackground,
  }) => FreedomTokens(
    canvas: canvas ?? this.canvas,
    panel: panel ?? this.panel,
    panelElevated: panelElevated ?? this.panelElevated,
    border: border ?? this.border,
    glow: glow ?? this.glow,
    good: good ?? this.good,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    chatBackground: chatBackground ?? this.chatBackground,
  );

  @override
  FreedomTokens lerp(covariant FreedomTokens? other, double t) {
    if (other == null) return this;
    return FreedomTokens(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      panelElevated: Color.lerp(panelElevated, other.panelElevated, t)!,
      border: Color.lerp(border, other.border, t)!,
      glow: Color.lerp(glow, other.glow, t)!,
      good: Color.lerp(good, other.good, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      chatBackground: Color.lerp(chatBackground, other.chatBackground, t)!,
    );
  }
}

abstract final class FreedomTheme {
  static ThemeData fromProfile(ThemeProfile profile) {
    final definition = switch (profile) {
      ThemeProfile.auroraViolet => _ThemeDefinition(
        brightness: Brightness.dark,
        seed: const Color(0xFF7C4DFF),
        secondary: const Color(0xFF00D9FF),
        canvas: const Color(0xFF050713),
        panel: const Color(0xD90C1021),
        elevated: const Color(0xEE12182C),
        border: const Color(0xFF27365C),
        glow: const Color(0xFF8C5BFF),
      ),
      ThemeProfile.obsidianGlass => _ThemeDefinition(
        brightness: Brightness.dark,
        seed: const Color(0xFF3FA9FF),
        secondary: const Color(0xFF54F4CA),
        canvas: const Color(0xFF04070B),
        panel: const Color(0xDF0A111A),
        elevated: const Color(0xF0121C28),
        border: const Color(0xFF263849),
        glow: const Color(0xFF3FA9FF),
      ),
      ThemeProfile.solarGraphite => _ThemeDefinition(
        brightness: Brightness.dark,
        seed: const Color(0xFFFFA94D),
        secondary: const Color(0xFFFFD166),
        canvas: const Color(0xFF090806),
        panel: const Color(0xE0151411),
        elevated: const Color(0xF0201D17),
        border: const Color(0xFF4B402E),
        glow: const Color(0xFFFFB55E),
      ),
      ThemeProfile.arcticSignal => _ThemeDefinition(
        brightness: Brightness.light,
        seed: const Color(0xFF376DFF),
        secondary: const Color(0xFF006C8F),
        canvas: const Color(0xFFF2F5FA),
        panel: const Color(0xEFFFFFFF),
        elevated: const Color(0xFFF8FAFF),
        border: const Color(0xFFC7D2E8),
        glow: const Color(0xFF376DFF),
      ),
      ThemeProfile.oledVoid => _ThemeDefinition(
        brightness: Brightness.dark,
        seed: const Color(0xFF9A6CFF),
        secondary: const Color(0xFF00E2B8),
        canvas: Colors.black,
        panel: const Color(0xEE030306),
        elevated: const Color(0xFF090910),
        border: const Color(0xFF242438),
        glow: const Color(0xFF9A6CFF),
      ),
      ThemeProfile.highContrast => _ThemeDefinition(
        brightness: Brightness.dark,
        seed: const Color(0xFFFFFF00),
        secondary: const Color(0xFF00FFFF),
        canvas: Colors.black,
        panel: const Color(0xFF050505),
        elevated: const Color(0xFF101010),
        border: Colors.white,
        glow: const Color(0xFFFFFF00),
      ),
    };
    final colorScheme = ColorScheme.fromSeed(
      seedColor: definition.seed,
      brightness: definition.brightness,
      primary: definition.seed,
      secondary: definition.secondary,
      surface: definition.panel,
    );
    final textTheme = ThemeData(brightness: definition.brightness).textTheme
        .apply(
          bodyColor: colorScheme.onSurface,
          displayColor: colorScheme.onSurface,
          fontFamily: 'Inter',
        );
    return ThemeData(
      useMaterial3: true,
      brightness: definition.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: definition.canvas,
      canvasColor: definition.canvas,
      textTheme: textTheme,
      fontFamily: 'Inter',
      visualDensity: VisualDensity.standard,
      // InkSparkle is costly on software-rendered desktop surfaces and can
      // delay presentation of pointer/text invalidations. Ripple is cheaper
      // and reliable across GTK, Windows, and software rendering.
      splashFactory: InkRipple.splashFactory,
      extensions: <ThemeExtension<dynamic>>[
        FreedomTokens(
          canvas: definition.canvas,
          panel: definition.panel,
          panelElevated: definition.elevated,
          border: definition.border,
          glow: definition.glow,
          good: const Color(0xFF53E3B5),
          warning: const Color(0xFFFFC857),
          danger: const Color(0xFFFF5E7C),
          chatBackground: Color.alphaBlend(
            colorScheme.primary.withValues(alpha: 0.025),
            definition.panel,
          ),
        ),
      ],
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: definition.elevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: definition.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: definition.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: definition.glow, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          side: BorderSide(color: definition.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: definition.elevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: BorderSide(color: definition.border),
        ),
      ),
      dividerColor: definition.border,
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          definition.glow.withValues(alpha: 0.45),
        ),
        radius: const Radius.circular(12),
        thickness: const WidgetStatePropertyAll(6),
      ),
    );
  }
}

final class _ThemeDefinition {
  const _ThemeDefinition({
    required this.brightness,
    required this.seed,
    required this.secondary,
    required this.canvas,
    required this.panel,
    required this.elevated,
    required this.border,
    required this.glow,
  });
  final Brightness brightness;
  final Color seed;
  final Color secondary;
  final Color canvas;
  final Color panel;
  final Color elevated;
  final Color border;
  final Color glow;
}

FreedomTokens freedomTokens(BuildContext context) =>
    Theme.of(context).extension<FreedomTokens>()!;
