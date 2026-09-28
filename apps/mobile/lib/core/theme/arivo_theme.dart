import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.g.dart';

/// Semantic surface palette. Paper = the clean white app surface used everywhere. Ink = dark surfaces (photo overlays, snackbars).
@immutable
class ArivoPalette extends ThemeExtension<ArivoPalette> {
  const ArivoPalette({
    required this.isInk,
    required this.surface,
    required this.raised,
    required this.sunken,
    required this.line,
    required this.text,
    required this.muted,
    required this.voltText,
    required this.signalText,
    required this.lanternText,
    required this.emberText,
  });

  final bool isInk;
  final Color surface, raised, sunken, line, text, muted, voltText, signalText, lanternText, emberText;

  /// The brand blue (primary buttons, selection, active tab).
  Color get volt => ArivoColors.accentVolt;
  Color get onVolt => ArivoColors.textOnVolt;
  Color get signal => ArivoColors.accentSignal;
  Color get lantern => ArivoColors.accentLantern;
  Color get ember => ArivoColors.accentEmber;

  /// Pale brand tint for selected cards, icon wells and info banners.
  Color get voltSoft => const Color(0xFFEAF1FF);

  static const paper = ArivoPalette(
    isInk: false,
    surface: ArivoColors.paper100,
    raised: ArivoColors.paper50,
    sunken: ArivoColors.paper200,
    line: ArivoColors.paper300,
    text: ArivoColors.textOnPaper,
    muted: ArivoColors.textOnPaperMuted,
    voltText: ArivoColors.accentOnPaperVolt,
    signalText: ArivoColors.accentOnPaperSignal,
    lanternText: ArivoColors.accentOnPaperLantern,
    emberText: ArivoColors.accentOnPaperEmber,
  );

  static const ink = ArivoPalette(
    isInk: true,
    surface: ArivoColors.ink900,
    raised: ArivoColors.ink800,
    sunken: ArivoColors.ink950,
    line: Color(0xFF2B3558),
    text: ArivoColors.textOnInk,
    muted: ArivoColors.textOnInkMuted,
    voltText: ArivoColors.accentSignal,
    signalText: ArivoColors.accentSignal,
    lanternText: ArivoColors.accentLantern,
    emberText: ArivoColors.accentEmber,
  );

  Color route(int day) => ArivoColors.route[day % ArivoColors.route.length];

  Color crew(int i) => ArivoColors.crew[i % ArivoColors.crew.length];

  Color provenance(String kind) => switch (kind) { 'live' => signalText, 'you' => ArivoColors.provenanceYou, _ => lanternText };

  @override
  ArivoPalette copyWith() => this;

