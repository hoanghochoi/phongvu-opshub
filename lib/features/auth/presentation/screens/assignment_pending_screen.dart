import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:phongvu_opshub/app/widgets/app_toast.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../core/logging/app_logger.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_screen_shell.dart';
import '../../../support_chat/presentation/support_chat_surface.dart';

class AssignmentPendingScreen extends StatefulWidget {
  const AssignmentPendingScreen({super.key});

  @override
  State<AssignmentPendingScreen> createState() =>
      _AssignmentPendingScreenState();
}

class _AssignmentPendingScreenState extends State<AssignmentPendingScreen> {
  static const _supportMessage =
      'Chưa được gán phòng ban, cửa hàng. Vui lòng liên hệ hoang.nv1@phongvu-mna.vn - zalo: 0906581906 để được hỗ trợ.';

  bool _refreshing = false;

  Future<void> _refresh() async {
    final stopwatch = Stopwatch()..start();
    final auth = context.read<AuthProvider>();
    final email = auth.user?.email;
    setState(() => _refreshing = true);
    await AppLogger.instance.info(
      'Auth',
      'Assignment pending refresh started',
      context: {'email': email},
    );
    try {
      await auth.refreshUserData();
      if (!mounted) return;
      if (auth.user?.needsOrganizationAssignment != true) {
        await AppLogger.instance.info(
          'Auth',
          'Assignment pending resolved',
          context: {
            'email': auth.user?.email,
            'organizationNodeId': auth.user?.organizationNodeId,
            'durationMs': stopwatch.elapsedMilliseconds,
          },
        );
        if (!mounted) return;
        context.go('/home');
        return;
      }
      await AppLogger.instance.info(
        'Auth',
        'Assignment still pending',
        context: {
          'email': auth.user?.email,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
      if (!mounted) return;
      AppToast.show(
        context,
        const SnackBar(content: Text('Tài khoản vẫn chưa được gán tổ chức.')),
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'Auth',
        'Assignment pending refresh failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {
          'email': email,
          'errorType': error.runtimeType.toString(),
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
      if (mounted) {
        AppToast.show(
          context,
          const SnackBar(content: Text('Không tải lại được tài khoản.')),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _logout() async {
    await context.read<AuthProvider>().logout();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final userEmail = context.select<AuthProvider, String?>(
      (auth) => auth.user?.email,
    );
    final mediaQuery = MediaQuery.of(context);
    final floatingBottomInset = math.max(
      mediaQuery.padding.bottom,
      mediaQuery.viewInsets.bottom,
    );
    return Stack(
      children: [
        AuthScreenShell(
          child: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.primarySurfaceOf(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const SizedBox(
                    width: 56,
                    height: 56,
                    child: Icon(PhosphorIconsRegular.warningCircle, size: 30),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Chờ gán tổ chức',
                  style: AppTextStyles.labelL.copyWith(
                    color: AppColors.primaryOf(context),
                  ),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Text(
                    _supportMessage,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyM.copyWith(
                      color: AppColors.textMutedOf(context),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 220,
                  child: AppSecondaryButton(
                    onPressed: _refreshing ? null : _refresh,
                    icon: PhosphorIconsRegular.arrowClockwise,
                    label: 'Tải lại trạng thái',
                    isLoading: _refreshing,
                    loadingLabel: 'Đang tải lại...',
                    height: 44,
                  ),
                ),
                if (userEmail?.isNotEmpty == true) ...[
                  const SizedBox(height: 28),
                  Text(
                    'Tài khoản: $userEmail',
                    style: AppTextStyles.labelM.copyWith(
                      color: AppColors.primaryOf(context),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                AppLinkButton(
                  onPressed: _refreshing ? null : _logout,
                  icon: PhosphorIconsRegular.signOut,
                  label: 'Đăng xuất',
                  compact: true,
                ),
              ],
            ),
          ),
        ),
        if (maybeSupportChatProvider(context, listen: true)?.enabled == true)
          Positioned(
            right: 16,
            bottom: 32 + floatingBottomInset,
            child: SupportChatBubble(
              onPressed: () => showSupportChatSurface(context),
            ),
          ),
      ],
    );
  }
}
