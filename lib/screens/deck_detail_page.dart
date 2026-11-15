import 'package:flutter/material.dart';

import '../data/card_repository.dart';
import '../models/deck.dart';
import '../theme.dart';
import '../widgets/card_thumb.dart';
import '../widgets/dialogs.dart';
import 'deck_card_picker_page.dart';

class DeckDetailPage extends StatefulWidget {
  final int deckId;

  const DeckDetailPage({super.key, required this.deckId});

  @override
  State<DeckDetailPage> createState() => _DeckDetailPageState();
}

class _DeckDetailPageState extends State<DeckDetailPage> {
  final _repo = CardRepository.instance;
  String _name = '';
  List<DeckEntry> _entries = [];
  bool _loaded = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _repo.revision.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _repo.revision.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    if (_deleting) return;
    final name = await _repo.deckName(widget.deckId);
    final list = await _repo.deckCards(widget.deckId);
    if (!mounted || _deleting) return;
    if (name == null) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _name = name;
      _entries = list;
      _loaded = true;
    });
  }

  int _count(String section) => _entries
      .where((e) => e.section == section)
      .fold<int>(0, (a, e) => a + e.qty);

  Map<int, int> _usedPerCard() {
    final m = <int, int>{};
    for (final e in _entries) {
      final id = e.card.id;
      if (id != null) m[id] = (m[id] ?? 0) + e.qty;
    }
    return m;
  }

  Future<void> _rename() async {
    final name = await promptText(context,
        title: 'Rinomina deck', initial: _name, hint: 'Nome del deck');
    if (name != null) await _repo.renameDeck(widget.deckId, name);
  }

  Future<void> _deleteDeck() async {
    final ok = await confirmDialog(context,
        title: 'Eliminare il deck?',
        message:
            '"$_name" verrà eliminato. Le carte restano nella collezione.',
        confirm: 'Elimina');
    if (!ok) return;
    _deleting = true;
    await _repo.deleteDeck(widget.deckId);
    if (mounted) Navigator.of(context).pop();
  }

  void _addCards() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
          builder: (_) => DeckCardPickerPage(deckId: widget.deckId)),
    );
  }

  Future<void> _change(DeckEntry e, int delta) async {
    final ok = await _repo.changeDeckQty(widget.deckId, e.card, e.section, delta);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Hai solo ${e.card.totalQty} copie di questa carta: non puoi metterne di più in questo deck.')));
    }
  }

  Widget _sectionHeader(String title, int count) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Row(
          children: [
            Text(title,
                style: const TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
            const SizedBox(width: 8),
            Text('$count carte',
                style: const TextStyle(color: AppColors.textDim)),
          ],
        ),
      );

  Widget _entryRow(DeckEntry e, Map<int, int> used) {
    final c = e.card;
    final usedHere = used[c.id] ?? 0;
    final canAdd = usedHere < c.totalQty;
    final canMove = e.section != kExtra;
    final target = e.section == kMain ? kSide : kMain;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          CardThumb(path: c.imagePath, url: c.imageUrl, width: 34, height: 50),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.displayName,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                    'Possedute: IT ×${c.qtyIt}  EN ×${c.qtyEn}',
                    style: const TextStyle(
                        color: AppColors.textDim, fontSize: 12)),
              ],
            ),
          ),
          if (canMove)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                  e.section == kMain ? Icons.arrow_downward : Icons.arrow_upward,
                  size: 20),
              tooltip: 'Sposta una copia in ${sectionLabel(target)}',
              onPressed: () =>
                  _repo.moveInDeck(widget.deckId, c.id!, e.section, target),
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: () => _change(e, -1),
          ),
          SizedBox(
            width: 24,
            child: Text('${e.qty}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_circle_outline),
            onPressed: canAdd ? () => _change(e, 1) : null,
          ),
        ],
      ),
    );
  }

  List<Widget> _section(String key, String title, Map<int, int> used) {
    final list = _entries.where((e) => e.section == key).toList();
    return [
      _sectionHeader(title, _count(key)),
      if (list.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text('Nessuna carta.',
              style: TextStyle(color: AppColors.textDim)),
        )
      else
        for (final e in list) _entryRow(e, used),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final used = _usedPerCard();
    final total = _count(kMain) + _count(kExtra) + _count(kSide);
    return Scaffold(
      appBar: AppBar(
        title: Text(_name),
        actions: [
          IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Rinomina',
              onPressed: _loaded ? _rename : null),
          IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Elimina deck',
              onPressed: _loaded ? _deleteDeck : null),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCards,
        icon: const Icon(Icons.add),
        label: const Text('Aggiungi carte'),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    'Totale: $total carte  ·  Main ${_count(kMain)}  ·  Extra ${_count(kExtra)}  ·  Side ${_count(kSide)}',
                    style: const TextStyle(color: AppColors.textDim),
                  ),
                ),
                ..._section(kMain, 'MAIN DECK', used),
                ..._section(kExtra, 'EXTRA DECK', used),
                ..._section(kSide, 'SIDE DECK', used),
              ],
            ),
    );
  }
}
