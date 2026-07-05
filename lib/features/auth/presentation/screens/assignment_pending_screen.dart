import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:phongvu_opshub/app/widgets/app_toast.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../core/logging/app_logger.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_screen_shell.dart';

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
    return AuthScreenShell(
      child: AuthCard(
        icon: Icons.account_tree_outlined,
        title: 'Chờ gán tổ chức',
        subtitle: 'Tài khoản đã tạo nhưng chưa có phạm vi sử dụng.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.primarySurfaceOf(context),
                borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
                border: Border.all(
                  color: AppColors.primaryOf(context).withValues(alpha: 0.22),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Việc cần làm', style: AppTextStyles.headingS),
                        const SizedBox(height: AppLayoutTokens.formInlineGap),
                        Text(
                          _supportMessage,
                          style: AppTextStyles.bodyM.copyWith(
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                        if (userEmail?.isNotEmpty == true) ...[
                          const SizedBox(height: AppLayoutTokens.formInlineGap),
                          Text(
                            userEmail!,
                            style: AppTextStyles.labelM.copyWith(
                              color: AppColors.primaryOf(context),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppLayoutTokens.formSectionGap),
            AppPrimaryButton(
              onPressed: _refreshing ? null : _refresh,
              icon: Icons.refresh_rounded,
              label: 'Tải lại trạng thái',
              isLoading: _refreshing,
              loadingLabel: 'Đang tải lại...',
            ),
            const SizedBox(height: AppLayoutTokens.formInlineGap),
            AppSecondaryButton(
              onPressed: _refreshing ? null : _logout,
              icon: Icons.logout_rounded,
              label: 'Đăng xuất',
            ),
          ],
        ),
      ),
    );
  }
}
