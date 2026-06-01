import 'package:flutter/material.dart';

import 'app_layout.dart';

class AppFeatureAction {
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final VoidCallback? onTap;

  const AppFeatureAction({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
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
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
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
        final width = constraints.maxWidth;
        final crossAxisCount = width < 300
            ? 1
            : width >= 980
            ? 4
            : width >= 680
            ? 3
            : 2;
        final spacing = width >= 680 ? 14.0 : 12.0;
        final tileHeight = width < 340 ? 124.0 : 118.0;

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
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
        child: InkWell(
          onTap: action.onTap,
          borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
              border: Border.all(color: Theme.of(context).dividerColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: action.color.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(
                      AppLayoutTokens.cardRadius,
                    ),
                  ),
                  child: Icon(action.icon, color: action.color, size: 20),
                ),
                const Spacer(),
                Text(
                  action.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  action.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
