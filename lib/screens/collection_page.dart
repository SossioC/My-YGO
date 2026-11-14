import 'package:flutter/material.dart';

import '../data/card_repository.dart';
import '../models/owned_card.dart';
import '../theme.dart';
import '../widgets/card_thumb.dart';
import 'card_edit_page.dart';

class CollectionPage extends StatefulWidget {
  const CollectionPage({super.key});

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  final _repo = CardRepository.instance;
  final _search = TextEditingController();

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
    final list = await _repo.all(query: _search.text);
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

  @override
  Widget build(BuildContext context) {
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
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _search,
              onChanged: (_) => _reload(),
              decoration: InputDecoration(
                hintText: 'Cerca per nome o codice',
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_stats[0]} carte diverse  ·  ${_stats[1]} copie in totale',
                style: const TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
            ),
          ),
          Expanded(child: _buildList()),
        ],
      ),
    );
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
            _search.text.isEmpty
                ? 'La collezione è vuota.\nScansiona una carta oppure aggiungila a mano con il pulsante +.'
                : 'Nessuna carta trovata.',
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
        return ListTile(
          leading: CardThumb(path: c.imagePath, url: c.imageUrl),
          title: Text(
            c.nameIt.isEmpty ? '—' : c.nameIt,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${c.nameEn.isEmpty ? '—' : c.nameEn}  ·  ${c.code}',
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
