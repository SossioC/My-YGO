import 'package:flutter/material.dart';

import '../data/card_repository.dart';
import '../models/owned_card.dart';
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

  Future<void> _save() async {
    final nameIt = _nameIt.text.trim();
    final nameEn = _nameEn.text.trim();
    if (nameIt.isEmpty && nameEn.isEmpty) {
      _snack('Inserisci almeno un nome (italiano o inglese).');
      return;
    }
    if (_qtyIt + _qtyEn <= 0) {
      _snack('La carta deve avere almeno una copia. Per toglierla usa il cestino.');
      return;
    }
    final c = widget.card ?? OwnedCard();
    c.nameIt = nameIt;
    c.nameEn = nameEn;
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
    await _repo.save(c);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare la carta?'),
        content: const Text(
            'La carta e tutte le sue copie verranno tolte dalla collezione.'),
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

  @override
  Widget build(BuildContext context) {
    final c = widget.card;
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
            icon: const Icon(Icons.check),
            tooltip: 'Salva',
            onPressed: _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (c != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: CardThumb(
                    path: c.imagePath, url: c.imageUrl, width: 130, height: 190),
              ),
            ),
          _sectionTitle('NOMI'),
          _field(_nameIt, 'Nome italiano'),
          _field(_nameEn, 'Nome inglese'),
          _field(_code, 'Codice (es. LOB-IT001)'),
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
          const Padding(
            padding: EdgeInsets.only(bottom: 24),
            child: Text(
              'Nessun deck. L\'elenco dei deck in cui compare la carta arriva con la gestione dei deck.',
              style: TextStyle(color: AppColors.textDim),
            ),
          ),
        ],
      ),
    );
  }
}
