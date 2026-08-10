import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'pressable_scale.dart';

/// CLAUDE.md UI/UX madde 2 + 4: ana CTA'lar için neon zümrüt→camgöbeği
/// gradyanlı buton. Hover'da border'ı `cyan-500/50` yapan `MouseRegion` +
/// `AnimatedContainer(200ms)`, basılma hissi için `PressableScale` sarmalar
/// — `ElevatedButton`'ın kendi arka planı düz renk olduğundan gradyan
/// arka plan için Material bileşeni yerine bu özel widget kullanılıyor.
class GradientButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget? icon;
  final String label;
  final bool loading;
  final bool expand;

  const GradientButton({
    super.key,
    required this.onPressed,
    this.icon,
    required this.label,
    this.loading = false,
    this.expand = false,
  });

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null || widget.loading;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: PressableScale(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            gradient: AppColors.bullishGradient,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovering && !disabled
                  ? AppColors.cyan500.withValues(alpha: 0.5)
                  : Colors.transparent,
              width: 1.5,
            ),
            boxShadow: disabled ? null : AppColors.glow(),
          ),
          child: Opacity(
            opacity: disabled ? 0.5 : 1,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onPressed,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.loading)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.slate950,
                          ),
                        )
                      else if (widget.icon != null)
                        IconTheme(
                          data: const IconThemeData(color: AppColors.slate950, size: 18),
                          child: widget.icon!,
                        ),
                      const SizedBox(width: 8),
                      Text(
                        widget.label,
                        style: const TextStyle(
                          color: AppColors.slate950,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
