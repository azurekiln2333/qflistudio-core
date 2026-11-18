import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/tools/netrix/batch2/batch2_models.dart';
import 'package:qfli_studio_core/tools/netrix/batch2/netrix_batch2_tools.dart';

/// The batch 2 registration list is the single source of truth the toolbox
/// registry concatenates, so its ids must match the published inventory.
void main() {
  test('registers exactly the 27 inventoried batch 2 ids', () {
    final List<String> ids =
        netrixBatch2Tools.map((NetrixToolDefinition tool) => tool.id).toList();
    expect(ids, netrixBatch2ToolIds);
    expect(ids.toSet(), hasLength(27));
  });

  test('keeps the netrix ids unique inside the batch', () {
    final Set<String> ids =
        netrixBatch2Tools.map((NetrixToolDefinition tool) => tool.id).toSet();
    expect(ids.length, netrixBatch2Tools.length);
    for (final String id in ids) {
      expect(id, matches(RegExp(r'^[a-z0-9-]+$')));
    }
  });

  test('does not own any batch 1 or batch 3 id', () {
    const List<String> otherBatches = <String>[
      // batch 1 (Pi C)
      'url-parser', 'json', 'base64', 'url-codec', 'hex', 'digest', 'jwt',
      'http-status', 'port-reference', 'headers-parser', 'curl-builder',
      'reverse-dns', 'dns-name', 'query-parser', 'query-builder',
      'http-content-type', 'http-cache-control', 'http-date', 'basic-auth',
      'timestamp-converter', 'port-range', 'cookie-parser', 'url-join',
      'http-method', 'dns-label',
    ];
    final Set<String> mine = netrixBatch2ToolIds.toSet();
    for (final String id in otherBatches) {
      expect(mine.contains(id), isFalse, reason: id);
    }
    expect(mine.length + otherBatches.length, 52);
  });
}
