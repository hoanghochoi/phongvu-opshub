import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../app/navigation/app_nav_model.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/private_media_headers.dart';
import '../../../../core/platform/app_platform_capabilities.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../payment_monitor/presentation/providers/payment_monitor_provider.dart';
import '../providers/home_summary_provider.dart';
import '../widgets/home_summary_page.dart';

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
    final homeSummaryProvider = context.watch<HomeSummaryProvider?>();
    final workspaceCount = AppNavModel.visibleWorkspaceDestinations(
      user,
    ).length;
    final canUsePaymentSpeaker =
        user?.canUseFeature('PAYMENT_SPEAKER') == true &&
        AppPlatformCapabilities.isPaymentSpeakerSupported();

    _logHomeResolved(
      workspaceCount,
      user,
      hasSummaryProvider: homeSummaryProvider != null,
    );

    if (homeSummaryProvider != null) {
      return AppResponsiveContent(
        onRefresh: homeSummaryProvider.canRefresh
            ? homeSummaryProvider.refreshNow
            : AppRefreshCallbacks.noop,
        refreshIndicatorKey: const Key('home-summary-pull-refresh'),
        refreshLogSource: 'Home',
        refreshLogContext: () => {
          'hasSummaryProvider': true,
          'canRefreshSummary': homeSummaryProvider.canRefresh,
        },
        child: HomeSummaryPage(
          provider: homeSummaryProvider,
          greetingName: _homeUserGreetingName(user),
          headerAction: canUsePaymentSpeaker
              ? const _HomeSpeakerStatusButton()
              : null,
          footer: null,
        ),
      );
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HomeCommandPanel(user: user),
        const SizedBox(height: AppLayoutTokens.sectionGap),
        _LegacyHomeBody(
          workspaceCount: workspaceCount,
          onOpenOperations: () => _openOperations(context, workspaceCount),
        ),
        const SizedBox(height: 20),
      ],
    );
    return AppResponsiveScrollView(child: content);
  }

  void _openOperations(BuildContext context, int workspaceCount) {
    unawaited(
      AppLogger.instance.info(
        'Home',
        'Operations workspace opened from home',
        context: {'visibleActions': workspaceCount},
      ),
    );
    context.go('/operations');
  }

  List<HomeQuickToolAction> quickToolsForLegacy(
    BuildContext context,
    User? user,
    int workspaceCount,
  ) {
    HomeQuickToolAction action({
      required String id,
      required String title,
      required String description,
      required IconData icon,
      required Color color,
      required String route,
      String? fallbackRoute,
    }) {
      return HomeQuickToolAction(
        id: id,
        title: title,
        description: description,
        icon: icon,
        color: color,
        onTap: () {
          final targetRoute = fallbackRoute ?? route;
          unawaited(
            AppLogger.instance.info(
              'Home',
              'Quick tool opened from home dashboard',
              context: {
                'tool': id,
                'route': targetRoute,
                'visibleActions': workspaceCount,
              },
            ),
          );
          context.go(targetRoute);
        },
      );
    }

    final salesDestination = AppNavModel.destinations.firstWhere(
      (destination) => destination.id == 'sales',
    );
    final statementDestination = AppNavModel.destinations.firstWhere(
      (destination) => destination.id == 'statement',
    );
    final canOpenSales = AppNavModel.canUseDestination(user, salesDestination);
    final canOpenStatement = AppNavModel.canUseDestination(
      user,
      statementDestination,
    );

    return [
      action(
        id: 'reports',
        title: 'Tổng hợp ngày',
        description: 'Xem tổng hợp và chi tiết báo cáo',
        icon: Icons.description_outlined,
        color: AppColors.secondary,
        route: salesDestination.route,
        fallbackRoute: canOpenSales ? null : '/operations',
      ),
      action(
        id: 'reconcile',
        title: 'Đối soát',
        description: 'Đối soát doanh số và đơn hàng',
        icon: Icons.fact_check_outlined,
        color: AppColors.info,
        route: '/bank-statement',
        fallbackRoute: canOpenStatement ? null : '/operations',
      ),
      action(
        id: 'operations',
        title: 'Vận hành',
        description: 'Xử lý đơn và theo dõi tiến độ',
        icon: Icons.apps_outlined,
        color: AppColors.accent,
        route: '/operations',
      ),
      action(
        id: 'settings',
        title: 'Thiết lập phạm vi',
        description: 'Thiết lập hệ thống và phạm vi',
        icon: Icons.settings_outlined,
        color: AppColors.warning,
        route: '/settings',
      ),
    ];
  }

  void _logHomeResolved(
    int visibleCount,
    User? user, {
    required bool hasSummaryProvider,
  }) {
    final hiddenCount = AppNavModel.hiddenWorkspaceCount(user);
    final key = '$visibleCount|$hiddenCount|$hasSummaryProvider';
    if (_lastLogKey == key) return;
    _lastLogKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        AppLogger.instance.info(
          'Home',
          'Home landing resolved',
          context: {
            'visibleActions': visibleCount,
            'hiddenActions': hiddenCount,
            'hasSummaryProvider': hasSummaryProvider,
          },
        ),
      );
    });
  }
}

