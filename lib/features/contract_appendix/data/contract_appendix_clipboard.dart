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

  // Formats.htmlText wraps this snippet in the Windows CF_HTML document and
  // fragment markers. Supplying another html/body document here makes Word
  // repair nested markup differently depending on the destination document.
  final html = StringBuffer()
    ..writeln(
      '<table border="0" cellspacing="0" cellpadding="0" width="100%" '
      'style="border-collapse:collapse;table-layout:fixed;'
      'mso-table-layout-alt:fixed;width:100%;">',
    )
    ..writeln('<colgroup>')
    ..writeln(_htmlColumn(_columnWidths[0]))
    ..writeln(_htmlColumn(_columnWidths[1]))
    ..writeln(_htmlColumn(_columnWidths[2]))
    ..writeln(_htmlColumn(_columnWidths[3]))
    ..writeln(_htmlColumn(_columnWidths[4]))
    ..writeln(_htmlColumn(_columnWidths[5]))
    ..writeln(_htmlColumn(_columnWidths[6]))
    ..writeln('</colgroup>')
    // Keep the first row as ordinary tbody/td cells. Word can turn semantic
    // thead/th markup into a repeating table header on page breaks.
    ..writeln('<tbody><tr>')
    ..write(_htmlHeader('STT', width: _columnWidths[0]))
    ..write(_htmlHeader('Tên hàng hóa', width: _columnWidths[1]))
    ..write(_htmlHeader('SL', width: _columnWidths[2]))
    ..write(_htmlHeader('ĐVT', width: _columnWidths[3]))
    ..write(_htmlHeader('Đơn giá (VNĐ)<br>Chưa VAT', width: _columnWidths[4]))
    ..write(_htmlHeader('GTGT', width: _columnWidths[5]))
    ..write(
      _htmlHeader('Thành tiền (VNĐ)<br>Chưa VAT', width: _columnWidths[6]),
    )
    ..writeln('</tr>');

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
      ..write(
        _htmlCell(
          item.position.toString(),
          width: _columnWidths[0],
          align: 'center',
          nowrap: true,
        ),
      )
      ..write(_htmlCell(item.productName, width: _columnWidths[1]))
      ..write(
        _htmlCell(
          item.quantity.toString(),
          width: _columnWidths[2],
          align: 'center',
          nowrap: true,
        ),
      )
      ..write(
        _htmlCell(
          item.unit,
          width: _columnWidths[3],
          align: 'center',
          nowrap: true,
        ),
      )
      ..write(
        _htmlCell(
          unitBeforeVat,
          width: _columnWidths[4],
          align: 'center',
          nowrap: true,
        ),
      )
      ..write(
        _htmlCell(
          item.vatLabel,
          width: _columnWidths[5],
          align: 'center',
          nowrap: true,
        ),
      )
      ..write(
        _htmlCell(
          lineBeforeVat,
          width: _columnWidths[6],
          align: 'center',
          nowrap: true,
        ),
      )
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
      '<p align="left" style="margin:12pt 0 0 0;text-align:left;">'
      '${_htmlRun('Bằng chữ: ${_html(document.amountInWords!)}', bold: true)}'
      '</p>',
    )
    ..writeln();

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

const _columnWidths = <String>['6%', '40%', '6%', '7%', '16%', '9%', '16%'];

const _wordFontStyle =
    "font-family:'Times New Roman';mso-ascii-font-family:'Times New Roman';"
    "mso-fareast-font-family:'Times New Roman';"
    "mso-hansi-font-family:'Times New Roman';"
    "mso-bidi-font-family:'Times New Roman';font-size:12pt;";

const _cellStyle =
    'border:1px solid #000;padding:5px 6px;'
    'mso-padding-alt:3.75pt 4.5pt 3.75pt 4.5pt;vertical-align:middle;';

String _htmlColumn(String width) =>
    '<col width="$width" style="width:$width;">';

String _htmlHeader(String value, {required String width}) =>
    '<td width="$width" nowrap="nowrap" align="center" valign="middle" '
    'dir="ltr" '
    'style="width:$width;${_cellStyle}background:#f4c7a8;'
    'text-align:center!important;text-justify:none;white-space:nowrap;">'
    '${_htmlBlock(value, align: 'center', bold: true, nowrap: true)}'
    '</td>';

String _htmlCell(
  String value, {
  required String width,
  String align = 'left',
  bool nowrap = false,
}) =>
    '<td width="$width"${nowrap ? ' nowrap="nowrap"' : ''} align="$align" '
    'valign="middle" dir="ltr" style="width:$width;$_cellStyle'
    'text-align:$align!important;text-justify:none;'
    '${nowrap ? 'white-space:nowrap;' : ''}">'
    '${_htmlBlock(_html(value), align: align, nowrap: nowrap)}'
    '</td>';

String _htmlBlock(
  String value, {
  required String align,
  bool bold = false,
  bool nowrap = false,
}) =>
    // Word represents text inside table cells as paragraphs. A div-level
    // alignment can be discarded when the destination document applies its
    // Normal/Body Text paragraph style (for example, justified text). Keep the
    // alignment and zero margins directly on a Word-compatible paragraph.
    '<p align="$align" dir="ltr" style="margin:0cm;mso-para-margin:0cm;'
    'mso-para-margin-left:0cm;mso-para-margin-right:0cm;'
    'text-align:$align!important;text-justify:none;line-height:1.2;'
    '$_wordFontStyle${nowrap ? 'white-space:nowrap;' : ''}">'
    '${_htmlRun(value, bold: bold, nowrap: nowrap)}'
    '</p>';

String _htmlRun(String value, {bool bold = false, bool nowrap = false}) =>
    '<span style="$_wordFontStyle${bold ? 'font-weight:bold;' : ''}'
    '${nowrap ? 'white-space:nowrap;' : ''}">'
    '<font face="Times New Roman" size="3" style="font-size:12pt;">'
    '$value</font></span>';

void _appendHtmlSummary(
  StringBuffer buffer,
  String label,
  String value, {
  bool emphasized = false,
}) {
  final background = emphasized ? 'background:#f4c7a8;' : '';
  buffer.writeln(
    '<tr><td colspan="4" align="center" valign="middle" style="$_cellStyle'
    '${background}text-align:center;">'
    '${_htmlBlock(_html(label), align: 'center', bold: true)}</td>'
    '<td colspan="3" align="center" valign="middle" style="$_cellStyle'
    '${background}text-align:center;white-space:nowrap;">'
    '${_htmlBlock(_html(value), align: 'center', bold: true, nowrap: true)}'
    '</td></tr>',
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
