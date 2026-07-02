import 'package:flutter/material.dart';

import '../../../../app/widgets/app_buttons.dart';

typedef SalesReportExportCallback = void Function(String exportType);

class SalesReportExportMenuButton extends StatelessWidget {
  final bool isExporting;
  final SalesReportExportCallback onExport;

  const SalesReportExportMenuButton({
    super.key,
    required this.isExporting,
    required this.onExport,
  });

  static const _options = [
    (type: 'HVTC', label: 'HVTC', icon: Icons.school_outlined),
    (type: 'REVENUE', label: 'Doanh số', icon: Icons.payments_outlined),
    (type: 'INSTALLMENT', label: 'Trả góp', icon: Icons.credit_card_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (final option in _options)
          MenuItemButton(
            leadingIcon: Icon(option.icon),
            onPressed: isExporting ? null : () => onExport(option.type),
            child: Text(option.label),
          ),
      ],
      builder: (context, controller, child) {
        return AppSecondaryButton(
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          icon: Icons.download_rounded,
          label: 'Xuất file',
          isLoading: isExporting,
          loadingLabel: 'Đang xuất',
        );
      },
    );
  }
}