class _LegacyHomeBody extends StatelessWidget {
  final int workspaceCount;
  final VoidCallback onOpenOperations;

  const _LegacyHomeBody({
    required this.workspaceCount,
    required this.onOpenOperations,
  });

  @override
  Widget build(BuildContext context) {
    if (workspaceCount == 0) {
      return const AppSurfaceCard(
        key: Key('home-empty-state'),
        child: AppStatePanel.empty(
          icon: Icons.apps_outlined,
          title: 'Chưa có chức năng khả dụng',
          message: 'Vui lòng liên hệ quản lý để kiểm tra phân quyền truy cập.',
        ),
      );
    }

    final countLabel = workspaceCount == 1
        ? '1 công cụ đang sẵn sàng'
        : '$workspaceCount công cụ đang sẵn sàng';

    return AppSurfaceCard(
      key: const Key('home-operations-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vận hành theo quyền',
            style: AppTextStyles.headingS.copyWith(
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            countLabel,
            style: AppTextStyles.labelM.copyWith(
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: AppLayoutTokens.sectionGap),
          AppActionRow(
            desktopAlignment: MainAxisAlignment.start,
            children: [
              AppPrimaryButton(
                onPressed: onOpenOperations,
                icon: Icons.apps_rounded,
                label: 'Mở Vận hành',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeCommandPanel extends StatelessWidget {
  final User? user;

  const _HomeCommandPanel({required this.user});

  @override
  Widget build(BuildContext context) {
    final userName = user?.name ?? user?.email ?? 'Nhân viên OpsHub';
    final greetingLabel = homeGreetingLabel(_homeUserGreetingName(user));
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
                      headers: privateMediaHeaders(avatarUrl),
                      width: avatarSize,
                      height: avatarSize,
                      fit: BoxFit.cover,
                      frameBuilder: (context, child, frame, _) {
                        if (frame == null) {
                          return _AvatarInitials(initials);
                        }
                        return child;
                      },
                      errorBuilder: (_, error, _) {
                        unawaited(
                          AppLogger.instance.warn(
                            'Home',
                            'Home avatar image load failed',
                            context: {
                              'protectedMedia': isProtectedPrivateMediaUrl(
                                avatarUrl,
                              ),
                              'urlLength': avatarUrl.length,
                              'errorType': error.runtimeType.toString(),
                            },
                          ),
                        );
                        return _AvatarInitials(initials);
                      },
                    )
                  : _AvatarInitials(initials),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    greetingLabel,
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

String _homeUserGreetingName(User? user) {
  final fullName = [user?.lastName, user?.name]
      .whereType<String>()
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .join(' ');
  if (fullName.isNotEmpty) return fullName;
  return user?.email ?? '';
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

class _HomeSpeakerStatusButton extends StatelessWidget {
  const _HomeSpeakerStatusButton();

  @override
  Widget build(BuildContext context) {
    late final PaymentMonitorProvider monitor;
    try {
      monitor = context.watch<PaymentMonitorProvider>();
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }

    if (!monitor.canUsePaymentSpeaker) {
      return const SizedBox.shrink();
    }

    final speakerEnabled = monitor.isSpeakerEnabled;
    final label = speakerEnabled ? 'Loa đang bật' : 'Loa đang tắt';
    final color = speakerEnabled ? AppColors.success : AppColors.neutral600;
    final backgroundColor = speakerEnabled
        ? AppColors.successSurface
        : AppColors.neutral100;
    final icon = speakerEnabled
        ? Icons.volume_up_rounded
        : Icons.volume_off_rounded;

    void toggleSpeaker() {
      unawaited(
        AppLogger.instance.info(
          'Home',
          'Payment speaker toggled from home status',
          context: {
            'source': 'homeSpeakerStatus',
            'nextEnabled': !speakerEnabled,
            'syncActive': monitor.isActive,
          },
        ),
      );
      unawaited(
        context.read<PaymentMonitorProvider>().setSpeakerEnabled(
          !speakerEnabled,
        ),
      );
    }

    return Tooltip(
      message: speakerEnabled ? 'Bấm để tắt đọc loa' : 'Bấm để bật đọc loa',
      child: Material(
        color: AppColors.transparent,
        child: InkWell(
          key: const Key('home-speaker-status-toggle'),
          borderRadius: AppRadius.allPill,
          onTap: toggleSpeaker,
          child: Container(
            constraints: const BoxConstraints(minHeight: 32),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: AppRadius.allPill,
              border: Border.all(color: color.withValues(alpha: 0.24)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelS.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
