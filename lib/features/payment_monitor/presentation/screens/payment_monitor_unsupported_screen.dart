import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../core/logging/app_logger.dart';

class PaymentMonitorUnsupportedScreen extends StatefulWidget {
  const PaymentMonitorUnsupportedScreen({super.key});

  @override
  State<PaymentMonitorUnsupportedScreen> createState() =>
      _PaymentMonitorUnsupportedScreenState();
}

class _PaymentMonitorUnsupportedScreenState
    extends State<PaymentMonitorUnsupportedScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(_logUnsupportedAccess());
  }

  Future<void> _logUnsupportedAccess() {
    return AppLogger.instance.warn(
      'PaymentMonitor',
      'Payment monitor unsupported platform screen shown',
      context: {'platform': defaultTargetPlatform.name, 'isWeb': kIsWeb},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GradientHeader(
        title: 'Theo d\u00F5i ti\u1EC1n v\u00E0o',
        showBack: true,
      ),
      body: SafeArea(
        child: AppResponsiveScrollView(
          maxWidth: AppLayoutTokens.formMaxWidth,
          child: AppStatePanel(
            icon: Icons.web_asset_off_outlined,
            title: 'Ch\u01B0a h\u1ED7 tr\u1EE3 tr\u00EAn web',
            message:
                'Vui l\u00F2ng d\u00F9ng app Android ho\u1EB7c Windows \u0111\u1EC3 theo d\u00F5i ti\u1EC1n v\u00E0o. Ri\u00EAng \u0111\u1ECDc loa thanh to\u00E1n ch\u1EC9 ch\u1EA1y tr\u00EAn Windows.',
            tone: AppStateTone.warning,
            actionLabel: 'V\u1EC1 trang ch\u1EE7',
            actionIcon: Icons.home_rounded,
            onAction: () => context.go('/home'),
          ),
        ),
      ),
    );
  }
}
