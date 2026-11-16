import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/tools/netrix/batch2/batch2_address_tools.dart';
import 'package:qfli_studio_core/tools/netrix/batch2/batch2_models.dart';
import 'package:qfli_studio_core/tools/netrix/batch2/batch2_network_tools.dart';

/// Every batch 2 tool must be registered, unique, and runnable. Runners that
/// would leave the machine are exercised through their input validation only,
/// so the suite never depends on the network.
List<NetrixToolDefinition> get _batch2Tools => <NetrixToolDefinition>[
      ...batch2AddressTools,
      ...batch2NetworkTools,
    ];

Future<NetrixToolResult> _run(NetrixToolDefinition tool,
    Map<String, String> values) {
  return tool.run(values);
}

void main() {
  test('registers every batch 2 tool with a unique id', () {
    final List<NetrixToolDefinition> tools = _batch2Tools;
    expect(tools, hasLength(27));
    final Set<String> ids = tools.map((NetrixToolDefinition tool) => tool.id).toSet();
    expect(ids, hasLength(tools.length));
    for (final NetrixToolDefinition tool in tools) {
      expect(tool.id, matches(RegExp(r'^[a-z0-9-]+$')));
      expect(tool.title, isNotEmpty);
      expect(tool.titleEn, isNotEmpty);
      expect(tool.description, isNotEmpty);
      expect(tool.run, isNotNull);
      final Set<String> fieldIds =
          tool.fields.map((NetrixToolField field) => field.id).toSet();
      expect(fieldIds, hasLength(tool.fields.length), reason: tool.id);
    }
  });

  test('covers the netrix category set of batch 2', () {
    final Set<NetrixToolCategory> categories = _batch2Tools
        .map((NetrixToolDefinition tool) => tool.category)
        .toSet();
    expect(
      categories,
      containsAll(<NetrixToolCategory>[
        NetrixToolCategory.diagnostics,
        NetrixToolCategory.address,
        NetrixToolCategory.dns,
        NetrixToolCategory.web,
        NetrixToolCategory.local,
      ]),
    );
  });

  test('subnet-calculator reports the netrix row set', () async {
    final NetrixToolDefinition tool =
        _batch2Tools.firstWhere((t) => t.id == 'subnet-calculator');
    final NetrixToolResult result =
        await _run(tool, <String, String>{'cidr': '192.168.1.42/24'});
    expect(result.ok, isTrue);
    expect(result.title, '子网计算完成');
    expect(
      result.rows.map((NetrixResultRow row) => '${row.label}=${row.value}'),
      <String>[
        '网络地址=192.168.1.0',
        '前缀长度=/24',
        '子网掩码=255.255.255.0',
        '广播地址=192.168.1.255',
        '首个主机=192.168.1.1',
        '最后主机=192.168.1.254',
        '可用主机数=254',
      ],
    );
  });

  test('address tools keep their netrix defaults and output', () async {
    final NetrixToolDefinition splitter =
        _batch2Tools.firstWhere((t) => t.id == 'subnet-splitter');
    expect(splitter.fields.first.initialValue, '10.0.0.0/16');
    expect(splitter.fields.last.initialValue, '24');
    final NetrixToolResult split = await _run(
      splitter,
      <String, String>{'cidr': '10.0.0.0/16', 'prefix': '24'},
    );
    expect(split.summary, '生成 256 个 /24 子网');
    expect(split.panels.single.text.split('\n').first, '10.0.0.0/24');
    expect(split.panels.single.text.split('\n').last, '10.0.255.0/24');

    final NetrixToolDefinition converter =
        _batch2Tools.firstWhere((t) => t.id == 'ip-converter');
    final NetrixToolResult converted =
        await _run(converter, <String, String>{'ip': '192.168.1.1'});
    expect(
      converted.rows.map((NetrixResultRow row) => row.value),
      <String>['192.168.1.1', '3232235777', '0xc0a80101',
        '11000000101010000000000100000001'],
    );

    final NetrixToolDefinition membership =
        _batch2Tools.firstWhere((t) => t.id == 'ip-membership');
    final NetrixToolResult inside = await _run(membership, <String, String>{
      'ip': '192.168.1.42',
      'cidr': '192.168.1.0/24',
    });
    expect(inside.ok, isTrue);
    expect(inside.title, '地址属于网段');
    final NetrixToolResult outside = await _run(membership, <String, String>{
      'ip': '192.168.2.42',
      'cidr': '192.168.1.0/24',
    });
    expect(outside.ok, isFalse);
    expect(outside.title, '地址不属于网段');

    final NetrixToolDefinition scope =
        _batch2Tools.firstWhere((t) => t.id == 'ipv4-scope');
    final NetrixToolResult scoped =
        await _run(scope, <String, String>{'ip': '10.0.0.1'});
    expect(scoped.rows.last.value, '私有地址');
  });

  test('mac-normalizer keeps the three netrix formats', () async {
    final NetrixToolDefinition tool =
        _batch2Tools.firstWhere((t) => t.id == 'mac-normalizer');
    final NetrixToolResult result =
        await _run(tool, <String, String>{'mac': '00-11-22-33-44-55'});
    expect(
      result.rows.map((NetrixResultRow row) => row.value),
      <String>['00:11:22:33:44:55', '00-11-22-33-44-55', '0011.2233.4455'],
    );
  });

  test('offline tools reject invalid input with netrix error keys', () async {
    Future<String> errorCode(String id, Map<String, String> values) async {
      final NetrixToolDefinition tool =
          _batch2Tools.firstWhere((t) => t.id == id);
      try {
        await _run(tool, values);
      } on NetrixToolException catch (error) {
        return error.message;
      }
      fail('$id accepted invalid input');
    }

    expect(
      await errorCode('subnet-calculator', <String, String>{'cidr': '10.0.0.0'}),
      'error_cidr_format',
    );
    expect(
      await errorCode('ip-inspector', <String, String>{'ip': 'nope'}),
      'error_invalid_ip',
    );
    expect(
      await errorCode('mac-normalizer', <String, String>{'mac': 'zz'}),
      'error_mac_format',
    );
    expect(
      await errorCode('mask-prefix', <String, String>{'mask': '255.0.255.0'}),
      'error_non_contiguous_mask',
    );
    expect(
      await errorCode('wildcard-mask', <String, String>{'prefix': 'x'}),
      'error_prefix_integer',
    );
    expect(
      await errorCode('prefix-mask', <String, String>{'prefix': '99'}),
      'error_ipv4_prefix',
    );
    expect(
      await errorCode('ip-range', <String, String>{'cidr': ''}),
      'error_required',
    );
  });

  test('network tools validate before touching the network', () async {
    Future<String> errorCode(String id, Map<String, String> values) async {
      final NetrixToolDefinition tool =
          _batch2Tools.firstWhere((t) => t.id == id);
      try {
        await _run(tool, values);
      } on NetrixToolException catch (error) {
        return error.message;
      }
      fail('$id accepted invalid input');
    }

    expect(
      await errorCode('reachability', <String, String>{
        'host': 'example.com',
        'port': '99999',
      }),
      'error_port_range',
    );
    expect(
      await errorCode('port-scan', <String, String>{
        'host': '127.0.0.1',
        'ports': '',
      }),
      'error_no_ports',
    );
    expect(
      await errorCode('host-scan', <String, String>{
        'cidr': '8.8.8.0/24',
        'ports': '443',
      }),
      'error_private_network_only',
    );
    expect(
      await errorCode('host-scan', <String, String>{
        'cidr': '192.168.0.0/16',
        'ports': '443',
      }),
      'error_host_limit',
    );
    expect(
      await errorCode('http-request', <String, String>{
        'method': 'GET',
        'url': 'ftp://example.com',
      }),
      'error_http_url',
    );
    expect(
      await errorCode('http-request', <String, String>{
        'method': 'GET',
        'url': 'https://example.com',
        'headers': 'broken',
      }),
      'error_header_format',
    );
    expect(
      await errorCode('dns-record', <String, String>{
        'name': 'example.com',
        'type': 'ZZZ',
      }),
      'error_dns_record_type',
    );
    expect(
      await errorCode('hostname-lookup', <String, String>{'host': 'a b'}),
      'error_whitespace',
    );
    expect(
      await errorCode('websocket', <String, String>{'url': 'https://x.test'}),
      'error_websocket_url',
    );
    expect(
      await errorCode('rdap', <String, String>{'target': ''}),
      'error_required',
    );
    expect(
      await errorCode('tls-inspector', <String, String>{'host': 'a b'}),
      'error_whitespace',
    );
  });

  test('keeps the two netrix tools that take no input', () {
    expect(
      batch2NetworkTools.firstWhere((t) => t.id == 'public-ip').fields,
      isEmpty,
    );
    expect(
      batch2NetworkTools.firstWhere((t) => t.id == 'local-interfaces').fields,
      isEmpty,
    );
  });
}
