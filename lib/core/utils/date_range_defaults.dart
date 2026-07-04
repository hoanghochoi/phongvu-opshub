const int appImplicitDateRangeDays = 30;

DateTime appDateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime appImplicitDateRangeStart(
  DateTime anchor, {
  int days = appImplicitDateRangeDays,
}) {
  final end = appDateOnly(anchor);
  return end.subtract(Duration(days: days - 1));
}

DateTime appImplicitDateRangeEnd(DateTime anchor) => appDateOnly(anchor);

String appImplicitDateRangeHelperText({int days = appImplicitDateRangeDays}) {
  return 'Không chọn khoảng ngày: hệ thống mặc định lấy $days ngày gần nhất.';
}
