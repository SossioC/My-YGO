import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../models/art_option.dart';
import '../models/card_hit.dart';
import '../models/card_info.dart';
import 'code_parser.dart';
import 'debug_log.dart';

class LookupResult {
  final CardInfo? card;
  final bool networkError;

  const LookupResult({this.card, this.networkError = false});
}

class _Page {
  final List<Map> data;
  final int total;
  const _Page(this.data, this.total);
}

class YgoApi {
  static final YgoApi instance = YgoApi();

  static const String _base = 'https://db.ygoprodeck.com/api/v7';
  static const int searchLimit = 30;

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

  /// Esegue una ricerca trasformando gli errori di rete in un risultato.
  Future<LookupResult> _guard(Future<LookupResult> Function() job) async {
    try {
      return await job();
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

  /// Cerca una carta dal codice del set (es. LOB-IT001).
  Future<LookupResult> lookup(ParsedCode code) => _guard(() async {
        int? id;
        for (final c in code.candidates) {
          final cached = _codeToId[c];
          if (cached != null) {
            id = cached;
            break;
          }
          final res = await _get(
              'cardsetsinfo.php?setcode=${Uri.encodeQueryComponent(c)}');
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
      });

  /// Cerca una carta dal numero a 8 cifre stampato sulla carta (passcode).
  Future<LookupResult> lookupById(int id) => _guard(() async {
        final card = _cards[id] ?? await _loadCard(id);
        return LookupResult(card: card);
      });

  Future<_Page> _searchOne(String path) async {
    final res = await _get(path);
    DebugLog.add('  -> ${res.statusCode}');
    if (res.statusCode != 200) return const _Page([], 0);
    final j = jsonDecode(res.body);
    final data = (j is Map && j['data'] is List)
        ? (j['data'] as List).whereType<Map>().toList()
        : <Map>[];
    final meta = j is Map ? j['meta'] : null;
    final total = (meta is Map && meta['total_rows'] is int)
        ? meta['total_rows'] as int
        : data.length;
    return _Page(data, total);
  }

  /// Cerca per nome (in inglese e in italiano) e unisce i risultati.
  Future<SearchResult> searchByName(String query) async {
    try {
      final q = Uri.encodeQueryComponent(query);
      final pages = await Future.wait([
        _searchOne('cardinfo.php?fname=$q&num=$searchLimit&offset=0'),
        _searchOne(
            'cardinfo.php?fname=$q&language=it&num=$searchLimit&offset=0'),
      ]);

      final hits = <int, CardHit>{};
      void absorb(_Page page, bool italian) {
        for (final d in page.data) {
          final id = d['id'];
          if (id is! int) continue;
          final name = (d['name'] as String?) ?? '';
          String? small;
          final images = d['card_images'];
          if (images is List && images.isNotEmpty) {
            small = (images.first as Map)['image_url_small'] as String?;
          }
          final prev = hits[id];
          hits[id] = CardHit(
            id: id,
            nameEn: italian ? prev?.nameEn : name,
            nameIt: italian ? name : prev?.nameIt,
            type: (d['type'] as String?) ?? prev?.type ?? '',
            imageSmallUrl: small ?? prev?.imageSmallUrl,
          );
        }
      }

      absorb(pages[0], false);
      absorb(pages[1], true);

      final list = hits.values.toList()
        ..sort((a, b) =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      return SearchResult(
        hits: list,
        total: math.max(pages[0].total, pages[1].total),
      );
    } on SocketException catch (e) {
      DebugLog.add('Rete: $e');
      return const SearchResult(networkError: true);
    } on TimeoutException {
      DebugLog.add('Rete: timeout');
      return const SearchResult(networkError: true);
    } on http.ClientException catch (e) {
      DebugLog.add('Rete: $e');
      return const SearchResult(networkError: true);
    } catch (e) {
      DebugLog.add('Errore ricerca per nome: $e');
      return const SearchResult();
    }
  }

  /// Elenco delle illustrazioni disponibili per una carta.
  Future<ArtResult> fetchImages(int ygoId) async {
    try {
      final res = await _get('cardinfo.php?id=$ygoId');
      DebugLog.add('  -> ${res.statusCode}');
      if (res.statusCode != 200) return const ArtResult();
      final j = jsonDecode(res.body);
      final data = (j is Map && j['data'] is List) ? j['data'] as List : [];
      if (data.isEmpty) return const ArtResult();
      final images = (data.first as Map)['card_images'];
      final out = <ArtOption>[];
      if (images is List) {
        for (final im in images) {
          if (im is! Map) continue;
          final id = im['id'];
          final url = im['image_url'];
          final small = im['image_url_small'];
          if (id is int && url is String) {
            out.add(ArtOption(
                imageId: id, url: url, smallUrl: (small as String?) ?? url));
          }
        }
      }
      return ArtResult(options: out);
    } on SocketException catch (e) {
      DebugLog.add('Rete: $e');
      return const ArtResult(networkError: true);
    } on TimeoutException {
      DebugLog.add('Rete: timeout');
      return const ArtResult(networkError: true);
    } on http.ClientException catch (e) {
      DebugLog.add('Rete: $e');
      return const ArtResult(networkError: true);
    } catch (e) {
      DebugLog.add('Errore illustrazioni: $e');
      return const ArtResult();
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
