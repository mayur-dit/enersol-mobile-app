import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Pill-style tab bar used inside the shell.
///
/// Material's default underline indicator reads too heavy against the glass
/// surfaces, so the selected tab takes the brand gradient instead.
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.controller,
    required this.labels,
  });

  final TabController controller;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: isDark ? AppColors.darkHairline : AppColors.lightHairline,
        ),
      ),
      child: TabBar(
        controller: controller,
        indicator: BoxDecoration(
          gradient: AppColors.brand,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor:
            isDark ? AppColors.darkText2 : AppColors.lightText2,
        labelStyle:
            const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        tabs: labels.map((l) => Tab(text: l)).toList(),
      ),
    );
  }
}
