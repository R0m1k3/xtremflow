import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import '../utils/password_hasher.dart';

void main() {
  group('PasswordHasher', () {
    test('bcrypt roundtrip verifies the original password', () {
      final hash = PasswordHasher.hash('s3cret-Pass!');
      expect(hash, startsWith(r'$2'));
      expect(PasswordHasher.verify('s3cret-Pass!', hash), isTrue);
      expect(PasswordHasher.verify('wrong', hash), isFalse);
    });

    test('legacy unsalted SHA-256 hashes still verify', () {
      final legacy = sha256.convert(utf8.encode('admin')).toString();
      expect(PasswordHasher.verify('admin', legacy), isTrue);
      expect(PasswordHasher.verify('not-admin', legacy), isFalse);
    });

    test('isLegacy detects SHA-256 hex digests only', () {
      final legacy = sha256.convert(utf8.encode('admin')).toString();
      expect(PasswordHasher.isLegacy(legacy), isTrue);
      expect(PasswordHasher.isLegacy(PasswordHasher.hash('admin')), isFalse);
    });

    test('rehash produces a non-legacy hash', () {
      final rehashed = PasswordHasher.hash('admin');
      expect(PasswordHasher.isLegacy(rehashed), isFalse);
      expect(PasswordHasher.verify('admin', rehashed), isTrue);
    });

    test('malformed hash never verifies', () {
      expect(PasswordHasher.verify('x', 'garbage-hash'), isFalse);
    });
  });
}
