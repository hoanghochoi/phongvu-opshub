import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';

void main() {
  test('avatarMimeTypeFor maps supported image file names and paths', () {
    expect(
      AuthRepository.avatarMimeTypeFor(fileName: 'avatar.JPG'),
      'image/jpeg',
    );
    expect(
      AuthRepository.avatarMimeTypeFor(fileName: 'profile.png'),
      'image/png',
    );
    expect(
      AuthRepository.avatarMimeTypeFor(fileName: 'avatar.webp'),
      'image/webp',
    );
    expect(
      AuthRepository.avatarMimeTypeFor(fileName: 'avatar.heic'),
      'image/heic',
    );
    expect(
      AuthRepository.avatarMimeTypeFor(
        fileName: '',
        path: r'C:\Users\staff\avatar.heif',
      ),
      'image/heif',
    );
  });

  test('avatarMimeTypeFor rejects unsupported avatar files', () {
    expect(AuthRepository.avatarMimeTypeFor(fileName: 'avatar.pdf'), isNull);
    expect(AuthRepository.avatarMimeTypeFor(fileName: 'avatar'), isNull);
  });
}
