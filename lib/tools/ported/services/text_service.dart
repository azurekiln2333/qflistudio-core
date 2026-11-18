import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models.dart';

String formatJson(String raw) {
  try {
    final Object? decoded = jsonDecode(requireValue(raw, field: 'JSON'));
    return const JsonEncoder.withIndent('  ').convert(decoded);
  } on FormatException {
    throw ToolException('error_invalid_json');
  }
}

String base64EncodeText(String raw) => base64Encode(utf8.encode(raw));

String base64DecodeText(String raw) {
  try {
    return utf8.decode(base64.decode(requireValue(raw, field: 'Base64')));
  } on FormatException {
    throw ToolException('error_invalid_base64');
  } on ArgumentError {
    throw ToolException('error_invalid_base64');
  }
}

String urlEncodeText(String raw) => Uri.encodeComponent(raw);

String urlDecodeText(String raw) {
  try {
    return Uri.decodeComponent(raw);
  } on FormatException {
    throw ToolException('error_invalid_url_encoding');
  }
}

String hexEncodeText(String raw) {
  final StringBuffer output = StringBuffer();
  for (final int byte in utf8.encode(raw)) {
    output.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return output.toString();
}

String hexDecodeText(String raw) {
  final String value =
      requireValue(raw, field: 'Hex').replaceAll(RegExp(r'\s+'), '');
  if (value.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
    throw ToolException('error_invalid_hex');
  }
  final List<int> bytes = <int>[];
  for (int i = 0; i < value.length; i += 2) {
    bytes.add(int.parse(value.substring(i, i + 2), radix: 16));
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    throw ToolException('error_invalid_utf8');
  }
}

String digestText(String raw, String algorithm) {
  final List<int> bytes = utf8.encode(raw);
  final Digest digest;
  switch (algorithm.toLowerCase()) {
    case 'md5':
      digest = md5.convert(bytes);
    case 'sha1':
      digest = sha1.convert(bytes);
    case 'sha256':
      digest = sha256.convert(bytes);
    case 'sha512':
      digest = sha512.convert(bytes);
    default:
      throw ToolException('error_unsupported_algorithm');
  }
  return digest.toString();
}

class JwtDecodeResult {
  const JwtDecodeResult(
      {required this.header,
      required this.payload,
      required this.hasSignature});

  final Map<String, dynamic> header;
  final Object? payload;
  final bool hasSignature;
}

JwtDecodeResult decodeJwt(String raw) {
  final List<String> parts = requireValue(raw, field: 'JWT').split('.');
  if (parts.length != 3) throw ToolException('error_invalid_jwt_parts');
  Object decodePart(String value, String label) {
    try {
      final Uint8List bytes = base64Url.decode(base64Url.normalize(value));
      return jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw ToolException('error_invalid_jwt_json');
    } on ArgumentError {
      throw ToolException('error_invalid_jwt_encoding');
    }
  }

  final Object headerObject = decodePart(parts[0], 'header');
  if (headerObject is! Map<String, dynamic>) {
    throw ToolException('error_invalid_jwt_header');
  }
  return JwtDecodeResult(
    header: headerObject,
    payload: decodePart(parts[1], 'payload'),
    hasSignature: parts[2].isNotEmpty,
  );
}
