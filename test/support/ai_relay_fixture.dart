import 'dart:convert';

import 'package:http/http.dart' as http;

/// A completed relay turn for controller tests that do not inspect deltas.
/// Preserve the supplied result, including intentionally malformed tool calls.
http.StreamedResponse relayTurnResponse(Map<String, dynamic> result) =>
    http.StreamedResponse(
      Stream.value(
        utf8.encode('${jsonEncode({...result, 'type': 'result'})}\n'),
      ),
      200,
      headers: {'content-type': 'application/x-ndjson; charset=utf-8'},
    );
