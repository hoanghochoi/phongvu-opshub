import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_radius.dart';

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

  const AppResponsiveContent({
    super.key,
    required this.child,
    this.maxWidth = AppLayoutTokens.contentMaxWidth,
    this.padding,
    this.alignment = Alignment.topCenter,
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
        return Align(
          alignment: alignment,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
            child: SizedBox(
              width: double.infinity,
              child: Padding(padding: effectivePadding, child: child),
            ),
          ),
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
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  const AppResponsiveScrollView({
    super.key,
    required this.child,
    this.maxWidth = AppLayoutTokens.contentMaxWidth,
    this.padding,
    this.controller,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
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
        return SingleChildScrollView(
          controller: controller,
          keyboardDismissBehavior: keyboardDismissBehavior,
          padding: effectivePadding,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
              child: child,
            ),
          ),
        );
      },
    );
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
