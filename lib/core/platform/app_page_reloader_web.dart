import 'package:web/web.dart' as web;

Future<void> reloadCurrentPage() async {
  web.window.location.reload();
}
