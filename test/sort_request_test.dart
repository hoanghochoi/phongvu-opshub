import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/features/sort/data/models/sort_request.dart';

void main() {
  test('SortRequest sends only fields accepted by the backend DTO', () {
    expect(SortRequest(text: '250403171').toJson(), {'text': '250403171'});
  });
}
