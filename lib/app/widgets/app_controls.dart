import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_text_styles.dart';
import 'app_layout.dart';

/// Shared checkbox row used by forms that need a compact, keyboard-accessible
/// preference control with the app's focus and color tokens.
class AppCheckbox extends StatelessWidget {
  const AppCheckbox({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
    this.tooltip,
  });

  final bool value;
  final String label;
  final ValueChanged<bool>? onChanged;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final row = Semantics(
      container: true,
      label: label,
      hint: tooltip,
      checked: value,
      enabled: enabled,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AppLayoutTokens.checkboxTouchTarget,
        ),
        child: InkWell(
          onTap: enabled ? () => onChanged!(!value) : null,
          borderRadius: AppRadius.allSm,
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused) ||
                states.contains(WidgetState.hovered)) {
              return AppColors.primaryOf(context).withValues(alpha: 0.08);
            }
            if (states.contains(WidgetState.pressed)) {
              return AppColors.primaryOf(context).withValues(alpha: 0.14);
            }
            return null;
          }),
          child: Row(
            children: [
              Checkbox(
                value: value,
                onChanged: enabled ? (next) => onChanged!(next ?? false) : null,
                semanticLabel: label,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                visualDensity: VisualDensity.standard,
                fillColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.disabled)) {
                    return AppColors.borderOf(context);
                  }
                  if (states.contains(WidgetState.selected)) {
                    return AppColors.primaryOf(context);
                  }
                  return Colors.transparent;
                }),
                checkColor: AppColors.primaryForegroundOf(context),
                side: WidgetStateBorderSide.resolveWith((states) {
                  final color = states.contains(WidgetState.disabled)
                      ? AppColors.borderOf(context)
                      : AppColors.primaryOf(context);
                  return BorderSide(color: color, width: 1.5);
                }),
              ),
              Expanded(child: Text(label, style: AppTextStyles.bodyM)),
            ],
          ),
        ),
      ),
    );

    if (tooltip == null || tooltip!.trim().isEmpty) return row;
    return Tooltip(message: tooltip!, child: row);
  }
}
