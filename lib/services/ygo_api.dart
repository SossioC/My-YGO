import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/card_info.dart';
import 'code_parser.dart';
import 'debug_log.dart';

class LookupResult {
  final CardInfo? card;
  final bool networkError;

  const LookupResult({this.card, this.networkError = false});
}

class YgoApi {
  static const String _base = 'https://db.ygoprodeck.com/api/v7';

  final http.Client _client = http.Client();
  final Map<String, int> _codeToId = {};
  final Map<int, CardInfo> _cards = {};

  Future<http.Response> _get(String path) {
    DebugLog.add('GET $path');
    return _client
        .get(Uri.parse('$_base/$path'))
        .timeout(const Duration(seconds: 10));
  }

  int? _extractId(dynamic j) {
    if (j is List && j.isNotEmpty) return _extractId(j.first);
    if (j is Map) {
      if (j.containsKey('error')) return null;
      if (j['data'] is List) return _extractId(j['data']);
      final v = j['id'];
      if (v is int) return v;
      if (v is String) return int.tryParse(v);
    }
    return null;
  }

  int? _int(dynamic v) => v is int ? v : null;

  String _short(String s) => s.length > 110 ? '${s.substring(0, 110)}...' : s;

  Future<LookupResult> lookup(ParsedCode code) async {
    try {
      int? id;
      for (final c in code.candidates) {
        final cached = _codeToId[c];
        if (cached != null) {
          id = cached;
          break;
        }
        final res =
            await _get('cardsetsinfo.php?setcode=${Uri.encodeQueryComponent(c)}');
        DebugLog.add('  -> ${res.statusCode} ${_short(res.body)}');
        if (res.statusCode == 200) {
          final found = _extractId(jsonDecode(res.body));
          if (found != null) {
            id = found;
            _codeToId[c] = found;
            break;
          }
        }
      }
      if (id == null) return const LookupResult();

      final card = _cards[id] ?? await _loadCard(id);
      return LookupResult(card: card);
    } on SocketException catch (e) {
      DebugLog.add('Rete: $e');
      return const LookupResult(networkError: true);
    } on TimeoutException {
      DebugLog.add('Rete: timeout');
      return const LookupResult(networkError: true);
    } on http.ClientException catch (e) {
      DebugLog.add('Rete: $e');
      return const LookupResult(networkError: true);
    } catch (e) {
      DebugLog.add('Errore ricerca: $e');
      return const LookupResult();
    }
  }

  Future<CardInfo?> _loadCard(int id) async {
    final en = await _get('cardinfo.php?id=$id');
    DebugLog.add('  -> ${en.statusCode}');
    if (en.statusCode != 200) return null;
    final enData =
        (jsonDecode(en.body)['data'] as List).first as Map<String, dynamic>;

    String? nameIt;
    String? descIt;
    try {
      final it = await _get('cardinfo.php?id=$id&language=it');
      DebugLog.add('  -> IT ${it.statusCode} ${_short(it.body)}');
      if (it.statusCode == 200) {
        final d =
            (jsonDecode(it.body)['data'] as List).first as Map<String, dynamic>;
        nameIt = d['name'] as String?;
        descIt = d['desc'] as String?;
      }
    } catch (e) {
      DebugLog.add('Italiano non disponibile: $e');
    }

    String? image;
    String? imageSmall;
    final images = enData['card_images'];
    if (images is List && images.isNotEmpty) {
      final first = images.first as Map;
      image = first['image_url'] as String?;
      imageSmall = first['image_url_small'] as String?;
    }

    final card = CardInfo(
      id: id,
      nameEn: enData['name'] as String? ?? '',
      nameIt: nameIt,
      type: enData['type'] as String? ?? '',
      attribute: enData['attribute'] as String?,
      race: enData['race'] as String?,
      level: _int(enData['level']),
      atk: _int(enData['atk']),
      def: _int(enData['def']),
      descEn: enData['desc'] as String?,
      descIt: descIt,
      imageUrl: image,
      imageSmallUrl: imageSmall,
    );
    _cards[id] = card;
    return card;
  }
}