  @override
  ArivoPalette lerp(ArivoPalette? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension ArivoContext on BuildContext {
  ArivoPalette get palette => Theme.of(this).extension<ArivoPalette>()!;
  ArivoText get type => ArivoText.of(Theme.of(this).extension<ArivoPalette>()!);
  bool get reduceMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;
}

/// Type roles from the design system. One family (Plus Jakarta Sans); tabular figures for comparable numbers.
class ArivoText {
  ArivoText._(this.p);
  final ArivoPalette p;
  static final Map<bool, ArivoText> _cache = {};
  static ArivoText of(ArivoPalette p) => _cache.putIfAbsent(p.isInk, () => ArivoText._(p));

  TextStyle _ui(double size, double height, FontWeight w, [double tracking = 0]) =>
      GoogleFonts.plusJakartaSans(fontSize: size, height: height / size, fontWeight: w, letterSpacing: tracking * size, color: p.text);
  // Prices and times: same family, tabular figures so columns line up.
  TextStyle _num(double size, double height, FontWeight w, [double tracking = 0]) =>
      _ui(size, height, w, tracking).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  TextStyle get displayXL => _ui(34, 40, FontWeight.w700, -0.02);
  TextStyle get displayL => _ui(28, 34, FontWeight.w700, -0.015);
  TextStyle get displayM => _ui(24, 30, FontWeight.w700, -0.01);
  TextStyle get titleL => _ui(20, 26, FontWeight.w700, -0.01);
  TextStyle get titleM => _ui(17, 22, FontWeight.w600, -0.005);
  TextStyle get bodyL => _ui(16, 24, FontWeight.w400);
  TextStyle get bodyM => _ui(14, 20, FontWeight.w400);
  TextStyle get label => _ui(13, 16, FontWeight.w600);
  TextStyle get caption => _ui(12, 16, FontWeight.w500).copyWith(color: p.muted);
  TextStyle get monoL => _num(22, 28, FontWeight.w700, -0.01);
  TextStyle get monoM => _num(15, 20, FontWeight.w600);
  TextStyle get monoS => _num(12, 16, FontWeight.w600, 0.02);
}

abstract final class ArivoTheme {
  static ThemeData paper() => _paper;

  /// Screens that used to switch to the dark "ink" theme (Live, onboarding) now share the one light look.
  static ThemeData ink() => _paper;
  static final ThemeData _paper = _build(ArivoPalette.paper, Brightness.light);

  static ThemeData _build(ArivoPalette p, Brightness b) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: b,
      scaffoldBackgroundColor: p.surface,
      colorScheme: ColorScheme.fromSeed(
        seedColor: ArivoColors.accentVolt,
        brightness: b,
        surface: p.surface,
        surfaceContainerLowest: p.raised,
        surfaceContainerLow: p.sunken,
        surfaceContainer: p.sunken,
        surfaceContainerHigh: p.sunken,
        primary: ArivoColors.accentVolt,
        onPrimary: ArivoColors.textOnVolt,
        secondary: p.signalText,
        error: p.emberText,
      ),
      extensions: [p],
      splashFactory: InkSparkle.splashFactory,
    );
    final t = ArivoText.of(p);
    return base.copyWith(
      textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(bodyColor: p.text, displayColor: p.text),
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface,
        foregroundColor: p.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: t.titleM.copyWith(fontWeight: FontWeight.w700),
      ),
      dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.raised,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: p.line,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(ArivoRadius.l))),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.raised,
        hintStyle: t.bodyM.copyWith(color: p.muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: ArivoSpace.s4, vertical: ArivoSpace.s4),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(ArivoRadius.s), borderSide: BorderSide(color: p.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(ArivoRadius.s), borderSide: BorderSide(color: p.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(ArivoRadius.s), borderSide: BorderSide(color: p.volt, width: 1.5)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.raised,
        selectedColor: p.volt,
        checkmarkColor: p.onVolt,
        labelStyle: t.label,
        secondaryLabelStyle: t.label.copyWith(color: p.onVolt),
        side: BorderSide(color: p.line),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: ArivoSpace.s2, vertical: ArivoSpace.s1),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.raised,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? p.volt : p.muted, size: 24)),
        labelTextStyle: WidgetStateProperty.resolveWith(
            (s) => t.caption.copyWith(color: s.contains(WidgetState.selected) ? p.volt : p.muted, fontWeight: FontWeight.w600, fontSize: 11)),
        height: 64,
      ),
      cardTheme: CardThemeData(
        color: p.raised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ArivoRadius.m), side: BorderSide(color: p.line)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.volt : p.line),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.volt : Colors.transparent),
        side: BorderSide(color: p.line, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      sliderTheme: SliderThemeData(activeTrackColor: p.volt, thumbColor: p.volt, inactiveTrackColor: p.line, overlayColor: p.volt.withValues(alpha: 0.12)),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.volt, linearTrackColor: p.sunken),
      tabBarTheme: TabBarThemeData(
        labelColor: p.volt,
        unselectedLabelColor: p.muted,
        indicatorColor: p.volt,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: t.label,
        unselectedLabelStyle: t.label,
        dividerColor: p.line,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.volt : p.raised),
          foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onVolt : p.text),
          iconColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onVolt : p.text),
          side: WidgetStatePropertyAll(BorderSide(color: p.line)),
          textStyle: WidgetStatePropertyAll(t.label),
        ),
      ),
      datePickerTheme: DatePickerThemeData(backgroundColor: p.raised, surfaceTintColor: Colors.transparent),
      dialogTheme: DialogThemeData(backgroundColor: p.raised, surfaceTintColor: Colors.transparent),
      floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: p.volt, foregroundColor: p.onVolt),
      listTileTheme: ListTileThemeData(iconColor: p.muted, titleTextStyle: t.bodyL.copyWith(fontWeight: FontWeight.w500), subtitleTextStyle: t.caption),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ArivoColors.ink900,
        contentTextStyle: ArivoText.of(ArivoPalette.ink).bodyM,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ArivoRadius.s)),
      ),
    );
  }
}
