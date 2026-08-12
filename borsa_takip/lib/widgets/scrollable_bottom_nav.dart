import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class TabNavItem {
  final String key;
  final String label;
  final IconData icon;

  const TabNavItem({required this.key, required this.label, required this.icon});
}

/// `NavigationBar`'ın yerine geçer: o widget sekme sayısı arttıkça
/// (Grafik'ten Temel Analiz'e, artı Ayarlar) her öğeyi ekran genişliğine
/// sıkıştırıp etiketleri iç içe geçirdiğinden, burada her öğeye sabit bir
/// genişlik veriliyor ve toplam genişlik ekrana sığmadığında satır
/// `SingleChildScrollView` ile yatay kaydırılabilir hale geliyor; sığdığı
/// sürece (az sayıda sekme açıkken) eskisi gibi `Expanded` ile eşit
/// aralıklı ve tam genişlikte kalıyor.
class ScrollableBottomNav extends StatelessWidget {
  final List<TabNavItem> items;
  final String selectedKey;
  final ValueChanged<String> onSelect;

  const ScrollableBottomNav({
    super.key,
    required this.items,
    required this.selectedKey,
    required this.onSelect,
  });

  static const _itemWidth = 76.0;
  static const _height = 72.0;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.slate900.withValues(alpha: 0.9),
        border: Border(top: BorderSide(color: AppColors.slate800.withValues(alpha: 0.8))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final needsScroll = _itemWidth * items.length > constraints.maxWidth;
              if (!needsScroll) {
                return Row(
                  children: [
                    for (final item in items)
                      Expanded(child: _buildItem(item)),
                  ],
                );
              }
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final item in items)
                      SizedBox(width: _itemWidth, child: _buildItem(item)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildItem(TabNavItem item) {
    final selected = item.key == selectedKey;
    final color = selected ? AppColors.cyan500 : AppColors.slate400;
    return InkWell(
      onTap: () => onSelect(item.key),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? AppColors.cyan500.withValues(alpha: 0.2) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(item.icon, color: color, size: 22),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              item.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
