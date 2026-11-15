import 'dart:async';

import 'package:flutter/material.dart';

import '../models/card_hit.dart';
import '../models/card_info.dart';
import '../services/ygo_api.dart';
import '../theme.dart';
import '../widgets/card_thumb.dart';

/// Ricerca di una carta per nome (italiano o inglese). Restituisce la carta scelta.
class CardSearchPage extends StatefulWidget {
  final String initialQuery;

  const CardSearchPage({super.key, this.initialQuery = ''});

  @override
  State<CardSearchPage> createState() => _CardSearchPageState();
}

class _CardSearchPageState extends State<CardSearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;

  List<CardHit> _hits = [];
  int _total = 0;
  bool _loading = false;
  int? _picking;
  String _message = 'Scrivi almeno 3 lettere del nome (italiano o inglese).';

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialQuery;
    if (widget.initialQuery.trim().length >= 3) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _search);
  }

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.length < 3) {
      setState(() {
        _hits = [];
        _total = 0;
        _loading = false;
        _message = 'Scrivi almeno 3 lettere del nome (italiano o inglese).';
      });
      return;
    }
    setState(() => _loading = true);
    final res = await YgoApi.instance.searchByName(q);
    if (!mounted || q != _controller.text.trim()) return;
    setState(() {
      _loading = false;
      _hits = res.hits;
      _total = res.total;
      if (res.networkError) {
        _message = 'Nessuna connessione: ricerca non riuscita.';
      } else if (res.hits.isEmpty) {
        _message = 'Nessuna carta trovata per "$q".';
      }
    });
  }

  Future<void> _pick(CardHit hit) async {
    if (_picking != null) return;
    setState(() => _picking = hit.id);
    final res = await YgoApi.instance.lookupById(hit.id);
    if (!mounted) return;
    final CardInfo? card = res.card;
    if (card != null) {
      Navigator.of(context).pop(card);
      return;
    }
    setState(() => _picking = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.networkError
            ? 'Nessuna connessione: impossibile caricare la carta.'
            : 'Impossibile caricare i dati della carta.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cerca per nome')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _controller,
              autofocus: widget.initialQuery.trim().length < 3,
              onChanged: _onChanged,
              onSubmitted: (_) => _search(),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Es. Drago Bianco o Blue-Eyes',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          if (_hits.isNotEmpty && _total > _hits.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Ci sono più risultati di quelli mostrati (${YgoApi.searchLimit} per lingua): scrivi più lettere per restringere.',
                  style:
                      const TextStyle(color: AppColors.textDim, fontSize: 12),
                ),
              ),
            ),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_hits.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textDim)),
        ),
      );
    }
    return ListView.builder(
      itemCount: _hits.length,
      itemBuilder: (context, i) {
        final h = _hits[i];
        final picking = _picking == h.id;
        return ListTile(
          leading: CardThumb(url: h.imageSmallUrl, width: 36, height: 52),
          title: Text(h.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(h.subtitle,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: picking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.chevron_right),
          onTap: () => _pick(h),
        );
      },
    );
  }
}
