import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<bool> writeContractAppendixClipboardOnWeb({
  required String html,
  required String plainText,
}) async {
  final clipboard = web.window.navigator.clipboard;
  final item = web.ClipboardItem(
    <String, JSAny?>{
          'text/html': web.Blob(
            [html.toJS].toJS,
            web.BlobPropertyBag(type: 'text/html'),
          ),
          'text/plain': web.Blob(
            [plainText.toJS].toJS,
            web.BlobPropertyBag(type: 'text/plain'),
          ),
        }.jsify()
        as JSObject,
  );
  await clipboard.write([item].toJS).toDart;
  return true;
}
