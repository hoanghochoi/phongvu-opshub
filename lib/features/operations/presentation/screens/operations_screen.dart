import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../app/navigation/app_nav_model.dart';
import '../../../../app/widgets/app_feature_grid.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class OperationsScreen extends StatefulWidget {
  const OperationsScreen({super.key});

  @override
  State<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends State<OperationsScreen> {
  String _lastLogKey = '';

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final sections = _buildSections(context, user);
    final visibleCount = sections.fold<int>(
      0,
      (count, section) => count + section.actions.length,
    );

    _logOperationsResolved(visibleCount, sections.length, user);

    return AppResponsiveScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sections.isEmpty)
            const AppStatePanel.empty(
              key: Key('operations-empty-state'),
              icon: Icons.apps_outlined,
              title: 'Chưa có công cụ khả dụng',
              message:
                  'Vui lòng liên hệ quản lý để kiểm tra phân quyền truy cập.',
            )
          else
            Column(
              key: const Key('operations-feature-section'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < sections.length; index++) ...[
                  if (index > 0)
                    const SizedBox(height: AppLayoutTokens.sectionGap),
                  AppFeatureSection(
                    key: ValueKey(
                      'operations-section-${sections[index].group.name}',
                    ),
                    title: sections[index].label,
                    actions: sections[index].actions,
                  ),
                ],
              ],
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  List<_OperationsSection> _buildSections(BuildContext context, User? user) {
    final sections = AppNavModel.visibleWorkspaceSections(user);
    return [
      for (final section in sections)
        _OperationsSection(
          group: section.group,
          label: section.label,
          actions: [
            for (final destination in section.destinations)
              AppFeatureAction(
                icon: destination.icon,
                title: destination.label,
                description: destination.description,
                color: destination.color,
                onTap: () => context.go(destination.route),
              ),
          ],
        ),
    ];
  }

  void _logOperationsResolved(int visibleCount, int sectionCount, User? user) {
    final hiddenCount = AppNavModel.hiddenWorkspaceCount(user);
    final key = '$visibleCount|$hiddenCount|$sectionCount';
    if (_lastLogKey == key) return;
    _lastLogKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        AppLogger.instance.info(
          'Operations',
          'Operations workspace resolved',
          context: {
            'visibleActions': visibleCount,
            'hiddenActions': hiddenCount,
            'sectionCount': sectionCount,
          },
        ),
      );
    });
  }
}

class _OperationsSection {
  final AppNavGroup group;
  final String label;
  final List<AppFeatureAction> actions;

  const _OperationsSection({
    required this.group,
    required this.label,
    required this.actions,
  });
}
