import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'app_paths.dart';

abstract final class AvatarCache {
  static final http.Client _client = http.Client();
  static final Map<String, ({String url, Future<File?> file})> _entries = {};

  static Future<File?> resolve(String key, String url, {bool recheck = false}) {
    final existing = _entries[key];
    if (!recheck && existing?.url == url) return existing!.file;
    final file = () async {
      if (existing != null) await existing.file;
      try {
        return await _load(key, url);
      } on Object {
        return null;
      }
    }();
    _entries[key] = (url: url, file: file);
    return file;
  }

  static Future<File?> _load(String key, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !['http', 'https'].contains(uri.scheme)) return null;
    final base = await AppPaths.storageDirectory();
    if (base == null) return null;
    final directory = Directory(p.join(base, 'avatar_cache'));
    await directory.create(recursive: true);
    final name = base64Url.encode(utf8.encode(key)).replaceAll('=', '');
    final metadata = File(p.join(directory.path, '$name.json'));
    File? previous;
    if (await metadata.exists()) {
      try {
        final data = jsonDecode(await metadata.readAsString());
        if (data is Map && data['file'] is String) {
          final cachedName = data['file'] as String;
          if (cachedName == p.basename(cachedName)) {
            previous = File(p.join(directory.path, cachedName));
            if (data['url'] == url && await previous.exists()) return previous;
          }
        }
      } on Object {
        // A missing or damaged cache falls back to a fresh download.
      }
    }
    final response = await _client
        .send(http.Request('GET', uri))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      await response.stream.timeout(const Duration(seconds: 15)).drain<void>();
      return null;
    }
    const maxBytes = 5 * 1024 * 1024;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 15),
    )) {
      if (bytes.length + chunk.length > maxBytes) return null;
      bytes.add(chunk);
    }
    final content = bytes.takeBytes();
    final codec = await ui.instantiateImageCodec(content, targetWidth: 256);
    codec.dispose();
    final image = File(
      p.join(
        directory.path,
        '$name-${DateTime.now().microsecondsSinceEpoch}.image',
      ),
    );
    await image.writeAsBytes(content, flush: true);
    await metadata.writeAsString(
      jsonEncode({'url': url, 'file': p.basename(image.path)}),
      flush: true,
    );
    if (previous != null) {
      try {
        if (await previous.exists()) await previous.delete();
      } on FileSystemException {
        // A locked old image does not invalidate the new cached avatar.
      }
    }
    return image;
  }
}
