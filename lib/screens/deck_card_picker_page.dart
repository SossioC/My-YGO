import 'package:flutter/material.dart';

import '../data/card_repository.dart';
import '../models/deck.dart';
import '../models/owned_card.dart';
import '../theme.dart';
import '../widgets/card_thumb.dart';

/// Scelta delle carte della collezione da mettere in un deck.
class DeckCardPickerPage extends StatefulWidget {
  final int deckId;

  const DeckCardPickerPage({super.key, required this.deckId});

  @override
  State<DeckCardPickerPage> createState() => _DeckCardPickerPageState();
}

class _DeckCardPickerPageState extends State<DeckCardPickerPage> {
  final _repo = CardRepository.instance;
  final _search = TextEditingController();

  List<OwnedCard> _cards = [];
  // cardId -> sezione -> copie
  Map<int, Map<String, int>> _inDeck = {};
  String _section = kMain;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _repo.revision.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _repo.revision.removeListener(_reload);
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final cards = await _repo.all(query: _search.text);
    final entries = await _repo.deckCards(widget.deckId);
    final map = <int, Map<String, int>>{};
    for (final e in entries) {
      final id = e.card.id;
      if (id == null) continue;
      map.putIfAbsent(id, () => {})[e.section] = e.qty;
    }
    if (!mounted) return;
    setState(() {
      _cards = cards;
      _inDeck = map;
      _loaded = true;
    });
  }

  String _targetSection(OwnedCard c) => c.isExtraDeck ? kExtra : _section;

  int _used(OwnedCard c) =>
      (_inDeck[c.id]?.values ?? const <int>[]).fold<int>(0, (a, b) => a + b);

  Future<void> _add(OwnedCard c) async {
    final ok = await _repo.changeDeckQty(
        widget.deckId, c, _targetSection(c), 1);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Hai solo ${c.totalQty} copie di questa carta: sono già tutte in questo deck.')));
    }
  }

  Future<void> _remove(OwnedCard c) =>
      _repo.changeDeckQty(widget.deckId, c, _targetSection(c), -1);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aggiungi carte')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _search,
              onChanged: (_) => _reload(),
              decoration: const InputDecoration(
                hintText: 'Cerca per nome o codice',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Row(
              children: [
                const Text('Aggiungi in:',
                    style: TextStyle(color: AppColors.textDim)),
                const SizedBox(width: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: kMain, label: Text('Main')),
                    ButtonSegment(value: kSide, label: Text('Side')),
                  ],
                  selected: {_section},
                  onSelectionChanged: (s) =>
                      setState(() => _section = s.first),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Fusione, Synchro, Xyz e Link vanno automaticamente nell\'Extra Deck.',
                style: TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
            ),
          ),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (_cards.isEmpty) {
      return const Center(
        child: Text('Nessuna carta trovata nella collezione.',
            style: TextStyle(color: AppColors.textDim)),
      );
    }
    return ListView.builder(
      itemCount: _cards.length,
      itemBuilder: (context, i) {
        final c = _cards[i];
        final sec = _inDeck[c.id] ?? const <String, int>{};
        final used = _used(c);
        final target = _targetSection(c);
        final inTarget = sec[target] ?? 0;
        final parts = <String>[
          if ((sec[kMain] ?? 0) > 0) 'Main ${sec[kMain]}',
          if ((sec[kExtra] ?? 0) > 0) 'Extra ${sec[kExtra]}',
          if ((sec[kSide] ?? 0) > 0) 'Side ${sec[kSide]}',
        ];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              CardThumb(
                  path: c.imagePath, url: c.imageUrl, width: 34, height: 50),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.displayName,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      'Possedute ${c.totalQty} (IT ${c.qtyIt}, EN ${c.qtyEn})'
                      '${parts.isEmpty ? '' : '  ·  nel deck: ${parts.join(', ')}'}'
                      '${c.isExtraDeck ? '  ·  Extra' : ''}',
                      style: const TextStyle(
                          color: AppColors.textDim, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: inTarget > 0 ? () => _remove(c) : null,
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_circle_outline),
                onPressed: used < c.totalQty ? () => _add(c) : null,
              ),
            ],
          ),
        );
      },
    );
  }
}
