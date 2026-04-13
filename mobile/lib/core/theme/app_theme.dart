import 'package:flutter/material.dart';

class AppTheme {
  // ── Brand palette ─────────────────────────────────────────────────────────
  // Emerald green — professional, trustworthy, money-adjacent
  static const Color primary      = Color(0xFF059669); // Emerald-600
  static const Color primaryDark  = Color(0xFF047857); // Emerald-700
  static const Color primaryLight = Color(0xFF34D399); // Emerald-400
  static const Color primaryBg    = Color(0xFFECFDF5); // Emerald-50

  // Neutrals — warm slate (not cold blue-grey)
  static const Color ink          = Color(0xFF111827); // Gray-900
  static const Color inkMuted     = Color(0xFF6B7280); // Gray-500
  static const Color surface      = Color(0xFFF9FAFB); // Gray-50
  static const Color card         = Color(0xFFFFFFFF);
  static const Color border       = Color(0xFFE5E7EB); // Gray-200

  // Semantic
  static const Color success      = Color(0xFF059669);
  static const Color warning      = Color(0xFFD97706); // Amber-600
  static const Color error        = Color(0xFFDC2626); // Red-600

  // ── Gradients ─────────────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryDark],
    begin:  Alignment.topLeft,
    end:    Alignment.bottomRight,
  );

  // ── Shadows ───────────────────────────────────────────────────────────────
  static final List<BoxShadow> cardShadow = [
    BoxShadow(
      color:      primary.withOpacity(0.25),
      blurRadius: 24,
      offset:     const Offset(0, 8),
    ),
  ];

  static final List<BoxShadow> subtleShadow = [
    BoxShadow(
      color:      Colors.black.withOpacity(0.06),
      blurRadius: 12,
      offset:     const Offset(0, 4),
    ),
  ];

  // ── Typography ────────────────────────────────────────────────────────────
  static const TextStyle display = TextStyle(
    fontSize:      32,
    fontWeight:    FontWeight.w800,
    color:         ink,
    letterSpacing: -1.0,
    height:        1.1,
  );

  static const TextStyle heading = TextStyle(
    fontSize:   22,
    fontWeight: FontWeight.w700,
    color:      ink,
    height:     1.2,
  );

  static const TextStyle subheading = TextStyle(
    fontSize:   16,
    fontWeight: FontWeight.w600,
    color:      ink,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    color:    inkMuted,
    height:   1.5,
  );

  static const TextStyle caption = TextStyle(
    fontSize:      12,
    color:         inkMuted,
    letterSpacing: 0.2,
  );

  static const TextStyle cashbackLabel = TextStyle(
    fontSize:   20,
    fontWeight: FontWeight.w800,
    color:      primary,
  );

  static const TextStyle moneyLarge = TextStyle(
    fontSize:      42,
    fontWeight:    FontWeight.w800,
    color:         Colors.white,
    letterSpacing: -1.5,
    height:        1.0,
  );

  // ── Theme ─────────────────────────────────────────────────────────────────
  static ThemeData get light => ThemeData(
        useMaterial3:            true,
        colorSchemeSeed:         primary,
        scaffoldBackgroundColor: surface,

        // Cards
        cardTheme: CardThemeData(
          color:     card,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side:         const BorderSide(color: border),
          ),
          margin: EdgeInsets.zero,
        ),

        // AppBar
        appBarTheme: const AppBarTheme(
          backgroundColor: card,
          foregroundColor: ink,
          elevation:       0,
          centerTitle:     false,
          titleTextStyle:  TextStyle(
            color:      ink,
            fontSize:   18,
            fontWeight: FontWeight.w700,
          ),
        ),

        // Navigation bar (bottom tabs)
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor:   card,
          indicatorColor:    primaryBg,
          labelTextStyle:    WidgetStateProperty.all(
            caption.copyWith(fontWeight: FontWeight.w600),
          ),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: primary, size: 24);
            }
            return const IconThemeData(color: inkMuted, size: 24);
          }),
          elevation: 0,
        ),

        // Buttons
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            minimumSize:     const Size(double.infinity, 52),
            elevation:       0,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),

        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primary,
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),

        // Inputs
        inputDecorationTheme: InputDecorationTheme(
          filled:      true,
          fillColor:   const Color(0xFFF3F4F6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:   BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:   const BorderSide(color: primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:   const BorderSide(color: error, width: 1),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          hintStyle: const TextStyle(color: inkMuted, fontSize: 14),
        ),

        // Floating action button
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation:       2,
          shape: StadiumBorder(),
        ),

        // Chips
        chipTheme: ChipThemeData(
          backgroundColor: primaryBg,
          labelStyle:      const TextStyle(color: primary, fontWeight: FontWeight.w600, fontSize: 12),
          side:            BorderSide.none,
          shape:           const StadiumBorder(),
        ),

        // Divider
        dividerTheme: const DividerThemeData(
          color:     border,
          thickness: 1,
          space:     1,
        ),
      );
}
