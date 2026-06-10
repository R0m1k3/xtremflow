import 'package:test/test.dart';
import '../utils/safe_path.dart';

void main() {
  group('SafePath.resolveWithin', () {
    const base = '/app/recordings';

    test('accepts files inside the base directory', () {
      expect(
        SafePath.resolveWithin(base, '/app/recordings/show.log'),
        isNotNull,
      );
      expect(SafePath.resolveWithin(base, 'show.log'), isNotNull);
      expect(
        SafePath.resolveWithin(base, '/app/recordings/sub/dir/file.log'),
        isNotNull,
      );
    });

    test('rejects .. traversal', () {
      expect(
        SafePath.resolveWithin(base, '/app/recordings/../data/xtremflow.db'),
        isNull,
      );
      expect(SafePath.resolveWithin(base, '../../etc/passwd'), isNull);
    });

    test('rejects absolute paths outside the base', () {
      expect(SafePath.resolveWithin(base, '/etc/passwd'), isNull);
      expect(SafePath.resolveWithin(base, '/app/data/xtremflow.db'), isNull);
    });

    test('rejects sibling directories with a shared prefix', () {
      expect(
        SafePath.resolveWithin(base, '/app/recordings-evil/file.log'),
        isNull,
      );
    });
  });
}
