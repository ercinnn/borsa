import 'package:flutter/material.dart';

/// CLAUDE.md "UI/UX Tasarım Kuralları" madde 4'teki basılma-hissi
/// animasyonu. ChoiceChip/ElevatedButton gibi Material bileşenleri kendi
/// ink/hover geri bildirimini zaten sağladığından onları bu widget'la
/// sarmaya gerek yok; bunu öne çıkan tek bir CTA'yı vurgulamak istediğinde
/// ya da ileride Material olmayan özel bir tıklanabilir yüzey eklendiğinde
/// kullan.
class PressableScale extends StatefulWidget {
  final Widget child;

  const PressableScale({super.key, required this.child});

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
