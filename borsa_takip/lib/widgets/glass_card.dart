import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// CLAUDE.md UI/UX madde 1'deki "glassmorphism" kart: yarı saydam koyu zemin
/// + arkasında blur + ince border. Bir `Card` gibi davranır ama `Card`'ın
/// `ThemeData.cardTheme`'i bunu ifade edemez, çünkü `BackdropFilter`
/// widget ağacında gerçek bir katman gerektirir — bu yüzden ayrı bir widget.
/// `glow: true` iken madde 2'deki yumuşak renkli "tech glow" gölgesi eklenir
/// (öne çıkan kartlar için, ör. grafik kartı).
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool glow;
  final bool glowBullish;
  final BorderRadius borderRadius;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.glow = false,
    this.glowBullish = true,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: glow ? AppColors.glow(bullish: glowBullish) : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.glassFill,
              borderRadius: borderRadius,
              border: AppColors.glassBorder,
            ),
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}
