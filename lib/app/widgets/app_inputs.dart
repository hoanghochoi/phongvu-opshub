import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_text_styles.dart';
import 'app_layout.dart';

class AppInputMetrics {
  AppInputMetrics._();

  static const double height = AppLayoutTokens.authControlHeight;
  static const double iconBoxSize = AppLayoutTokens.authControlHeight;
  static const EdgeInsets contentPadding = EdgeInsets.symmetric(
    horizontal: 14,
    vertical: 12,
  );
}

InputDecoration appInputDecoration({
  required String label,
  IconData? icon,
  String? hintText,
  String? helperText,
  String? suffixText,
  String? errorText,
  bool dense = false,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hintText,
    helperText: helperText,
    suffixText: suffixText,
    errorText: errorText,
    prefixIcon: icon == null ? null : Icon(icon, size: 20),
    prefixIconConstraints: const BoxConstraints.tightFor(
      width: AppInputMetrics.iconBoxSize,
      height: AppInputMetrics.iconBoxSize,
    ),
    suffixIcon: suffixIcon,
    suffixIconConstraints: const BoxConstraints.tightFor(
      width: AppInputMetrics.iconBoxSize,
      height: AppInputMetrics.iconBoxSize,
    ),
    isDense: dense,
    contentPadding: AppInputMetrics.contentPadding,
    constraints: const BoxConstraints(minHeight: AppInputMetrics.height),
  );
}

class AppTextInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? hintText;
  final String? helperText;
  final String? suffixText;
  final String? errorText;
  final bool dense;
  final bool autofocus;
  final bool enabled;
  final bool readOnly;
  final bool obscureText;
  final bool autocorrect;
  final Iterable<String>? autofillHints;
  final int? maxLines;
  final int? minLines;
  final TextInputAction? textInputAction;
  final Widget? suffixIcon;

  const AppTextInput({
    super.key,
    required this.controller,
    required this.label,
    this.icon,
    this.focusNode,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.hintText,
    this.helperText,
    this.suffixText,
    this.errorText,
    this.dense = false,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.autocorrect = true,
    this.autofillHints,
    this.maxLines = 1,
    this.minLines,
    this.textInputAction,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      autofocus: autofocus,
      enabled: enabled,
      readOnly: readOnly,
      obscureText: obscureText,
      autocorrect: autocorrect,
      autofillHints: autofillHints,
      maxLines: maxLines,
      minLines: minLines,
      textInputAction: textInputAction,
      style: AppTextStyles.bodyM,
      decoration: appInputDecoration(
        label: label,
        icon: icon,
        hintText: hintText,
        helperText: helperText,
        suffixText: suffixText,
        errorText: errorText,
        dense: dense,
        suffixIcon: suffixIcon,
      ),
    );
  }
}

class AppFormTextInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final FormFieldValidator<String>? validator;
  final String? hintText;
  final String? helperText;
  final String? suffixText;
  final String? errorText;
  final bool dense;
  final bool autofocus;
  final bool enabled;
  final bool readOnly;
  final bool obscureText;
  final bool autocorrect;
  final Iterable<String>? autofillHints;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final TextInputAction? textInputAction;
  final Widget? suffixIcon;
  final bool alignLabelWithHint;
  final String? counterText;

  const AppFormTextInput({
    super.key,
    required this.controller,
    required this.label,
    this.icon,
    this.focusNode,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.onChanged,
    this.onFieldSubmitted,
    this.validator,
    this.hintText,
    this.helperText,
    this.suffixText,
    this.errorText,
    this.dense = false,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.autocorrect = true,
    this.autofillHints,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.textInputAction,
    this.suffixIcon,
    this.alignLabelWithHint = false,
    this.counterText,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
      autofocus: autofocus,
      enabled: enabled,
      readOnly: readOnly,
      obscureText: obscureText,
      autocorrect: autocorrect,
      autofillHints: autofillHints,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      textInputAction: textInputAction,
      style: AppTextStyles.bodyM,
      decoration:
          appInputDecoration(
            label: label,
            icon: icon,
            hintText: hintText,
            helperText: helperText,
            suffixText: suffixText,
            errorText: errorText,
            dense: dense,
            suffixIcon: suffixIcon,
          ).copyWith(
            alignLabelWithHint: alignLabelWithHint,
            counterText: counterText,
          ),
    );
  }
}

class AppReadOnlyField extends StatelessWidget {
  final String value;
  final String label;
  final IconData? icon;
  final int maxLines;

  const AppReadOnlyField({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      enabled: false,
      maxLines: maxLines,
      style: AppTextStyles.bodyM,
      decoration: appInputDecoration(label: label, icon: icon),
    );
  }
}

class AppSelectField<T> extends StatelessWidget {
  final String label;
  final T? value;
  final IconData? icon;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final FormFieldValidator<T>? validator;
  final String? hintText;
  final bool dense;

  const AppSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.validator,
    this.hintText,
    this.icon,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      hint: hintText == null ? null : Text(hintText!),
      style: AppTextStyles.bodyM.copyWith(
        color: Theme.of(context).colorScheme.onSurface,
      ),
      decoration: appInputDecoration(label: label, icon: icon, dense: dense),
      items: items,
      onChanged: onChanged,
      validator: validator,
    );
  }
}
