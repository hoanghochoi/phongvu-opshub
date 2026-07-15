import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/data/shared_preferences_query_persistence.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('logout cleanup removes every indexed persisted query', () async {
    const persistence = SharedPreferencesQueryPersistence();
    await persistence.write('production:user-1:home', 'home-value');
    await persistence.write('production:user-1:metrics', 'metrics-value');

    expect(await persistence.read('production:user-1:home'), 'home-value');
    expect(
      await persistence.read('production:user-1:metrics'),
      'metrics-value',
    );

    await SharedPreferencesQueryPersistence.clearAll();

    expect(await persistence.read('production:user-1:home'), isNull);
    expect(await persistence.read('production:user-1:metrics'), isNull);
  });
}
