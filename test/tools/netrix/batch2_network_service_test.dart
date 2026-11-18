import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/tools/netrix/batch2/batch2_models.dart';
import 'package:qfli_studio_core/tools/netrix/batch2/batch2_network_service.dart';

/// Ported from `netrix/test/core_services_test.dart` (local network bounds)
/// plus the header parsing contract from `netrix/test/registry_test.dart`.
void main() {
  group('local network and host scan bounds', () {
    test('groups interface addresses by IP version', () {
      const LocalInterfaceInfo info = LocalInterfaceInfo(
        name: 'lan0',
        addresses: <String>['192.168.1.10', 'fe80::1', '2001:db8::10'],
      );
      expect(info.ipv4Addresses, <String>['192.168.1.10']);
      expect(info.ipv6Addresses, <String>['fe80::1', '2001:db8::10']);
    });

    test('rejects public and oversized host scan ranges before probing', () {
      const NetworkService service = NetworkService();
      expect(
        () => service.scanHosts(
          rawCidr: '8.8.8.0/24',
          ports: <int>[443],
        ),
        throwsA(isA<NetrixToolException>()),
      );
      expect(
        () => service.scanHosts(
          rawCidr: '192.168.0.0/16',
          ports: <int>[443],
        ),
        throwsA(isA<NetrixToolException>()),
      );
    });

    test('rejects an empty or oversized host port list', () {
      const NetworkService service = NetworkService();
      expect(
        () => service.scanHosts(rawCidr: '192.168.1.0/24', ports: <int>[]),
        throwsA(isA<NetrixToolException>()),
      );
      expect(
        () => service.scanHosts(
          rawCidr: '192.168.1.0/24',
          ports: <int>[for (int port = 1; port <= 17; port++) port],
        ),
        throwsA(isA<NetrixToolException>()),
      );
    });

    test('rejects an invalid HTTP method or URL before sending', () {
      const NetworkService service = NetworkService();
      expect(
        () => service.httpRequest(method: 'GET', rawUrl: 'ftp://example.com'),
        throwsA(isA<NetrixToolException>()),
      );
      expect(
        () => service.httpRequest(method: 'BREW', rawUrl: 'https://x.test'),
        throwsA(isA<NetrixToolException>()),
      );
    });

    test('rejects an invalid WebSocket URL before connecting', () {
      const NetworkService service = NetworkService();
      expect(
        () => service.webSocketProbe(rawUrl: 'https://example.com'),
        throwsA(isA<NetrixToolException>()),
      );
    });
  });

  group('header parsing', () {
    test('parses one request header per line', () {
      expect(
        parseHeaders('Accept: application/json\nX-Debug: true'),
        <String, String>{'Accept': 'application/json', 'X-Debug': 'true'},
      );
      expect(
        () => parseHeaders('missing separator'),
        throwsA(isA<NetrixToolException>()),
      );
    });
  });
}
