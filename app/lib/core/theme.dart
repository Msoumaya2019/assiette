import 'package:flutter/material.dart';

/// Palette et themes de l'application.
///
/// Parti pris : une interface chaleureuse, proche de la cuisine, qui ne
/// ressemble pas a un dossier medical. Les surfaces sont legerement teintees
/// plutot que gris neutre, les coins sont arrondis, et une couleur dediee
/// signale partout les glucides — l'information principale.
class AppColors {
  const AppColors._();

  /// Terracotta : couleur d'action principale.
  static const Color terracotta = Color(0xFFE0603A);

  /// Ambre : couleur reservee aux glucides. Elle n'est utilisee nulle part
  /// ailleurs, pour que l'oeil la reconnaisse immediatement.
  static const Color carbAmber = Color(0xFFE89B2E);

  /// Vert profond : proteines.
  static const Color proteinGreen = Color(0xFF3F8F6B);

  /// Bleu petrole : lipides.
  static const Color fatBlue = Color(0xFF4A7C94);

  /// Violet doux : fibres.
  static const Color fiberViolet = Color(0xFF8A6FA8);

  static const Color lightBackground = Color(0xFFFBF7F3);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFF3EBE3);
  static const Color lightOutline = Color(0xFFE3D8CC);
  static const Color lightText = Color(0xFF2A2118);
  static const Color lightTextMuted = Color(0xFF6F6355);

  static const Color darkBackground = Color(0xFF16130F);
  static const Color darkSurface = Color(0xFF211C16);
  static const Color darkSurfaceVariant = Color(0xFF2C261E);
  static const Color darkOutline = Color(0xFF3D352A);
  static const Color darkText = Color(0xFFF3EBE1);
  static const Color darkTextMuted = Color(0xFFB0A493);

  /// Vert de succes, lisible sur les deux themes.
  static const Color success = Color(0xFF2E8B57);

  /// Ambre d'avertissement, distinct de la couleur des glucides.
  static const Color warning = Color(0xFFD98324);

  /// Rouge d'erreur.
  static const Color danger = Color(0xFFC0392B);
}

/// Couleurs propres a l'application, exposees via le theme pour rester
/// accessibles depuis n'importe quel widget sans dependance a l'etat.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.carb,
    required this.protein,
    required this.fat,
    required this.fiber,
    required this.mutedText,
    required this.cardBorder,
    required this.estimateBackground,
  });

  /// Couleur de la donnee principale : les glucides.
  final Color carb;
  final Color protein;
  final Color fat;
  final Color fiber;

  /// Texte secondaire.
  final Color mutedText;

  /// Bordure fine des cartes.
  final Color cardBorder;

  /// Fond des encarts signalant une estimation.
  final Color estimateBackground;

  @override
  AppPalette copyWith({
    Color? carb,
    Color? protein,
    Color? fat,
    Color? fiber,
    Color? mutedText,
    Color? cardBorder,
    Color? estimateBackground,
  }) {
    return AppPalette(
      carb: carb ?? this.carb,
      protein: protein ?? this.protein,
      fat: fat ?? this.fat,
      fiber: fiber ?? this.fiber,
      mutedText: mutedText ?? this.mutedText,
      cardBorder: cardBorder ?? this.cardBorder,
      estimateBackground: estimateBackground ?? this.estimateBackground,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      carb: Color.lerp(carb, other.carb, t)!,
      protein: Color.lerp(protein, other.protein, t)!,
      fat: Color.lerp(fat, other.fat, t)!,
      fiber: Color.lerp(fiber, other.fiber, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      estimateBackground: Color.lerp(estimateBackground, other.estimateBackground, t)!,
    );
  }
}

