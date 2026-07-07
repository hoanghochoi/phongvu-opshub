import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../core/logging/app_logger.dart';
import '../providers/app_notifications_provider.dart';
import '../widgets/app_notifications_bell.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadNotifications());
    });
  }

  Future<void> _loadNotifications() async {
    late final AppNotificationsProvider provider;
    try {
      provider = context.read<AppNotificationsProvider>();
    } on ProviderNotFoundException {
      await AppLogger.instance.warn(
        'NotificationsScreen',
        'Notifications screen opened without provider',
      );
      return;
    }
    if (!provider.isEnabled) {
      await AppLogger.instance.info(
        'NotificationsScreen',
        'Notifications screen opened without enabled sources',
      );
      return;
    }
    await AppLogger.instance.info(
      'NotificationsScreen',
      'Notifications screen load requested',
      context: {'sourceCount': provider.totalCount},
    );
    await provider.load();
    await provider.markVisibleNotificationsRead();
  }

  @override
  Widget build(BuildContext context) {
    return AppResponsiveScrollView(
      onRefresh: _loadNotifications,
      refreshLogSource: 'NotificationsScreen',
      child: Consumer<AppNotificationsProvider>(
        builder: (context, provider, child) {
          if (!provider.isEnabled) {
            return const AppStatePanel.empty(
              title: 'Chưa có nguồn thông báo',
              message:
                  'Tài khoản hiện tại chưa có thông báo nghiệp vụ để hiển thị.',
            );
          }
          return AppNotificationsContent(provider: provider, fullPage: true);
        },
      ),
    );
  }
}
