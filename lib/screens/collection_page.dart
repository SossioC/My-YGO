import 'package:flutter/material.dart';

import '../data/card_repository.dart';
import '../models/card_filter.dart';
import '../models/owned_card.dart';
import '../theme.dart';
import '../widgets/card_thumb.dart';
import '../widgets/filter_sheet.dart';
import 'card_edit_page.dart';

class CollectionPage extends StatefulWidget {
  const CollectionPage({super.key});

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  final _repo = CardRepository.instance;
  final _search = TextEditingController();
  CardFilter _filter = CardFilter();

  List<OwnedCard> _cards = [];
  List<int> _stats = [0, 0];
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
    _filter.query = _search.text;
    final list = await _repo.all(filter: _filter);
    final st = await _repo.stats();
    if (!mounted) return;
    setState(() {
      _cards = list;
      _stats = st;
      _loaded = true;
    });
  }

  void _open(OwnedCard? card) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CardEditPage(card: card)),
    );
  }

  Future<void> _openFilters() async {
    final result = await showFilterSheet(context, _filter);
    if (result == null) return;
    _filter = result;
    await _reload();
  }

  bool get _isFiltered =>
      _filter.activeCount > 0 || _search.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final n = _filter.activeCount;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _open(null),
        tooltip: 'Aggiungi carta a mano',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => _reload(),
                    decoration: InputDecoration(
                      hintText: 'Cerca per nome, codice o numero',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _search.clear();
                                _reload();
                              },
                            ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Filtri e ordinamento',
                  onPressed: _openFilters,
                  icon: Badge(
                    isLabelVisible: n > 0 || !_filter.isDefaultSort,
                    label: n > 0 ? Text('$n') : null,
                    child: const Icon(Icons.tune),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _summary(),
                    style: const TextStyle(
                        color: AppColors.textDim, fontSize: 12),
                  ),
                ),
                if (n > 0)
                  TextButton(
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    onPressed: () {
                      _filter.clearFilters();
                      _reload();
                    },
                    child: const Text('Azzera filtri'),
                  ),
              ],
            ),
          ),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  String _summary() {
    if (_isFiltered) {
      final copies = _cards.fold<int>(0, (a, c) => a + c.totalQty);
      return '${_cards.length} carte trovate (su ${_stats[0]})  ·  $copies copie';
    }
    return '${_stats[0]} carte diverse  ·  ${_stats[1]} copie in totale';
  }

  Widget _buildList() {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_cards.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _isFiltered
                ? 'Nessuna carta corrisponde a ricerca e filtri.'
                : 'La collezione è vuota.\nScansiona una carta oppure aggiungila a mano con il pulsante +.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textDim),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: _cards.length,
      itemBuilder: (context, i) {
        final c = _cards[i];
        // Se manca il nome italiano si mostra solo quello inglese.
        final hasIt = c.nameIt.isNotEmpty;
        final second = hasIt
            ? '${c.nameEn.isEmpty ? '' : '${c.nameEn}  ·  '}${c.code}'
            : c.code;
        return ListTile(
          leading: CardThumb(path: c.imagePath, url: c.imageUrl),
          title: Text(
            c.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            second,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('IT ×${c.qtyIt}',
                  style: const TextStyle(color: AppColors.gold, fontSize: 12)),
              Text('EN ×${c.qtyEn}',
                  style: const TextStyle(color: AppColors.gold, fontSize: 12)),
            ],
          ),
          onTap: () => _open(c),
        );
      },
    );
  }
}
