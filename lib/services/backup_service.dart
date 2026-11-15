import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../data/card_repository.dart';

class BackupService {
  static final CardRepository _repo = CardRepository.instance;

  static String _stamp() {
    final n = DateTime.now();
    String t(int x) => x.toString().padLeft(2, '0');
    return '${n.year}${t(n.month)}${t(n.day)}_${t(n.hour)}${t(n.minute)}';
  }

  /// Salva un backup completo (carte e deck) in un file JSON scelto dall'utente.
  static Future<String> exportJson() async {
    final data = await _repo.exportData();
    final text = const JsonEncoder.withIndent('  ').convert(data);
    final saved = await FilePicker.saveFile(
      dialogTitle: 'Salva il backup',
      fileName: 'my_ygo_backup_${_stamp()}.json',
      bytes: Uint8List.fromList(utf8.encode(text)),
      mimeType: 'application/json',
    );
    if (saved == null) return 'Esportazione annullata.';
    final n = (data['cards'] as List).length;
    return 'Backup salvato: $n carte.';
  }

  static String _q(Object? v) {
    final s = (v ?? '').toString().replaceAll('"', '""');
    return '"$s"';
  }

  /// Salva la collezione come CSV (apribile con Excel). Solo per consultazione.
  static Future<String> exportCsv() async {
    final cards = await _repo.all();
    final labels = await _repo.deckLabels();
    final b = StringBuffer('\uFEFF');
    b.writeln([
      'Nome italiano',
      'Nome inglese',
      'Codice',
      'Copie IT',
      'Copie EN',
      'Tipo',
      'Attributo',
      'Razza',
      'Livello',
      'ATK',
      'DEF',
      'Descrizione italiana',
      'Descrizione inglese',
      'Note',
      'Deck',
    ].map(_q).join(';'));
    for (final c in cards) {
      b.writeln([
        c.nameIt,
        c.nameEn,
        c.code,
        c.qtyIt,
        c.qtyEn,
        c.type,
        c.attribute,
        c.race,
        c.level,
        c.atk,
        c.def,
        c.descIt,
        c.descEn,
        c.notes,
        labels[c.id] ?? '',
      ].map(_q).join(';'));
    }
    final saved = await FilePicker.saveFile(
      dialogTitle: 'Salva il file CSV',
      fileName: 'my_ygo_collezione_${_stamp()}.csv',
      bytes: Uint8List.fromList(utf8.encode(b.toString())),
      mimeType: 'text/csv',
    );
    if (saved == null) return 'Esportazione annullata.';
    return 'CSV salvato: ${cards.length} carte.';
  }

  /// Fa scegliere un file di backup e ne controlla il formato.
  /// Restituisce null se l'utente annulla; lancia FormatException se il file non è valido.
  static Future<Map<String, dynamic>?> pickBackup() async {
    final file = await FilePicker.pickFile(dialogTitle: 'Scegli il file di backup');
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final dynamic decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic> || decoded['format'] != 'my_ygo_backup') {
      throw const FormatException('Questo non è un file di backup di My YGO.');
    }
    if (decoded['cards'] is! List) {
      throw const FormatException('Il file di backup non contiene carte.');
    }
    return decoded;
  }

  static Future<List<int>> importData(Map<String, dynamic> data) =>
      _repo.importData(data);
}
