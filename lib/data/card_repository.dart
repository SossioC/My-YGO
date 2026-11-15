import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/card_info.dart';
import '../models/deck.dart';
import '../models/owned_card.dart';
import '../services/card_images.dart';

class CardRepository {
  CardRepository._();
  static final CardRepository instance = CardRepository._();

  Database? _db;
  bool _caching = false;

  /// Cresce ad ogni modifica: le schermate lo ascoltano per aggiornarsi.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  void _changed() => revision.value++;

  // ------------------------------------------------------------- database

  Future<Database> _open() async {
    final existing = _db;
    if (existing != null) return existing;
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, 'my_ygo.db'),
      version: 2,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createCards(db);
        await _createDecks(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createDecks(db);
      },
    );
    _db = db;
    return db;
  }

  Future<void> _createCards(Database db) async {
    await db.execute('''
      CREATE TABLE cards (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ygo_id INTEGER UNIQUE,
        name_it TEXT NOT NULL DEFAULT '',
        name_en TEXT NOT NULL DEFAULT '',
        code TEXT NOT NULL DEFAULT '',
        type TEXT NOT NULL DEFAULT '',
        attribute TEXT NOT NULL DEFAULT '',
        race TEXT NOT NULL DEFAULT '',
        level INTEGER,
        atk INTEGER,
        def INTEGER,
        desc_it TEXT NOT NULL DEFAULT '',
        desc_en TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        image_url TEXT,
        image_path TEXT,
        qty_it INTEGER NOT NULL DEFAULT 0,
        qty_en INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _createDecks(Database db) async {
    await db.execute('''
      CREATE TABLE decks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE deck_cards (
        deck_id INTEGER NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
        card_id INTEGER NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
        section TEXT NOT NULL,
        qty INTEGER NOT NULL,
        PRIMARY KEY (deck_id, card_id, section)
      )
    ''');
  }

  // ---------------------------------------------------------------- carte

  /// Aggiunge una copia (IT o EN) di una carta trovata online.
  Future<OwnedCard> addCopy(CardInfo info, String lang, String code) async {
    final db = await _open();
    final rows = await db.query('cards',
        where: 'ygo_id = ?', whereArgs: [info.id], limit: 1);
    final now = DateTime.now().millisecondsSinceEpoch;
    OwnedCard card;
    if (rows.isNotEmpty) {
      card = OwnedCard.fromMap(rows.first);
      if (lang == 'it') {
        card.qtyIt++;
      } else {
        card.qtyEn++;
      }
      if (card.nameIt.isEmpty && (info.nameIt ?? '').isNotEmpty) {
        card.nameIt = info.nameIt!;
      }
      if (card.descIt.isEmpty && (info.descIt ?? '').isNotEmpty) {
        card.descIt = info.descIt!;
      }
      card.updatedAt = now;
      await db.update('cards', card.toMap(),
          where: 'id = ?', whereArgs: [card.id]);
    } else {
      card = OwnedCard(
        ygoId: info.id,
        nameIt: info.nameIt ?? '',
        nameEn: info.nameEn,
        code: code,
        type: info.type,
        attribute: info.attribute ?? '',
        race: info.race ?? '',
        level: info.level,
        atk: info.atk,
        def: info.def,
        descIt: info.descIt ?? '',
        descEn: info.descEn ?? '',
        imageUrl: info.imageUrl ?? info.imageSmallUrl,
        qtyIt: lang == 'it' ? 1 : 0,
        qtyEn: lang == 'en' ? 1 : 0,
        createdAt: now,
        updatedAt: now,
      );
      card.id = await db.insert('cards', card.toMap());
    }
    _changed();
    return card;
  }

  /// Toglie una copia. Se non ne restano, la carta viene eliminata.
  /// Restituisce la carta aggiornata, oppure null se è stata eliminata.
  Future<OwnedCard?> removeCopy(int id, String lang) async {
    final db = await _open();
    final rows =
        await db.query('cards', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final card = OwnedCard.fromMap(rows.first);
    if (lang == 'it' && card.qtyIt > 0) {
      card.qtyIt--;
    } else if (lang == 'en' && card.qtyEn > 0) {
      card.qtyEn--;
    }
    OwnedCard? result = card;
    if (card.totalQty <= 0) {
      await db.delete('cards', where: 'id = ?', whereArgs: [id]);
      result = null;
    } else {
      card.updatedAt = DateTime.now().millisecondsSinceEpoch;
      await db.update('cards', card.toMap(),
          where: 'id = ?', whereArgs: [id]);
      await _clampDecks(db, id, card.totalQty);
    }
    _changed();
    return result;
  }

  Future<List<OwnedCard>> all({String query = ''}) async {
    final db = await _open();
    final q = query.trim();
    final rows = await db.query(
      'cards',
      where: q.isEmpty ? null : 'name_it LIKE ? OR name_en LIKE ? OR code LIKE ?',
      whereArgs: q.isEmpty ? null : ['%$q%', '%$q%', '%$q%'],
      orderBy:
          "LOWER(CASE WHEN name_it != '' THEN name_it ELSE name_en END)",
    );
    return rows.map(OwnedCard.fromMap).toList();
  }

  Future<OwnedCard?> findByYgoId(int ygoId) async {
    final db = await _open();
    final rows = await db.query('cards',
        where: 'ygo_id = ?', whereArgs: [ygoId], limit: 1);
    return rows.isEmpty ? null : OwnedCard.fromMap(rows.first);
  }

  /// [numero di carte diverse, numero totale di copie]
  Future<List<int>> stats() async {
    final db = await _open();
    final r = await db.rawQuery(
        'SELECT COUNT(*) AS n, COALESCE(SUM(qty_it + qty_en), 0) AS c FROM cards');
    final row = r.first;
    return [(row['n'] as int?) ?? 0, (row['c'] as int?) ?? 0];
  }

  /// Salva una carta (nuova o esistente) e restituisce il suo id.
  Future<int> save(OwnedCard card) async {
    final db = await _open();
    card.updatedAt = DateTime.now().millisecondsSinceEpoch;
    if (card.id == null) {
      card.id = await db.insert('cards', card.toMap());
    } else {
      await db.update('cards', card.toMap(),
          where: 'id = ?', whereArgs: [card.id]);
      await _clampDecks(db, card.id!, card.totalQty);
    }
    _changed();
    return card.id!;
  }

  Future<void> delete(int id) async {
    final db = await _open();
    await db.delete('cards', where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<void> setImagePath(int id, String path) async {
    final db = await _open();
    await db.update('cards', {'image_path': path},
        where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  /// Aggiunge copie a una carta già presente.
  Future<void> addQuantities(int targetId, int it, int en) async {
    final db = await _open();
    await db.rawUpdate(
      'UPDATE cards SET qty_it = qty_it + ?, qty_en = qty_en + ?, updated_at = ? WHERE id = ?',
      [it, en, DateTime.now().millisecondsSinceEpoch, targetId],
    );
    _changed();
  }

  /// Unisce la carta [sourceId] in [targetId]: somma le copie e i deck, poi elimina la prima.
  Future<void> mergeCards(
      {required int sourceId, required int targetId}) async {
    final db = await _open();
    await db.transaction((txn) async {
      final s = await txn
          .query('cards', where: 'id = ?', whereArgs: [sourceId], limit: 1);
      final t = await txn
          .query('cards', where: 'id = ?', whereArgs: [targetId], limit: 1);
      if (s.isEmpty || t.isEmpty) return;
      final source = OwnedCard.fromMap(s.first);
      final target = OwnedCard.fromMap(t.first);
      target.qtyIt += source.qtyIt;
      target.qtyEn += source.qtyEn;
      target.updatedAt = DateTime.now().millisecondsSinceEpoch;
      await txn.update('cards', target.toMap(),
          where: 'id = ?', whereArgs: [targetId]);

      final rows = await txn
          .query('deck_cards', where: 'card_id = ?', whereArgs: [sourceId]);
      for (final r in rows) {
        final deckId = r['deck_id'] as int;
        final section = r['section'] as String;
        final qty = r['qty'] as int;
        final ex = await txn.query('deck_cards',
            where: 'deck_id = ? AND card_id = ? AND section = ?',
            whereArgs: [deckId, targetId, section]);
        if (ex.isNotEmpty) {
          await txn.update(
              'deck_cards', {'qty': (ex.first['qty'] as int) + qty},
              where: 'deck_id = ? AND card_id = ? AND section = ?',
              whereArgs: [deckId, targetId, section]);
        } else {
          await txn.update('deck_cards', {'card_id': targetId},
              where: 'deck_id = ? AND card_id = ? AND section = ?',
              whereArgs: [deckId, sourceId, section]);
        }
      }
      await txn.delete('cards', where: 'id = ?', whereArgs: [sourceId]);
      await _clampDecks(txn, targetId, target.totalQty);
    });
    _changed();
  }

  // ----------------------------------------------------------------- deck

  /// Riduce le copie nei deck se superano il totale posseduto (prima Side, poi Main, poi Extra).
  Future<void> _clampDecks(DatabaseExecutor db, int cardId, int total) async {
    final over = await db.rawQuery(
      'SELECT deck_id, SUM(qty) AS used FROM deck_cards WHERE card_id = ? GROUP BY deck_id HAVING SUM(qty) > ?',
      [cardId, total],
    );
    for (final r in over) {
      var excess = (r['used'] as int) - total;
      final deckId = r['deck_id'] as int;
      for (final section in [kSide, kMain, kExtra]) {
        if (excess <= 0) break;
        final rows = await db.query('deck_cards',
            where: 'deck_id = ? AND card_id = ? AND section = ?',
            whereArgs: [deckId, cardId, section]);
        if (rows.isEmpty) continue;
        final q = rows.first['qty'] as int;
        final take = q < excess ? q : excess;
        if (q - take <= 0) {
          await db.delete('deck_cards',
              where: 'deck_id = ? AND card_id = ? AND section = ?',
              whereArgs: [deckId, cardId, section]);
        } else {
          await db.update('deck_cards', {'qty': q - take},
              where: 'deck_id = ? AND card_id = ? AND section = ?',
              whereArgs: [deckId, cardId, section]);
        }
        excess -= take;
      }
    }
  }

  /// Quanti deck dovrebbero ridurre le copie se la carta passasse a [newTotal] copie.
  Future<int> decksOverLimit(int cardId, int newTotal) async {
    final db = await _open();
    final over = await db.rawQuery(
      'SELECT deck_id FROM deck_cards WHERE card_id = ? GROUP BY deck_id HAVING SUM(qty) > ?',
      [cardId, newTotal],
    );
    return over.length;
  }

  Future<List<DeckSummary>> decks() async {
    final db = await _open();
    final rows = await db.rawQuery('''
      SELECT d.id AS id, d.name AS name,
        COALESCE(SUM(CASE WHEN dc.section = 'main' THEN dc.qty END), 0) AS m,
        COALESCE(SUM(CASE WHEN dc.section = 'extra' THEN dc.qty END), 0) AS e,
        COALESCE(SUM(CASE WHEN dc.section = 'side' THEN dc.qty END), 0) AS s
      FROM decks d LEFT JOIN deck_cards dc ON dc.deck_id = d.id
      GROUP BY d.id
      ORDER BY LOWER(d.name)
    ''');
    return rows
        .map((r) => DeckSummary(
              id: r['id'] as int,
              name: r['name'] as String,
              main: (r['m'] as int?) ?? 0,
              extra: (r['e'] as int?) ?? 0,
              side: (r['s'] as int?) ?? 0,
            ))
        .toList();
  }

  Future<int> createDeck(String name) async {
    final db = await _open();
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.insert(
        'decks', {'name': name, 'created_at': now, 'updated_at': now});
    _changed();
    return id;
  }

  Future<void> renameDeck(int id, String name) async {
    final db = await _open();
    await db.update('decks',
        {'name': name, 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<void> deleteDeck(int id) async {
    final db = await _open();
    await db.delete('decks', where: 'id = ?', whereArgs: [id]);
    _changed();
  }

  Future<String?> deckName(int id) async {
    final db = await _open();
    final rows = await db.query('decks',
        columns: ['name'], where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first['name'] as String;
  }

  Future<List<DeckEntry>> deckCards(int deckId) async {
    final db = await _open();
    final rows = await db.rawQuery('''
      SELECT c.*, dc.section AS dc_section, dc.qty AS dc_qty
      FROM deck_cards dc JOIN cards c ON c.id = dc.card_id
      WHERE dc.deck_id = ?
      ORDER BY LOWER(CASE WHEN c.name_it != '' THEN c.name_it ELSE c.name_en END)
    ''', [deckId]);
    return rows
        .map((r) => DeckEntry(
            OwnedCard.fromMap(r), r['dc_section'] as String, r['dc_qty'] as int))
        .toList();
  }

  /// Cambia di [delta] le copie di una carta in una sezione del deck.
  /// Restituisce false se si supererebbero le copie possedute.
  Future<bool> changeDeckQty(
      int deckId, OwnedCard card, String section, int delta) async {
    final cardId = card.id;
    if (cardId == null) return false;
    final db = await _open();
    var ok = true;
    await db.transaction((txn) async {
      final total = Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT qty_it + qty_en FROM cards WHERE id = ?', [cardId])) ??
          0;
      final used = Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT COALESCE(SUM(qty), 0) FROM deck_cards WHERE deck_id = ? AND card_id = ?',
              [deckId, cardId])) ??
          0;
      final rows = await txn.query('deck_cards',
          where: 'deck_id = ? AND card_id = ? AND section = ?',
          whereArgs: [deckId, cardId, section]);
      final cur = rows.isEmpty ? 0 : rows.first['qty'] as int;
      if (delta > 0 && used + delta > total) {
        ok = false;
        return;
      }
      final next = cur + delta;
      if (next <= 0) {
        if (rows.isNotEmpty) {
          await txn.delete('deck_cards',
              where: 'deck_id = ? AND card_id = ? AND section = ?',
              whereArgs: [deckId, cardId, section]);
        }
      } else if (rows.isEmpty) {
        await txn.insert('deck_cards', {
          'deck_id': deckId,
          'card_id': cardId,
          'section': section,
          'qty': next,
        });
      } else {
        await txn.update('deck_cards', {'qty': next},
            where: 'deck_id = ? AND card_id = ? AND section = ?',
            whereArgs: [deckId, cardId, section]);
      }
      await txn.rawUpdate('UPDATE decks SET updated_at = ? WHERE id = ?',
          [DateTime.now().millisecondsSinceEpoch, deckId]);
    });
    if (ok) _changed();
    return ok;
  }

  /// Sposta una copia da una sezione all'altra (Main <-> Side).
  Future<void> moveInDeck(
      int deckId, int cardId, String from, String to) async {
    final db = await _open();
    await db.transaction((txn) async {
      final src = await txn.query('deck_cards',
          where: 'deck_id = ? AND card_id = ? AND section = ?',
          whereArgs: [deckId, cardId, from]);
      if (src.isEmpty) return;
      final q = src.first['qty'] as int;
      if (q <= 1) {
        await txn.delete('deck_cards',
            where: 'deck_id = ? AND card_id = ? AND section = ?',
            whereArgs: [deckId, cardId, from]);
      } else {
        await txn.update('deck_cards', {'qty': q - 1},
            where: 'deck_id = ? AND card_id = ? AND section = ?',
            whereArgs: [deckId, cardId, from]);
      }
      final dst = await txn.query('deck_cards',
          where: 'deck_id = ? AND card_id = ? AND section = ?',
          whereArgs: [deckId, cardId, to]);
      if (dst.isEmpty) {
        await txn.insert('deck_cards', {
          'deck_id': deckId,
          'card_id': cardId,
          'section': to,
          'qty': 1,
        });
      } else {
        await txn.update('deck_cards', {'qty': (dst.first['qty'] as int) + 1},
            where: 'deck_id = ? AND card_id = ? AND section = ?',
            whereArgs: [deckId, cardId, to]);
      }
    });
    _changed();
  }

  Future<List<DeckUse>> decksForCard(int cardId) async {
    final db = await _open();
    final rows = await db.rawQuery('''
      SELECT d.id AS id, d.name AS name,
        SUM(CASE WHEN dc.section = 'main' THEN dc.qty ELSE 0 END) AS m,
        SUM(CASE WHEN dc.section = 'extra' THEN dc.qty ELSE 0 END) AS e,
        SUM(CASE WHEN dc.section = 'side' THEN dc.qty ELSE 0 END) AS s
      FROM deck_cards dc JOIN decks d ON d.id = dc.deck_id
      WHERE dc.card_id = ?
      GROUP BY d.id
      ORDER BY LOWER(d.name)
    ''', [cardId]);
    return rows
        .map((r) => DeckUse(
              deckId: r['id'] as int,
              name: r['name'] as String,
              main: (r['m'] as int?) ?? 0,
              extra: (r['e'] as int?) ?? 0,
              side: (r['s'] as int?) ?? 0,
            ))
        .toList();
  }

  /// Per il CSV: per ogni carta, i deck in cui compare.
  Future<Map<int, String>> deckLabels() async {
    final db = await _open();
    final rows = await db.rawQuery('''
      SELECT dc.card_id AS card_id, d.name AS name, SUM(dc.qty) AS q
      FROM deck_cards dc JOIN decks d ON d.id = dc.deck_id
      GROUP BY dc.card_id, d.id
      ORDER BY LOWER(d.name)
    ''');
    final map = <int, List<String>>{};
    for (final r in rows) {
      map
          .putIfAbsent(r['card_id'] as int, () => [])
          .add('${r['name']} (${r['q']})');
    }
    return map.map((k, v) => MapEntry(k, v.join('; ')));
  }

  // --------------------------------------------------------------- backup

  Future<Map<String, Object?>> exportData() async {
    final db = await _open();
    final cards = await db.query('cards', orderBy: 'id');
    final decks = await db.query('decks', orderBy: 'id');
    final dcs = await db.query('deck_cards');
    return {
      'format': 'my_ygo_backup',
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'cards': cards.map((r) {
        final m = Map<String, Object?>.from(r);
        m.remove('image_path');
        return m;
      }).toList(),
      'decks': decks
          .map((d) => {
                'id': d['id'],
                'name': d['name'],
                'cards': dcs
                    .where((r) => r['deck_id'] == d['id'])
                    .map((r) => {
                          'card': r['card_id'],
                          'section': r['section'],
                          'qty': r['qty'],
                        })
                    .toList(),
              })
          .toList(),
    };
  }

  /// Sostituisce tutta la collezione e i deck con quelli del backup.
  /// Restituisce [carte importate, deck importati].
  Future<List<int>> importData(Map<String, dynamic> data) async {
    final cards = data['cards'];
    if (cards is! List) throw const FormatException('Il file non contiene carte.');
    final decks = (data['decks'] is List) ? data['decks'] as List : <dynamic>[];
    final db = await _open();
    var nCards = 0;
    var nDecks = 0;
    await db.transaction((txn) async {
      await txn.delete('deck_cards');
      await txn.delete('decks');
      await txn.delete('cards');

      final ids = <int>{};
      for (final c in cards) {
        if (c is! Map) continue;
        final card = OwnedCard.fromMap(Map<String, Object?>.from(c));
        if (card.id == null) continue;
        card.imagePath = null;
        await txn.insert('cards', card.toMap());
        ids.add(card.id!);
        nCards++;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      for (final d in decks) {
        if (d is! Map) continue;
        final deckId = d['id'];
        final name = d['name'];
        if (deckId is! int || name is! String) continue;
        await txn.insert('decks',
            {'id': deckId, 'name': name, 'created_at': now, 'updated_at': now});
        nDecks++;
        final list = d['cards'];
        if (list is! List) continue;
        for (final r in list) {
          if (r is! Map) continue;
          final cardId = r['card'];
          final section = r['section'];
          final qty = r['qty'];
          if (cardId is! int || !ids.contains(cardId)) continue;
          if (section != kMain && section != kExtra && section != kSide) continue;
          if (qty is! int || qty <= 0) continue;
          await txn.insert(
            'deck_cards',
            {
              'deck_id': deckId,
              'card_id': cardId,
              'section': section,
              'qty': qty,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
    _changed();
    return [nCards, nDecks];
  }

  /// Scarica le immagini mancanti (dopo un import o un reinstall).
  Future<void> cacheMissingImages() async {
    if (_caching) return;
    _caching = true;
    try {
      final db = await _open();
      final rows = await db.query('cards',
          columns: ['id', 'ygo_id', 'image_url', 'image_path'],
          where: 'ygo_id IS NOT NULL AND image_url IS NOT NULL');
      var updated = false;
      for (final r in rows) {
        final path = r['image_path'] as String?;
        if (path != null && File(path).existsSync()) continue;
        final got = await CardImages.download(
            r['ygo_id'] as int, r['image_url'] as String?);
        if (got != null) {
          await db.update('cards', {'image_path': got},
              where: 'id = ?', whereArgs: [r['id']]);
          updated = true;
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      if (updated) _changed();
    } catch (_) {
      // riproverà alla prossima apertura
    } finally {
      _caching = false;
    }
  }
}
