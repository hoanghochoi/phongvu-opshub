import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/logging/app_logger.dart';
import '../theme/app_radius.dart';

typedef AppRefreshLogContextBuilder = Map<String, Object?> Function();

class AppRefreshCallbacks {
  AppRefreshCallbacks._();

  static Future<void> noop() async {}
}

class AppLayoutTokens {
  AppLayoutTokens._();

  static const double compactBreakpoint = 600;
  static const double tabletBreakpoint = 900;
  static const double desktopBreakpoint = 1200;
  static const double authDesktopBreakpoint = 1024;
  static const double legacyDesktopBreakpoint = tabletBreakpoint;
  static const double contentMaxWidth = 1180;
  static const double pageMaxWidth = contentMaxWidth;
  static const double sidebarWidth = 250;
  static const double tabletRailWidth = 88;
  static const double shellTopBarHeight = 72;
  static const double mobileBottomNavHeight = 76;
  static const double mobileStickyActionBottomInset = 80;
  static const double formMaxWidth = 720;
  static const double actionBarMaxWidth = 560;
  static const double authMaxWidth = 460;
  static const double authBrandPanelMinWidth = 520;
  static const double authFormPanelMinWidth = 420;
  static const double authCardPadding = 28;
  static const double authMobileCardPadding = 22;
  static const double authControlHeight = 48;
  static const double authControlRadius = AppRadius.md;
  static const double authSubmitHeight = 52;
  static const double authBenefitIconSize = 44;
  static const double authCompactBenefitIconSize = 38;
  static const double sectionGap = 24;
  static const double cardGap = 12;
  static const double formFieldGap = 16;
  static const double formSectionGap = 24;
  static const double formInlineGap = 12;
  static const double cardRadius = AppRadius.sm;
  static const double cardPadding = 16;
  static const double cardMarginBottom = 10;
  static const double mobileActionHeight = 48;
  static const double compactActionHeight = 44;
  static const double iconTouchTarget = 48;
  static const double listItemTouchTarget = 56;

  static EdgeInsets pagePaddingFor(double width) {
    if (width >= tabletBreakpoint) {
      return const EdgeInsets.fromLTRB(32, 24, 32, 24);
    }
    return const EdgeInsets.fromLTRB(16, 16, 16, 16);
  }

  static int formColumnsFor(double width) => width >= tabletBreakpoint ? 2 : 1;
}

class AppShadowTokens {
  AppShadowTokens._();

  static List<BoxShadow> authCard(BuildContext context) => [
    BoxShadow(
      color: Theme.of(context).shadowColor.withValues(alpha: 0.10),
      blurRadius: 28,
      offset: const Offset(0, 14),
    ),
  ];
}

class AppResponsiveContent extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsets? padding;
  final Alignment alignment;
  final RefreshCallback? onRefresh;
  final Key? refreshIndicatorKey;
  final String? refreshLogSource;
  final AppRefreshLogContextBuilder? refreshLogContext;
  final ScrollNotificationPredicate? refreshNotificationPredicate;

  const AppResponsiveContent({
    super.key,
    required this.child,
    this.maxWidth = AppLayoutTokens.contentMaxWidth,
    this.padding,
    this.alignment = Alignment.topCenter,
    this.onRefresh,
    this.refreshIndicatorKey,
    this.refreshLogSource,
    this.refreshLogContext,
    this.refreshNotificationPredicate,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = MediaQuery.sizeOf(context).width;
        final boundedWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : viewportWidth;
        final availableWidth = math.min(boundedWidth, viewportWidth);
        final effectivePadding =
            padding ?? AppLayoutTokens.pagePaddingFor(availableWidth);
        final effectiveMaxWidth = math.min(maxWidth, availableWidth);
        final content = Align(
          alignment: alignment,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
            child: SizedBox(
              width: double.infinity,
              child: Padding(padding: effectivePadding, child: child),
            ),
          ),
        );
        return _AppRefreshWrapper(
          refreshIndicatorKey: refreshIndicatorKey,
          onRefresh: onRefresh,
          logSource: refreshLogSource,
          logContext: refreshLogContext,
          notificationPredicate: refreshNotificationPredicate,
          child: content,
        );
      },
    );
  }
}

