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
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/platform/app_platform_capabilities.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../payment_monitor/presentation/providers/payment_monitor_provider.dart';

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
            const AppSurfaceCard(
              key: Key('home-empty-state'),
              child: AppStatePanel.empty(
                icon: Icons.apps_outlined,
                title: 'Chưa có chức năng khả dụng',
                message:
                    'Vui lòng liên hệ quản lý để kiểm tra phân quyền truy cập.',
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
    final destinations = AppNavModel.visibleWorkspaceDestinations(user);
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
    final hiddenCount = AppNavModel.hiddenWorkspaceCount(user);
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
    final storeInfo = user?.assignedStoreHeaderInfo ?? 'Chưa được gán Showroom';
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
    final isCompact =
        MediaQuery.sizeOf(context).width < AppLayoutTokens.compactBreakpoint;
    final avatarSize = isCompact ? 48.0 : 42.0;

    return DecoratedBox(
      key: const Key('home-welcome-strip'),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.subtleBorderOf(context)),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          top: isCompact ? 2 : 0,
          bottom: isCompact ? 12 : 10,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: avatarSize,
              height: avatarSize,
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
                      width: avatarSize,
                      height: avatarSize,
                      fit: BoxFit.cover,
                      frameBuilder: (context, child, frame, _) {
                        if (frame == null) {
                          return _AvatarInitials(initials);
                        }
                        return child;
                      },
                      errorBuilder: (_, _, _) => _AvatarInitials(initials),
                    )
                  : _AvatarInitials(initials),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trang chủ vận hành',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.headingS.copyWith(
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelM.copyWith(
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 3),
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
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
