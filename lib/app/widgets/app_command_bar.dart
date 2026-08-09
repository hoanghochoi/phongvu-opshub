import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'app_buttons.dart';
import 'app_cards.dart';
import 'app_inputs.dart';
import 'app_layout.dart';

/// Canonical scan/search command composition used by operational workspaces.
///
/// The input and both primary actions intentionally remain on one horizontal
/// row at every breakpoint so handheld scanner workflows stay one-handed.
class AppCommandBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final String hintText;
  final bool enabled;
  final bool isLoading;
  final TextCapitalization textCapitalization;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onScan;
  final VoidCallback? onPrimaryAction;
  final String scanTooltip;
  final String primaryActionTooltip;
  final Widget? suffixIcon;
  final Key? inputKey;
  final Key? scanKey;
  final Key? primaryActionKey;

  const AppCommandBar({
    super.key,
    required this.controller,
    required this.label,
    required this.hintText,
    required this.onScan,
    required this.onPrimaryAction,
    required this.scanTooltip,
    required this.primaryActionTooltip,
    this.focusNode,
    this.enabled = true,
    this.isLoading = false,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction = TextInputAction.search,
    this.onSubmitted,
    this.suffixIcon,
    this.inputKey,
    this.scanKey,
    this.primaryActionKey,
  });

  @override
  Widget build(BuildContext context) {
    final actionsEnabled = enabled && !isLoading;
    return AppSurfaceCard(
      radius: 12,
      backgroundColor: AppColors.cardOf(context),
      borderColor: AppColors.commandBorderOf(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 20,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelM.copyWith(
                        color: AppColors.textPrimaryOf(context),
                        height: 20 / 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                AppCommandTextInput(
                  key: inputKey,
                  controller: controller,
                  focusNode: focusNode,
                  enabled: actionsEnabled,
                  hintText: hintText,
                  semanticLabel: label,
                  textCapitalization: textCapitalization,
                  textInputAction: textInputAction,
                  onSubmitted: actionsEnabled ? onSubmitted : null,
                  suffixIcon: suffixIcon,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppLayoutTokens.formInlineGap),
          AppIconAction(
            key: scanKey,
            onPressed: actionsEnabled ? onScan : null,
            icon: PhosphorIconsRegular.qrCode,
            tooltip: scanTooltip,
            foregroundColor: AppColors.commandQrForegroundOf(context),
            backgroundColor: AppColors.commandQrSurfaceOf(context),
            iconSize: 24,
          ),
          const SizedBox(width: AppLayoutTokens.formInlineGap),
          AppIconAction(
            key: primaryActionKey,
            onPressed: actionsEnabled ? onPrimaryAction : null,
            icon: isLoading
                ? PhosphorIconsRegular.spinnerGap
                : PhosphorIconsRegular.magnifyingGlass,
            tooltip: isLoading ? 'Đang tìm kiếm' : primaryActionTooltip,
            filled: true,
            disabledBackgroundColor: isLoading
                ? AppColors.primaryOf(context)
                : null,
            disabledForegroundColor: isLoading
                ? AppColors.primaryForegroundOf(context)
                : null,
            iconSize: 20,
          ),
        ],
      ),
    );
  }
}
