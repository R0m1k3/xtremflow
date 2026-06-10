import 'package:test/test.dart';
import '../api/proxy_handler.dart';

void main() {
  group('isForbiddenProxyHost', () {
    test('blocks loopback', () {
      expect(isForbiddenProxyHost('127.0.0.1'), isTrue);
      expect(isForbiddenProxyHost('localhost'), isTrue);
      expect(isForbiddenProxyHost('::1'), isTrue);
    });

    test('blocks private LAN ranges', () {
      expect(isForbiddenProxyHost('10.0.0.5'), isTrue);
      expect(isForbiddenProxyHost('172.16.0.1'), isTrue);
      expect(isForbiddenProxyHost('172.31.255.255'), isTrue);
      expect(isForbiddenProxyHost('192.168.1.10'), isTrue);
    });

    test('blocks link-local / cloud metadata range', () {
      expect(isForbiddenProxyHost('169.254.169.254'), isTrue);
    });

    test('allows public IPs and hostnames', () {
      expect(isForbiddenProxyHost('8.8.8.8'), isFalse);
      expect(isForbiddenProxyHost('172.32.0.1'), isFalse);
      expect(isForbiddenProxyHost('cdn.example.com'), isFalse);
    });
  });
}
