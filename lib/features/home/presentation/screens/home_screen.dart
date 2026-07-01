import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../app/navigation/app_nav_model.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_feature_grid.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/platform/app_platform_capabilities.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../payment_monitor/presentation/providers/payment_delivery_metrics_provider.dart';
import '../../../payment_monitor/presentation/providers/payment_monitor_provider.dart';
import '../../../payment_monitor/presentation/widgets/payment_delivery_metrics_chip.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _lastLogKey = '';

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final actions = _buildHomeActions(context, user);
    final canUsePaymentSpeaker =
        user?.canUseFeature('PAYMENT_SPEAKER') == true &&
        AppPlatformCapabilities.isPaymentSpeakerSupported();

    _logHomeResolved(actions.length, user);

    return AppResponsiveScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HomeCommandPanel(user: user),
          const SizedBox(height: AppLayoutTokens.sectionGap),
          if (canUsePaymentSpeaker) ...[
            const _PaymentMonitorQuickToggle(),
            const SizedBox(height: AppLayoutTokens.sectionGap),
          ],
          if (actions.isEmpty)
            AppSurfaceCard(
              child: Text(
                'Chưa có chức năng khả dụng. Vui lòng liên hệ quản lý để kiểm tra phân quyền.',
                style: AppTextStyles.bodyM.copyWith(
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
            )
          else
            AppFeatureSection(title: 'Không gian làm việc', actions: actions),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  List<AppFeatureAction> _buildHomeActions(BuildContext context, User? user) {
    final destinations = AppNavModel.visibleTaskDestinations(user)
        .where((destination) => destination.id != 'settings')
        .toList(growable: false);
    return [
      for (final destination in destinations)
        AppFeatureAction(
          icon: destination.icon,
          title: destination.label,
          description: destination.description,
          color: destination.color,
          onTap: () {
            if (destination.id == 'feedback') {
              unawaited(
                AppLogger.instance.info(
                  'Feedback',
                  'Suggestion opened from home',
                ),
              );
            }
            context.go(destination.route);
          },
        ),
    ];
  }

  void _logHomeResolved(int visibleCount, User? user) {
    final hiddenCount = AppNavModel.destinations
        .where((destination) => destination.showInTasks)
        .where((destination) => destination.id != 'settings')
        .where(
          (destination) => !AppNavModel.canUseDestination(user, destination),
        )
        .length;
    final key = '$visibleCount|$hiddenCount';
    if (_lastLogKey == key) return;
    _lastLogKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        AppLogger.instance.info(
          'Home',
          'Home command center resolved',
          context: {
            'visibleActions': visibleCount,
            'hiddenActions': hiddenCount,
          },
        ),
      );
    });
  }
}

class _HomeCommandPanel extends StatelessWidget {
  final User? user;

  const _HomeCommandPanel({required this.user});

  @override
  Widget build(BuildContext context) {
    final userName = user?.name ?? user?.email ?? 'Nhân viên OpsHub';
    final storeInfo = user?.assignedStoreHeaderInfo ?? 'Chưa có SR được gán';
    final avatarUrl = user?.avatarUrl?.trim();
    final hasRemoteAvatar =
        avatarUrl != null &&
        (avatarUrl.startsWith('http://') || avatarUrl.startsWith('https://'));
    final cleanName = userName.contains('@')
        ? userName.split('@').first
        : userName;
    final initials = cleanName.trim().isNotEmpty
        ? cleanName.trim().substring(0, 1).toUpperCase()
        : '?';

    return AppSurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primarySurfaceOf(context),
              borderRadius: AppRadius.allLg,
              border: Border.all(color: AppColors.borderOf(context)),
            ),
            clipBehavior: Clip.antiAlias,
            child: hasRemoteAvatar
                ? Image.network(
                    avatarUrl,
                    key: ValueKey(avatarUrl),
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    frameBuilder: (context, child, frame, _) {
                      if (frame == null) return _AvatarInitials(initials);
                      return child;
                    },
                    errorBuilder: (_, _, _) => _AvatarInitials(initials),
                  )
                : _AvatarInitials(initials),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Trang chủ vận hành',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.headingS.copyWith(
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                    ),
                    const _HomePaymentDeliveryMetricsPill(),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  userName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelM.copyWith(
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.store_outlined,
                      color: AppColors.textMutedOf(context),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        storeInfo,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyS.copyWith(
                          color: AppColors.textMutedOf(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarInitials extends StatelessWidget {
  final String initials;

  const _AvatarInitials(this.initials);

  @override
  Widget build(BuildContext context) {
    return Text(
      initials,
      style: AppTextStyles.headingS.copyWith(
        color: AppColors.primaryOf(context),
      ),
    );
  }
}

class _PaymentMonitorQuickToggle extends StatelessWidget {
  const _PaymentMonitorQuickToggle();

  @override
  Widget build(BuildContext context) {
    final monitor = context.watch<PaymentMonitorProvider>();
    final canToggle = monitor.canUsePaymentSpeaker;
    final speakerEnabled = monitor.isSpeakerEnabled;
    final speakerActive = canToggle && speakerEnabled;
    final speakerSelectionNotice = monitor.speakerSelectionNotice;
    final statusText =
        speakerSelectionNotice ??
        (monitor.isActive
            ? speakerActive
                  ? 'Đang cập nhật, có đọc loa'
                  : 'Đang cập nhật, đã tắt loa'
            : canToggle
            ? 'Đang chuẩn bị cập nhật'
            : 'Chọn showroom để dùng');

    return AppSurfaceCard(
      padding: EdgeInsets.zero,
      child: SwitchListTile.adaptive(
        value: speakerActive,
        onChanged: canToggle
            ? (value) => context
                  .read<PaymentMonitorProvider>()
                  .setSpeakerEnabled(value)
            : null,
        secondary: Icon(
          speakerActive ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          color: speakerActive ? AppColors.success : AppColors.neutral500,
        ),
        title: const Text('Đọc loa tiền vào', style: AppTextStyles.labelM),
        subtitle: Text(statusText, style: AppTextStyles.bodyS),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
    );
  }
}

class _HomePaymentDeliveryMetricsPill extends StatelessWidget {
  const _HomePaymentDeliveryMetricsPill();

  @override
  Widget build(BuildContext context) {
    late final bool shouldShow;
    try {
      shouldShow = context.select<PaymentDeliveryMetricsProvider, bool>(
        (provider) => provider.shouldShow,
      );
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    if (!shouldShow) return const SizedBox.shrink();

    return const Padding(
      padding: EdgeInsets.only(left: 8),
      child: PaymentDeliveryMetricsChip(),
    );
  }
}
