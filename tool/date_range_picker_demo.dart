import 'package:flutter/material.dart';
import 'package:phongvu_opshub/app/theme/app_theme.dart';
import 'package:phongvu_opshub/app/widgets/date_range_picker/date_range_picker_demo.dart';

void main() {
  runApp(const DateRangePickerDemoApp());
}

class DateRangePickerDemoApp extends StatelessWidget {
  const DateRangePickerDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: const DateRangePickerDemo(),
    );
  }
}
