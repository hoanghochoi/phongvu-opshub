import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_text_styles.dart';

class AppToast {
  AppToast._();

  static final Map<OverlayState, OverlayEntry> _activeEntries = {};

  static void show(BuildContext context, SnackBar snackBar) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _activeEntries.remove(overlay)?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) => _AppToastOverlay(
        snackBar: snackBar,
        onDisposed: () {
          if (_activeEntries[overlay] == entry) {
            _activeEntries.remove(overlay);
          }
        },
        onDismissed: () {
          if (_activeEntries[overlay] != entry) return;
          _activeEntries.remove(overlay);
          entry.remove();
        },
      ),
    );
    _activeEntries[overlay] = entry;
    overlay.insert(entry);
  }
}

class _AppToastOverlay extends StatefulWidget {
  const _AppToastOverlay({
    required this.snackBar,
    required this.onDisposed,
    required this.onDismissed,
  });

  final SnackBar snackBar;
  final VoidCallback onDisposed;
  final VoidCallback onDismissed;

  @override
  State<_AppToastOverlay> createState() => _AppToastOverlayState();
}

class _AppToastOverlayState extends State<_AppToastOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final AnimationController _lifetimeController;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      reverseDuration: const Duration(milliseconds: 140),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0.10, -0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _lifetimeController =
        AnimationController(vsync: this, duration: widget.snackBar.duration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) _dismiss();
          });
    _controller.forward();
    _lifetimeController.forward();
  }

  Future<void> _dismiss() async {
    if (_dismissing) return;
    _dismissing = true;
    _lifetimeController.stop();
    await _controller.reverse();
    if (mounted) widget.onDismissed();
  }

  @override
  void dispose() {
    _lifetimeController.dispose();
    _controller.dispose();
    widget.onDisposed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final snackBarTheme = theme.snackBarTheme;
    final availableWidth = math.max(0.0, media.size.width - 32);
    final toastWidth = math.min(360.0, availableWidth);
    final backgroundColor =
        widget.snackBar.backgroundColor ??
        snackBarTheme.backgroundColor ??
        AppColors.neutral800;
    final contentStyle =
        snackBarTheme.contentTextStyle ??
        AppTextStyles.bodyM.copyWith(color: AppColors.neutral100);

    return Positioned(
      key: const Key('app-toast-position'),
      top: media.padding.top + 16,
      right: 16,
      width: toastWidth,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _opacity,
          child: Semantics(
            container: true,
            liveRegion: true,
            child: Material(
              key: const Key('app-toast'),
              color: backgroundColor,
              elevation: widget.snackBar.elevation ?? 8,
              shadowColor: AppColors.shadow.withValues(alpha: 0.24),
              shape:
                  widget.snackBar.shape ??
                  RoundedRectangleBorder(borderRadius: AppRadius.allSm),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding:
                    widget.snackBar.padding ??
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: DefaultTextStyle(
                        style: contentStyle,
                        child: widget.snackBar.content,
                      ),
                    ),
                    if (widget.snackBar.action != null) ...[
                      const SizedBox(width: 12),
                      widget.snackBar.action!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
