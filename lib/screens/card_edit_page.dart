import 'dart:async';

import 'package:flutter/material.dart';

import '../data/card_repository.dart';
import '../models/card_info.dart';
import '../models/deck.dart';
import '../models/owned_card.dart';
import '../services/code_parser.dart';
import '../services/ygo_api.dart';
import '../theme.dart';
import '../widgets/card_thumb.dart';

/// Modifica una carta esistente, oppure ne crea una a mano.
class CardEditPage extends StatefulWidget {
  final OwnedCard? card;
  final String? prefillCode;

  const CardEditPage({super.key, this.card, this.prefillCode});

  @override
  State<CardEditPage> createState() => _CardEditPageState();
}

class _CardEditPageState extends State<CardEditPage> {
  final _repo = CardRepository.instance;

  late final TextEditingController _nameIt;
  late final TextEditingController _nameEn;
  late final TextEditingController _code;
  late final TextEditingController _type;
  late final TextEditingController _attribute;
  late final TextEditingController _race;
  late final TextEditingController _level;
  late final TextEditingController _atk;
  late final TextEditingController _def;
  late final TextEditingController _descIt;
  late final TextEditingController _descEn;
  late final TextEditingController _notes;
  late int _qtyIt;
  late int _qtyEn;

  int? _ygoId;
  String? _imageUrl;
  String? _imagePath;
  bool _searching = false;
  bool _saving = false;
  bool _searchedOnce = false;
  String? _lookupProblem;
  List<DeckUse> _deckUses = [];

  bool get _isNew => widget.card == null;

  @override
  void initState() {
    super.initState();
    final c = widget.card;
    _nameIt = TextEditingController(text: c?.nameIt ?? '');
    _nameEn = TextEditingController(text: c?.nameEn ?? '');
    _code = TextEditingController(text: c?.code ?? widget.prefillCode ?? '');
    _type = TextEditingController(text: c?.type ?? '');
    _attribute = TextEditingController(text: c?.attribute ?? '');
    _race = TextEditingController(text: c?.race ?? '');
    _level = TextEditingController(text: c?.level?.toString() ?? '');
    _atk = TextEditingController(text: c?.atk?.toString() ?? '');
    _def = TextEditingController(text: c?.def?.toString() ?? '');
    _descIt = TextEditingController(text: c?.descIt ?? '');
    _descEn = TextEditingController(text: c?.descEn ?? '');
    _notes = TextEditingController(text: c?.notes ?? '');
    _qtyIt = c?.qtyIt ?? 1;
    _qtyEn = c?.qtyEn ?? 0;
    _ygoId = c?.ygoId;
    _imageUrl = c?.imageUrl;
    _imagePath = c?.imagePath;
    if (c?.id != null) _loadDecks(c!.id!);
  }

  Future<void> _loadDecks(int id) async {
    final uses = await _repo.decksForCard(id);
    if (mounted) setState(() => _deckUses = uses);
  }

