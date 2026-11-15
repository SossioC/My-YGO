import 'package:flutter/material.dart';

import '../data/card_repository.dart';
import '../models/deck.dart';
import '../theme.dart';
import '../widgets/dialogs.dart';
import 'deck_detail_page.dart';

class DecksPage extends StatefulWidget {
  const DecksPage({super.key});

  @override
  State<DecksPage> createState() => _DecksPageState();
}

class _DecksPageState extends State<DecksPage> {
  final _repo = CardRepository.instance;
  List<DeckSummary> _decks = [];
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
    super.dispose();
  }

  Future<void> _reload() async {
    final list = await _repo.decks();
    if (!mounted) return;
    setState(() {
      _decks = list;
      _loaded = true;
    });
  }

  Future<void> _newDeck() async {
    final name = await promptText(context,
        title: 'Nuovo deck', hint: 'Nome del deck', confirm: 'Crea');
    if (name == null) return;
    final id = await _repo.createDeck(name);
    if (!mounted) return;
    _open(id);
  }

  void _open(int id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DeckDetailPage(deckId: id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newDeck,
        icon: const Icon(Icons.add),
        label: const Text('Nuovo deck'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (_decks.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nessun deck.\nCreane uno con il pulsante in basso e riempilo con le carte della collezione.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textDim),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: 8, bottom: 88),
      itemCount: _decks.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final d = _decks[i];
        return ListTile(
          leading: const Icon(Icons.layers_outlined, color: AppColors.gold),
          title: Text(d.name),
          subtitle: Text(
              'Main ${d.main}  ·  Extra ${d.extra}  ·  Side ${d.side}   (${d.total} carte)'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(d.id),
        );
      },
    );
  }
}
