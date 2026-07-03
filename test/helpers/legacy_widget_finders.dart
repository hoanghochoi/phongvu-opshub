import 'package:flutter_test/flutter_test.dart';

Finder findsLegacyGradientHeader() {
  return find.byWidgetPredicate(
    (widget) => widget.runtimeType.toString() == 'GradientHeader',
    description: 'legacy GradientHeader',
  );
}
