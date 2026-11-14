import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/card_info.dart';
import '../models/owned_card.dart';

class CardRepository {
  CardRepository._();
  static final CardRepository instance = CardRepository._();

  Database? _db;

  /// Cresce ad ogni modifica: le schermate lo ascoltano per aggiornarsi.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Future<Database> _open() async {
    final existing = _db;
    if (existing != null) return existing;
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, 'my_ygo.db'),
      version: 1,
      onCreate: (db, version) async {
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
      },
    );
    _db = db;
    return db;
  }

  void _changed() => revision.value++;

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
}
