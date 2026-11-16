import 'batch2_address_tools.dart';
import 'batch2_models.dart';
import 'batch2_network_tools.dart';

/// Registration entry point for the netrix port, batch 2 (27 tools).
///
/// The toolbox registry concatenates one list per batch, so a batch can grow
/// without any other batch editing the same file. This list owns its order:
/// the netrix `kTools` order is preserved inside each group, and the address
/// group comes first exactly as in the inventory
/// (`research/netrix-tools-inventory.md`, section 7.2).
List<NetrixToolDefinition> get netrixBatch2Tools => <NetrixToolDefinition>[
      ...batch2AddressTools,
      ...batch2NetworkTools,
    ];

/// Ids owned by batch 2, in registration order.
///
/// Kept next to the list so the "every netrix tool belongs to exactly one
/// batch" check can compare it against the inventory without running Flutter.
const List<String> netrixBatch2ToolIds = <String>[
  'subnet-calculator',
  'subnet-splitter',
  'range-to-cidr',
  'cidr-aggregate',
  'ip-converter',
  'wildcard-mask',
  'ip-inspector',
  'ip-membership',
  'ip-range',
  'prefix-mask',
  'mask-prefix',
  'ipv4-classifier',
  'ipv4-scope',
  'reachability',
  'port-check',
  'port-scan',
  'host-scan',
  'hostname-lookup',
  'dns-record',
  'public-ip',
  'local-interfaces',
  'http-request',
  'websocket',
  'mac-normalizer',
  'dns-propagation',
  'rdap',
  'tls-inspector',
];