  @override
  void dispose() {
    for (final c in [
      _nameIt,
      _nameEn,
      _code,
      _type,
      _attribute,
      _race,
      _level,
      _atk,
      _def,
      _descIt,
      _descEn,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ------------------------------------------------------- ricerca online

  /// Cerca la carta online dal codice. Imposta [_lookupProblem] se non la trova.
  Future<CardInfo?> _lookup(String text) async {
    _lookupProblem = null;
    final codes = CodeParser.findAll(text);
    if (codes.isEmpty) {
      _lookupProblem =
          'Codice non riconosciuto. Il formato è tipo LOB-IT001 o RA01-EN012.';
      return null;
    }
    final res = await YgoApi.instance.lookup(codes.first);
    if (res.networkError) {
      _lookupProblem = 'Nessuna connessione: ricerca online non riuscita.';
      return null;
    }
    if (res.card == null) {
      _lookupProblem = 'Nessuna carta trovata con il codice ${codes.first.raw}.';
      return null;
    }
    return res.card;
  }

  void _put(TextEditingController c, String? v, bool overwrite) {
    if (v == null || v.isEmpty) return;
    if (overwrite || c.text.trim().isEmpty) c.text = v;
  }

  void _putInt(TextEditingController c, int? v, bool overwrite) {
    if (v == null) return;
    if (overwrite || c.text.trim().isEmpty) c.text = v.toString();
  }

  /// Compila i campi con i dati online. Con [overwrite] sostituisce anche quelli già scritti.
  /// Se online manca un dato (es. il nome italiano), quello scritto a mano resta.
  void _applyInfo(CardInfo info, {required bool overwrite}) {
    setState(() {
      _put(_nameIt, info.nameIt, overwrite);
      _put(_nameEn, info.nameEn, overwrite);
      _put(_type, info.type, overwrite);
      _put(_attribute, info.attribute, overwrite);
      _put(_race, info.race, overwrite);
      _put(_descIt, info.descIt, overwrite);
      _put(_descEn, info.descEn, overwrite);
      _putInt(_level, info.level, overwrite);
      _putInt(_atk, info.atk, overwrite);
      _putInt(_def, info.def, overwrite);
      _ygoId = info.id;
      _imageUrl = info.imageUrl ?? info.imageSmallUrl;
      _imagePath = null;
    });
  }

  /// Se la carta trovata è già in collezione, propone di unire le copie.
  /// Restituisce true se l'operazione è stata gestita (unione o annullamento).
  Future<bool> _handleDuplicate(CardInfo info) async {
    final existing = await _repo.findByYgoId(info.id);
    if (existing == null || existing.id == widget.card?.id) return false;
    if (!mounted) return true;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final merge = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Carta già in collezione'),
        content: Text(
          '"${existing.displayName}" è già presente (IT ×${existing.qtyIt}, EN ×${existing.qtyEn}).\n\nVuoi aggiungere le copie di questa scheda a quella carta?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annulla')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Unisci')),
        ],
      ),
    );
    if (merge != true) return true;

    if (widget.card?.id != null) {
      final c = _collect();
      await _repo.save(c);
      await _repo.mergeCards(sourceId: c.id!, targetId: existing.id!);
    } else {
      await _repo.addQuantities(existing.id!, _qtyIt, _qtyEn);
    }
    messenger.showSnackBar(SnackBar(
        content: Text('Copie aggiunte a "${existing.displayName}".')));
    navigator.pop();
    return true;
  }

