import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'debug_log.dart';

/// Scarica una sola volta l'immagine di ogni carta e la salva sul telefono.
class CardImages {
  static final http.Client _client = http.Client();

  /// Il nome del file viene dall'indirizzo (es. 6983839.jpg): illustrazioni
  /// diverse della stessa carta hanno così file diversi.
  static String _fileName(String url, int ygoId) {
    final segment = Uri.tryParse(url)?.pathSegments.lastOrNull ?? '';
    final clean = segment.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '');
    if (clean.isEmpty || !clean.contains('.')) return '$ygoId.jpg';
    return clean;
  }

  static Future<String?> download(int ygoId, String? url) async {
    if (url == null || url.isEmpty) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory(p.join(dir.path, 'card_images'));
      if (!await folder.exists()) await folder.create(recursive: true);
      final file = File(p.join(folder.path, _fileName(url, ygoId)));
      if (await file.exists() && await file.length() > 0) return file.path;
      final res =
          await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
      await file.writeAsBytes(res.bodyBytes);
      return file.path;
    } catch (e) {
      DebugLog.add('Immagine $ygoId: $e');
      return null;
    }
  }
}
