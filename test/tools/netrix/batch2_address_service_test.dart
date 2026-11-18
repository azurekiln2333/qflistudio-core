import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/tools/netrix/batch2/batch2_address_service.dart';
import 'package:qfli_studio_core/tools/netrix/batch2/batch2_models.dart';

/// Ported from `netrix/test/core_services_test.dart` (IPv4 and subnet groups).
void main() {
  group('input validation', () {
    test('normalizes a host with a URL and port', () {
      expect(hostFromInput('https://example.com:8443/path'), 'example.com');
      expect(requirePort('', fallback: 443), 443);
      expect(
        parsePortList('80, 443, 8000-8002'),
        <int>[80, 443, 8000, 8001, 8002],
      );
    });

    test('rejects an oversized port list', () {
      expect(
        () => parsePortList('1-257'),
        throwsA(isA<NetrixToolException>()),
      );
    });
  });

  group('IPv4 and subnet calculations', () {
    test('calculates a /24 subnet', () {
      final SubnetInfo subnet = calculateSubnet('192.168.1.42/24');
      expect(subnet.network, '192.168.1.0');
      expect(subnet.broadcast, '192.168.1.255');
      expect(subnet.firstHost, '192.168.1.1');
      expect(subnet.lastHost, '192.168.1.254');
      expect(subnet.hostCount, 254);
      expect(subnet.mask, '255.255.255.0');
    });

    test('handles /31 without producing a negative host count', () {
      final SubnetInfo subnet = calculateSubnet('10.0.0.8/31');
      expect(subnet.hostCount, 2);
      expect(subnet.firstHost, '10.0.0.8');
      expect(subnet.lastHost, '10.0.0.9');
    });

    test('splits and aggregates aligned CIDR blocks', () {
      expect(splitSubnet('10.0.0.0/16', 24), hasLength(256));
      expect(
        aggregateCidrs('10.0.0.0/25 10.0.0.128/25'),
        <String>['10.0.0.0/24'],
      );
      expect(
        rangeToCidrs('192.168.1.10', '192.168.1.15'),
        <String>['192.168.1.10/31', '192.168.1.12/30'],
      );
    });

    test('formats masks, IPv4 representations, IPv6, and MAC addresses', () {
      expect(wildcardMaskForPrefix(24), '0.0.0.255');
      expect(ipv4Binary('192.168.1.1'), '11000000101010000000000100000001');
      expect(ipv4Hex('192.168.1.1'), 'c0a80101');
      expect(inspectIpAddress('2001:db8::1').type, 'IPv6');
      expect(normalizeMac('0011.2233.4455'), '00:11:22:33:44:55');
    });

    test('checks IPv4 membership', () {
      expect(ipv4InCidr('192.168.1.42', '192.168.1.0/24'), isTrue);
      expect(ipv4InCidr('192.168.2.42', '192.168.1.0/24'), isFalse);
    });

    test('converts masks, ports, and IPv4 scopes', () {
      expect(maskFromPrefix('24').mask, '255.255.255.0');
      expect(maskFromPrefix('24').wildcard, '0.0.0.255');
      expect(prefixFromMask('255.255.255.0').prefix, 24);
      expect(parsePortRange('8000-8080').count, 81);
      expect(classifyIpv4('10.1.2.3').scope, '私有地址');
    });

    test('rejects invalid bounded inputs', () {
      expect(
        () => prefixFromMask('255.0.255.0'),
        throwsA(isA<NetrixToolException>()),
      );
      expect(
        () => parsePortRange('1-4097'),
        throwsA(isA<NetrixToolException>()),
      );
      expect(
        () => calculateSubnet('192.168.1.0'),
        throwsA(isA<NetrixToolException>()),
      );
    });
  });
}
