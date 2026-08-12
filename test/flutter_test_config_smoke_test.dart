import 'package:flutter_test/flutter_test.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  test('shared plugin bootstrap is active', () async {
    expect(TestWidgetsFlutterBinding.ensureInitialized(), isNotNull);
    expect((await getApplicationSupportDirectory()).path, isNotEmpty);
    expect(await FilePicker.pickFiles(), isNull);
  });
}