  Future<void> _searchOnline() async {
    final text = _code.text.trim();
    if (text.isEmpty) {
      _snack('Scrivi prima il codice della carta.');
      return;
    }
    setState(() => _searching = true);
    final info = await _lookup(text);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _searchedOnce = true;
    });
    if (info == null) {
      _snack(_lookupProblem ?? 'Carta non trovata.');
      return;
    }
    if (await _handleDuplicate(info)) return;
    _applyInfo(info, overwrite: true);
    _snack('Carta trovata: dati compilati.');
  }

  // --------------------------------------------------------------- salvataggio

  OwnedCard _collect() {
    final c = widget.card ?? OwnedCard();
    c.nameIt = _nameIt.text.trim();
    c.nameEn = _nameEn.text.trim();
    c.code = _code.text.trim().toUpperCase();
    c.type = _type.text.trim();
    c.attribute = _attribute.text.trim();
    c.race = _race.text.trim();
    c.level = int.tryParse(_level.text.trim());
    c.atk = int.tryParse(_atk.text.trim());
    c.def = int.tryParse(_def.text.trim());
    c.descIt = _descIt.text.trim();
    c.descEn = _descEn.text.trim();
    c.notes = _notes.text.trim();
    c.qtyIt = _qtyIt;
    c.qtyEn = _qtyEn;
    c.ygoId = _ygoId;
    c.imageUrl = _imageUrl;
    c.imagePath = _imagePath;
    return c;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_nameIt.text.trim().isEmpty && _nameEn.text.trim().isEmpty) {
      _snack('Inserisci almeno un nome (italiano o inglese).');
      return;
    }
    if (_qtyIt + _qtyEn <= 0) {
      _snack('La carta deve avere almeno una copia. Per toglierla usa il cestino.');
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    String? finalNote;

    try {
      // Se c'è un codice e la carta non è ancora collegata, prova la ricerca
      // (in questo caso compila solo i campi rimasti vuoti).
      final code = _code.text.trim();
      if (_ygoId == null && code.isNotEmpty && !_searchedOnce) {
        final found = await _lookup(code);
        if (!mounted) return;
        if (found != null) {
          if (await _handleDuplicate(found)) return;
          _applyInfo(found, overwrite: false);
          finalNote = 'Carta collegata al database online.';
        } else {
          finalNote = '${_lookupProblem ?? 'Ricerca online non riuscita.'} Salvata con i dati inseriti.';
        }
      }

      // Se si riducono le copie sotto quelle usate nei deck, chiedi conferma.
      final id = widget.card?.id;
      if (id != null) {
        final over = await _repo.decksOverLimit(id, _qtyIt + _qtyEn);
        if (over > 0) {
          if (!mounted) return;
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Copie usate nei deck'),
              content: Text(
                  'In $over deck questa carta è usata con più copie di quelle che ti restano. Le copie in eccesso verranno tolte dai deck (prima dal Side). Continuare?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Annulla')),
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Continua')),
              ],
            ),
          );
          if (ok != true) return;
        }
      }

      await _repo.save(_collect());
      unawaited(_repo.cacheMissingImages());
      if (finalNote != null) {
        messenger.showSnackBar(SnackBar(content: Text(finalNote)));
      }
      navigator.pop();
    } catch (e) {
      if (mounted) _snack('Errore nel salvataggio: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare la carta?'),
        content: const Text(
            'La carta, tutte le sue copie e la sua presenza nei deck verranno eliminate.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annulla')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Elimina')),
        ],
      ),
    );
    if (ok == true && widget.card?.id != null) {
      await _repo.delete(widget.card!.id!);
      if (mounted) Navigator.of(context).pop();
    }
  }

  // ------------------------------------------------------------------- UI

  Widget _field(TextEditingController c, String label,
      {int maxLines = 1, bool number = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        minLines: 1,
        keyboardType: number
            ? TextInputType.number
            : (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _qtyRow(String label, int value, void Function(int) onChanged) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value > 0 ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 32,
          child: Text('$value',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.gold)),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => onChanged(value + 1),
        ),
      ],
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(t,
            style: const TextStyle(
                color: AppColors.gold,
                fontWeight: FontWeight.bold,
                letterSpacing: 1)),
      );

  Widget _codeRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Codice (es. LOB-IT001)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 40,
            child: FilledButton.tonalIcon(
              onPressed: _searching ? null : _searchOnline,
              icon: _searching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.travel_explore, size: 18),
              label: const Text('Cerca online'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = (_imagePath != null) || (_imageUrl != null);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Nuova carta' : 'Modifica carta'),
        actions: [
          if (!_isNew)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Elimina',
              onPressed: _delete,
            ),
          IconButton(
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            tooltip: 'Salva',
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (hasImage)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: CardThumb(
                    path: _imagePath,
                    url: _imageUrl,
                    width: 130,
                    height: 190),
              ),
            ),
          _sectionTitle('CODICE'),
          _codeRow(),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _ygoId != null
                  ? 'Collegata al database online. "Cerca online" sostituisce i campi con i dati trovati.'
                  : 'Con "Cerca online" i dati trovati sostituiscono quelli che hai scritto. Se non premi il pulsante, alla pressione di Salva la ricerca parte da sola e compila solo i campi vuoti.',
              style: const TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          ),
          _sectionTitle('NOMI'),
          _field(_nameIt, 'Nome italiano'),
          _field(_nameEn, 'Nome inglese'),
          _sectionTitle('COPIE POSSEDUTE'),
          _qtyRow('Copie in italiano', _qtyIt, (v) => setState(() => _qtyIt = v)),
          _qtyRow('Copie in inglese', _qtyEn, (v) => setState(() => _qtyEn = v)),
          _sectionTitle('CARATTERISTICHE'),
          _field(_type, 'Tipo (es. Effect Monster)'),
          _field(_attribute, 'Attributo'),
          _field(_race, 'Razza / tipo di mostro'),
          Row(
            children: [
              Expanded(child: _field(_level, 'Livello', number: true)),
              const SizedBox(width: 8),
              Expanded(child: _field(_atk, 'ATK', number: true)),
              const SizedBox(width: 8),
              Expanded(child: _field(_def, 'DEF', number: true)),
            ],
          ),
          _field(_descIt, 'Descrizione italiana', maxLines: 8),
          _field(_descEn, 'Descrizione inglese', maxLines: 8),
          _field(_notes, 'Note', maxLines: 4),
          _sectionTitle('PRESENTE NEI DECK'),
          if (_deckUses.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 24),
              child: Text('Questa carta non è in nessun deck.',
                  style: TextStyle(color: AppColors.textDim)),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                children: [
                  for (final u in _deckUses)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(u.name),
                      subtitle: Text(
                          'Main ${u.main}  ·  Extra ${u.extra}  ·  Side ${u.side}'),
                      trailing: Text('×${u.total}',
                          style: const TextStyle(
                              color: AppColors.gold,
                              fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
