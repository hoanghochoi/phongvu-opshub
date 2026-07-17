import 'package:super_clipboard/super_clipboard.dart';

import '../../../core/formatting/money_formatters.dart';
import '../domain/contract_appendix.dart';

class ContractAppendixClipboardPayload {
  final String html;
  final String plainText;

  const ContractAppendixClipboardPayload({
    required this.html,
    required this.plainText,
  });
}

abstract interface class ContractAppendixClipboardWriter {
  Future<void> write(ContractAppendixDocument document);
}

class SuperClipboardContractAppendixWriter
    implements ContractAppendixClipboardWriter {
  const SuperClipboardContractAppendixWriter();

  @override
  Future<void> write(ContractAppendixDocument document) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      throw StateError('Thiết bị này chưa hỗ trợ sao chép bảng.');
    }
    final payload = buildContractAppendixClipboardPayload(document);
    final item = DataWriterItem();
    item.add(Formats.htmlText(payload.html));
    item.add(Formats.plainText(payload.plainText));
    await clipboard.write([item]);
  }
}

ContractAppendixClipboardPayload buildContractAppendixClipboardPayload(
  ContractAppendixDocument document,
) {
  if (!document.isFinalized ||
      document.items.isEmpty ||
      document.totalBeforeVat == null ||
      document.totalVatAmount == null ||
      document.totalAfterVat == null ||
      document.amountInWords == null) {
    throw StateError('Phụ lục phải được lưu đầy đủ trước khi sao chép.');
  }

  final html = StringBuffer()
    ..writeln('<!DOCTYPE html>')
    ..writeln(
      '<html><head><meta charset="utf-8"></head>'
      '<body style="margin:0;font-family:\'Times New Roman\',serif;'
      'font-size:12pt;">',
    )
    ..writeln('<!--StartFragment-->')
    ..writeln(
      '<table style="border-collapse:collapse;table-layout:fixed;width:100%;'
      'font-family:\'Times New Roman\',serif;font-size:12pt;">',
    )
    ..writeln(
      '<colgroup><col style="width:6%;"><col style="width:40%;">'
      '<col style="width:6%;"><col style="width:7%;">'
      '<col style="width:16%;"><col style="width:9%;">'
      '<col style="width:16%;"></colgroup>',
    )
    ..writeln('<thead><tr>')
    ..write(_htmlHeader('STT'))
    ..write(_htmlHeader('Tên hàng hóa'))
    ..write(_htmlHeader('SL'))
    ..write(_htmlHeader('ĐVT'))
    ..write(_htmlHeader('Đơn giá (VNĐ)<br>Chưa VAT'))
    ..write(_htmlHeader('GTGT'))
    ..write(_htmlHeader('Thành tiền (VNĐ)<br>Chưa VAT'))
    ..writeln('</tr></thead><tbody>');

  final tsv = StringBuffer()
    ..writeln(
      'STT\tTên hàng hóa\tSL\tĐVT\tĐơn giá (VNĐ) - Chưa VAT\tGTGT\t'
      'Thành tiền (VNĐ) - Chưa VAT',
    );

  for (final item in document.items) {
    final unitBeforeVat = _money(item.unitPriceBeforeVat);
    final lineBeforeVat = _money(item.lineBeforeVat);
    html
      ..writeln('<tr>')
      ..write(_htmlCell(item.position.toString(), align: 'center'))
      ..write(_htmlCell(item.productName))
      ..write(_htmlCell(item.quantity.toString(), align: 'center'))
      ..write(_htmlCell(item.unit, align: 'center'))
      ..write(_htmlCell(unitBeforeVat, align: 'center'))
      ..write(_htmlCell(item.vatLabel, align: 'center'))
      ..write(_htmlCell(lineBeforeVat, align: 'center'))
      ..writeln('</tr>');
    tsv.writeln(
      '${item.position}\t${_tsv(item.productName)}\t${item.quantity}\t'
      '${_tsv(item.unit)}\t$unitBeforeVat\t${item.vatLabel}\t$lineBeforeVat',
    );
  }

  _appendHtmlSummary(html, 'Tổng cộng', _money(document.totalBeforeVat));
  _appendHtmlSummary(html, 'Thuế GTGT', _money(document.totalVatAmount));
  _appendHtmlSummary(
    html,
    'Tổng giá trị hợp đồng (đã bao gồm thuế GTGT)',
    _money(document.totalAfterVat),
    emphasized: true,
  );
  html
    ..writeln('</tbody></table>')
    ..writeln(
      '<p style="margin:12pt 0 0 0;font-family:\'Times New Roman\',serif;'
      'font-size:12pt;font-weight:bold;text-align:left;">'
      'Bằng chữ: ${_html(document.amountInWords!)}</p>',
    )
    ..writeln('<!--EndFragment-->')
    ..writeln('</body></html>');

  tsv
    ..writeln('Tổng cộng\t\t\t\t\t\t${_money(document.totalBeforeVat)}')
    ..writeln('Thuế GTGT\t\t\t\t\t\t${_money(document.totalVatAmount)}')
    ..writeln(
      'Tổng giá trị hợp đồng (đã bao gồm thuế GTGT)\t\t\t\t\t\t'
      '${_money(document.totalAfterVat)}',
    )
    ..writeln()
    ..write('Bằng chữ: ${_tsv(document.amountInWords!)}');

  return ContractAppendixClipboardPayload(
    html: html.toString(),
    plainText: tsv.toString(),
  );
}

const _cellStyle =
    "font-family:'Times New Roman',serif;font-size:12pt;line-height:1.2;"
    'border:1px solid #000;padding:5px 6px;vertical-align:middle;';

String _htmlHeader(String value) =>
    '<th align="center" valign="middle" style="${_cellStyle}background:'
    '#f4c7a8;text-align:center;font-weight:bold;">$value</th>';

String _htmlCell(String value, {String align = 'left'}) =>
    '<td align="$align" valign="middle" style="${_cellStyle}text-align:'
    '$align;">${_html(value)}</td>';

void _appendHtmlSummary(
  StringBuffer buffer,
  String label,
  String value, {
  bool emphasized = false,
}) {
  final background = emphasized ? 'background:#f4c7a8;' : '';
  buffer.writeln(
    '<tr><td colspan="4" align="center" valign="middle" style="$_cellStyle'
    '${background}text-align:center;font-weight:bold;">${_html(label)}</td>'
    '<td colspan="3" align="center" valign="middle" style="$_cellStyle'
    '${background}text-align:center;font-weight:bold;">'
    '${_html(value)}</td></tr>',
  );
}

String _money(int? value) =>
    value == null ? '' : vietnameseMoneyNumberFormat.format(value);

String _html(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;')
    .replaceAll('\r\n', '<br>')
    .replaceAll('\n', '<br>')
    .replaceAll('\r', '<br>');

String _tsv(String value) => value
    .replaceAll('\r\n', ' ')
    .replaceAll('\n', ' ')
    .replaceAll('\r', ' ')
    .replaceAll('\t', ' ')
    .trim();