/// Espacements et rayons, centralises pour garder un rythme visuel coherent.
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  static const double radiusSm = 12;
  static const double radiusMd = 18;
  static const double radiusLg = 24;
  static const double radiusXl = 32;
}

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.terracotta,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFFFE3D8),
      onPrimaryContainer: Color(0xFF5A1F0C),
      secondary: AppColors.proteinGreen,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFD9EFE4),
      onSecondaryContainer: Color(0xFF10331F),
      tertiary: AppColors.fatBlue,
      onTertiary: Colors.white,
      error: AppColors.danger,
      onError: Colors.white,
      surface: AppColors.lightSurface,
      onSurface: AppColors.lightText,
      surfaceContainerHighest: AppColors.lightSurfaceVariant,
      onSurfaceVariant: AppColors.lightTextMuted,
      outline: AppColors.lightOutline,
      outlineVariant: AppColors.lightOutline,
      shadow: Color(0x1A2A2118),
      scrim: Color(0x802A2118),
      inverseSurface: AppColors.darkSurface,
      onInverseSurface: AppColors.darkText,
      inversePrimary: Color(0xFFFFB59B),
    );

    return _base(scheme, AppColors.lightBackground).copyWith(
      extensions: const [
        AppPalette(
          carb: AppColors.carbAmber,
          protein: AppColors.proteinGreen,
          fat: AppColors.fatBlue,
          fiber: AppColors.fiberViolet,
          mutedText: AppColors.lightTextMuted,
          cardBorder: AppColors.lightOutline,
          estimateBackground: Color(0xFFFFF3E0),
        ),
      ],
    );
  }

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFFF8A62),
      onPrimary: Color(0xFF4A1A08),
      primaryContainer: Color(0xFF6B2A12),
      onPrimaryContainer: Color(0xFFFFDBCE),
      secondary: Color(0xFF6FBF95),
      onSecondary: Color(0xFF0C2B1B),
      secondaryContainer: Color(0xFF1E4430),
      onSecondaryContainer: Color(0xFFCDEBD9),
      tertiary: Color(0xFF7FB3CB),
      onTertiary: Color(0xFF10262F),
      error: Color(0xFFFF8A7A),
      onError: Color(0xFF3A0A04),
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkText,
      surfaceContainerHighest: AppColors.darkSurfaceVariant,
      onSurfaceVariant: AppColors.darkTextMuted,
      outline: AppColors.darkOutline,
      outlineVariant: AppColors.darkOutline,
      shadow: Color(0x66000000),
      scrim: Color(0xCC000000),
      inverseSurface: AppColors.lightSurface,
      onInverseSurface: AppColors.lightText,
      inversePrimary: AppColors.terracotta,
    );

    return _base(scheme, AppColors.darkBackground).copyWith(
      extensions: const [
        AppPalette(
          carb: Color(0xFFFFB65C),
          protein: Color(0xFF6FBF95),
          fat: Color(0xFF7FB3CB),
          fiber: Color(0xFFB79BD4),
          mutedText: AppColors.darkTextMuted,
          cardBorder: AppColors.darkOutline,
          estimateBackground: Color(0xFF3A2C18),
        ),
      ],
    );
  }

  static ThemeData _base(ColorScheme scheme, Color background) {
    final isDark = scheme.brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,

      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),

      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: BorderSide(color: isDark ? AppColors.darkOutline : AppColors.lightOutline),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
          side: BorderSide(color: scheme.outline),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
      ),

      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide(color: scheme.outline),
        backgroundColor: scheme.surface,
        selectedColor: scheme.primaryContainer,
        labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
      ),

      dividerTheme: DividerThemeData(
        color: isDark ? AppColors.darkOutline : AppColors.lightOutline,
        thickness: 1,
        space: 1,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppColors.darkSurfaceVariant : const Color(0xFF3A322A),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
        insetPadding: const EdgeInsets.all(AppSpacing.md),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusXl)),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),

      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
        iconColor: scheme.onSurfaceVariant,
      ),
    );
  }
}

/// Raccourci d'acces a la palette depuis n'importe quel widget.
extension AppPaletteAccess on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;

  ColorScheme get colors => Theme.of(this).colorScheme;

  TextTheme get texts => Theme.of(this).textTheme;
}
