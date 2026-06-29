import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../core/logging/app_logger.dart';
import '../providers/auth_provider.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
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
        ScaffoldMessenger.of(context).showSnackBar(
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
    return Scaffold(
      appBar: const GradientHeader(title: 'Chờ gán tổ chức', showBack: false),
      body: AppResponsiveContent(
        maxWidth: AppLayoutTokens.formMaxWidth,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.account_tree_outlined, size: 56),
            const SizedBox(height: AppLayoutTokens.formSectionGap),
            Text(
              _supportMessage,
              textAlign: TextAlign.center,
              style: AppTextStyles.headingS,
            ),
            if (userEmail?.isNotEmpty == true) ...[
              const SizedBox(height: AppLayoutTokens.formInlineGap),
              Text(
                userEmail!,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyM,
              ),
            ],
            const SizedBox(height: AppLayoutTokens.formSectionGap),
            AppPrimaryButton(
              onPressed: _refreshing ? null : _refresh,
              icon: Icons.refresh_rounded,
              label: 'Tải lại tài khoản',
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
