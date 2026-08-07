import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

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
                color: AppColors.textPrimaryOf(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${actions.length} công cụ',
              style: AppTextStyles.bodyS.copyWith(
                color: AppColors.textMutedOf(context),
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
        // Figma node 1405:15958 keeps the five Sales cards in a 3+2 grid at
        // Web 1024. Two-card and one-card groups use the medium two-column
        // geometry instead; wide always has three columns.
        final crossAxisCount =
            viewportWidth >= AppLayoutTokens.desktopBreakpoint
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
    final actionColor = AppColors.adaptOf(context, action.color);
    final iconColor = AppColors.adaptOf(
      context,
      action.iconColor ?? actionColor,
    );
    return Semantics(
      button: true,
      enabled: action.onTap != null,
      label: 'Chức năng ${action.title}',
      hint: action.description,
      child: Material(
        color: AppColors.cardOf(context),
        borderRadius: AppRadius.allLg,
        child: InkWell(
          onTap: action.onTap,
          borderRadius: AppRadius.allLg,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: AppRadius.allLg,
              border: Border.all(color: AppColors.borderOf(context)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color:
                        action.iconBackground ??
                        AppColors.infoSurfaceOf(context),
                    borderRadius: AppRadius.allMd,
                  ),
                  child: Icon(action.icon, color: iconColor, size: 24),
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
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        action.description,
                        maxLines: 2,
                        overflow: TextOverflow.clip,
                        style: AppTextStyles.bodyS.copyWith(
                          color: AppColors.textSecondaryOf(context),
                          height: 18 / 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  PhosphorIconsRegular.caretRight,
                  size: 20,
                  color: AppColors.primaryOf(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
