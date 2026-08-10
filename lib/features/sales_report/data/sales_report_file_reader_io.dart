import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readSalesReportFileChunk(
  String path,
  int offset,
  int length,
) async {
  final handle = await File(path).open();
  try {
    await handle.setPosition(offset);
    return Uint8List.fromList(await handle.read(length));
  } finally {
    await handle.close();
  }
}
