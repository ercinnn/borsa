import 'package:flutter/material.dart';

import '../models/root_tabs.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_card.dart';

class SettingsScreen extends StatelessWidget {
  final Set<String> hiddenTabs;
  final void Function(String key, bool hidden) onSetHidden;

  const SettingsScreen({
    super.key,
    required this.hiddenTabs,
    required this.onSetHidden,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sekme Görünürlüğü', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Kullanmadığın sekmeleri kapatarak alt gezinme çubuğunu '
            'sadeleştirebilirsin. Kapalı bir sekmeye bir bildirimden veya '
            'kısayoldan erişirsen o sekme otomatik olarak yeniden açılır.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          for (final tab in toggleableRootTabs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                padding: EdgeInsets.zero,
                child: SwitchListTile(
                  secondary: Icon(tab.icon, color: AppColors.cyan500),
                  title: Text(tab.navLabel, style: const TextStyle(color: AppColors.slate100)),
                  value: !hiddenTabs.contains(tab.key),
                  onChanged: (visible) => onSetHidden(tab.key, !visible),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
