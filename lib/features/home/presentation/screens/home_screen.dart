import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/navigation/app_nav_model.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
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
          greetingSubtitle: _homeGreetingSubtitle(user),
          headerAction: canUsePaymentSpeaker
              ? const _HomeSpeakerStatusButton()
              : null,
          footer: null,
        ),
      );
    }

    // The app-level provider is created eagerly in App; a missing provider is
    // only an integration/bootstrap condition. Keep the approved Home header
    // visible while the shared Foundation state panel covers that condition.
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HomeCommandPanel(user: user),
        const SizedBox(height: AppLayoutTokens.sectionGap),
        const AppStatePanel.loading(
          key: Key('home-summary-provider-loading'),
          title: 'Đang tải tổng quan',
          message: 'Vui lòng chờ trong giây lát.',
        ),
      ],
    );
    return AppResponsiveScrollView(child: content);
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

String _homeGreetingSubtitle(User? user) {
  final parts = <String>[
    if ((user?.email ?? '').trim().isNotEmpty) user!.email.trim(),
    if ((user?.assignedStoreHeaderInfo ?? '').trim().isNotEmpty)
      user!.assignedStoreHeaderInfo.trim(),
  ];
  return parts.isEmpty
      ? 'Thông tin tài khoản đang được cập nhật'
      : parts.join(' · ');
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
    final color = speakerEnabled
        ? AppColors.successOf(context)
        : AppColors.textMutedOf(context);
    final backgroundColor = speakerEnabled
        ? AppColors.successSurfaceOf(context)
        : AppColors.speakerOffSurfaceOf(context);
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
          child: SizedBox(
            width: 152,
            height: 40,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: AppRadius.allPill,
                border: Border.all(color: color),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 104,
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.labelM.copyWith(color: color),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