class AppResponsiveScrollView extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsets? padding;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;
  final RefreshCallback? onRefresh;
  final Key? refreshIndicatorKey;
  final String? refreshLogSource;
  final AppRefreshLogContextBuilder? refreshLogContext;
  final ScrollNotificationPredicate? refreshNotificationPredicate;

  const AppResponsiveScrollView({
    super.key,
    required this.child,
    this.maxWidth = AppLayoutTokens.contentMaxWidth,
    this.padding,
    this.controller,
    this.physics,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
    this.onRefresh,
    this.refreshIndicatorKey,
    this.refreshLogSource,
    this.refreshLogContext,
    this.refreshNotificationPredicate,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = MediaQuery.sizeOf(context).width;
        final boundedWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : viewportWidth;
        final availableWidth = math.min(boundedWidth, viewportWidth);
        final effectivePadding =
            padding ?? AppLayoutTokens.pagePaddingFor(availableWidth);
        final effectiveMaxWidth = math.min(maxWidth, availableWidth);
        final scrollView = SingleChildScrollView(
          controller: controller,
          physics: onRefresh == null
              ? physics
              : _alwaysScrollablePhysics(physics),
          keyboardDismissBehavior: keyboardDismissBehavior,
          padding: effectivePadding,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
              child: child,
            ),
          ),
        );
        return _AppRefreshWrapper(
          refreshIndicatorKey: refreshIndicatorKey,
          onRefresh: onRefresh,
          logSource: refreshLogSource,
          logContext: refreshLogContext,
          notificationPredicate: refreshNotificationPredicate,
          child: scrollView,
        );
      },
    );
  }
}

ScrollPhysics _alwaysScrollablePhysics(ScrollPhysics? physics) {
  if (physics == null) return const AlwaysScrollableScrollPhysics();
  return AlwaysScrollableScrollPhysics(parent: physics);
}

class _AppRefreshWrapper extends StatelessWidget {
  final Widget child;
  final RefreshCallback? onRefresh;
  final Key? refreshIndicatorKey;
  final String? logSource;
  final AppRefreshLogContextBuilder? logContext;
  final ScrollNotificationPredicate? notificationPredicate;

  const _AppRefreshWrapper({
    required this.child,
    required this.onRefresh,
    required this.refreshIndicatorKey,
    required this.logSource,
    required this.logContext,
    required this.notificationPredicate,
  });

  @override
  Widget build(BuildContext context) {
    final refresh = onRefresh;
    if (refresh == null) return child;
    return RefreshIndicator(
      key: refreshIndicatorKey,
      onRefresh: () => _runRefresh(refresh),
      notificationPredicate: notificationPredicate ?? _verticalRefreshOnly,
      child: child,
    );
  }

  bool _verticalRefreshOnly(ScrollNotification notification) {
    return notification.metrics.axis == Axis.vertical;
  }

  Future<void> _runRefresh(RefreshCallback refresh) async {
    final source = logSource;
    final startedAt = DateTime.now();
    if (source != null) {
      await AppLogger.instance.info(
        source,
        'Pull refresh started',
        context: _safeLogContext(),
      );
    }
    try {
      await refresh();
      if (source != null) {
        await AppLogger.instance.info(
          source,
          'Pull refresh succeeded',
          context: {
            ...?_safeLogContext(),
            'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
          },
        );
      }
    } catch (error, stackTrace) {
      if (source != null) {
        await AppLogger.instance.error(
          source,
          'Pull refresh failed',
          error: error,
          stackTrace: stackTrace,
          context: {
            ...?_safeLogContext(),
            'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
          },
        );
      }
      rethrow;
    }
  }

  Map<String, Object?>? _safeLogContext() {
    try {
      return logContext?.call();
    } catch (error) {
      return {'logContextError': error.toString()};
    }
  }
}

class AppFormColumn extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisSize mainAxisSize;

  const AppFormColumn({
    super.key,
    required this.children,
    this.spacing = AppLayoutTokens.formFieldGap,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
    this.mainAxisSize = MainAxisSize.min,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: mainAxisSize,
      crossAxisAlignment: crossAxisAlignment,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) SizedBox(height: spacing),
          children[index],
        ],
      ],
    );
  }
}
