import 'package:flutter/material.dart';

import '../theme/app_radius.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'app_layout.dart';

class AppFeatureAction {
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final Color? iconColor;
  final Color? iconBackground;
  final VoidCallback? onTap;

  const AppFeatureAction({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    this.iconColor,
    this.iconBackground,
    required this.onTap,
  });
}

class AppFeatureSection extends StatelessWidget {
  final String title;
  final List<AppFeatureAction> actions;

  const AppFeatureSection({
    super.key,
    this.title = 'Chức năng',
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: AppTextStyles.bodyL.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${actions.length} công cụ',
              style: AppTextStyles.bodyS.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 18 / 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AppFeatureGrid(actions: actions),
      ],
    );
  }
}

class AppFeatureGrid extends StatelessWidget {
  final List<AppFeatureAction> actions;

  const AppFeatureGrid({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = MediaQuery.sizeOf(context).width;
        // Operations Figma frames use fixed 3-column desktop cards, a fixed
        // 2-column medium canvas (even for a single-card row), and one column
        // only below the compact breakpoint.
        final crossAxisCount = viewportWidth >= AppLayoutTokens.desktopBreakpoint
            ? 3
            : viewportWidth >= AppLayoutTokens.tabletBreakpoint
            ? (actions.length >= 3 ? 3 : 2)
            : 1;
        final spacing = viewportWidth >= AppLayoutTokens.desktopBreakpoint
            ? 16.0
            : viewportWidth >= AppLayoutTokens.tabletBreakpoint
            ? (actions.length >= 3 ? 16.0 : 12.0)
            : 12.0;
        const tileHeight = 96.0;

        return GridView.builder(
          itemCount: actions.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            mainAxisExtent: tileHeight,
          ),
          itemBuilder: (context, index) =>
              AppFeatureTile(action: actions[index]),
        );
      },
    );
  }
}

class AppFeatureTile extends StatelessWidget {
  final AppFeatureAction action;

  const AppFeatureTile({super.key, required this.action});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: action.onTap != null,
      label: 'Chức năng ${action.title}',
      hint: action.description,
      child: Material(
        color:
            Theme.of(context).cardTheme.color ??
            Theme.of(context).colorScheme.surface,
        borderRadius: AppRadius.allLg,
        child: InkWell(
          onTap: action.onTap,
          borderRadius: AppRadius.allLg,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: AppRadius.allLg,
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: action.iconBackground ?? AppColors.infoSurface,
                    borderRadius: AppRadius.allMd,
                  ),
                  child: Icon(
                    action.icon,
                    color: action.iconColor ?? action.color,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        action.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelM.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        action.description,
                        maxLines: 2,
                        overflow: TextOverflow.clip,
                        style: AppTextStyles.bodyS.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 18 / 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.primary500,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
