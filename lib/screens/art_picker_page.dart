import 'package:flutter/material.dart';

import '../models/art_option.dart';
import '../services/ygo_api.dart';
import '../theme.dart';

/// Scelta dell'illustrazione di una carta tra quelle disponibili sul sito.
/// Restituisce l'indirizzo dell'immagine scelta.
class ArtPickerPage extends StatefulWidget {
  final int ygoId;
  final String? currentUrl;

  const ArtPickerPage({super.key, required this.ygoId, this.currentUrl});

  @override
  State<ArtPickerPage> createState() => _ArtPickerPageState();
}

class _ArtPickerPageState extends State<ArtPickerPage> {
  List<ArtOption> _options = [];
  bool _loading = true;
  bool _networkError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _networkError = false;
    });
    final res = await YgoApi.instance.fetchImages(widget.ygoId);
    if (!mounted) return;
    setState(() {
      _options = res.options;
      _networkError = res.networkError;
      _loading = false;
    });
  }

  String _name(String? url) {
    if (url == null) return '';
    return Uri.tryParse(url)?.pathSegments.lastOrNull ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scegli l\'illustrazione')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_networkError || _options.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _networkError
                    ? 'Nessuna connessione: impossibile caricare le illustrazioni.'
                    : 'Nessuna illustrazione disponibile per questa carta.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textDim),
              ),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Riprova')),
            ],
          ),
        ),
      );
    }
    final current = _name(widget.currentUrl);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            _options.length == 1
                ? 'Questa carta ha una sola illustrazione disponibile.'
                : 'Questa carta ha ${_options.length} illustrazioni. Tocca quella che vuoi usare.',
            style: const TextStyle(color: AppColors.textDim),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.66,
            ),
            itemCount: _options.length,
            itemBuilder: (context, i) {
              final o = _options[i];
              final isCurrent = _name(o.url) == current;
              return GestureDetector(
                onTap: () => Navigator.of(context).pop(o.url),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isCurrent ? AppColors.gold : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: Image.network(
                            o.smallUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(
                                child: Icon(Icons.broken_image_outlined)),
                          ),
                        ),
                      ),
                      if (isCurrent)
                        const Positioned(
                          top: 6,
                          right: 6,
                          child: CircleAvatar(
                            radius: 12,
                            backgroundColor: AppColors.gold,
                            child: Icon(Icons.check,
                                size: 16, color: AppColors.background),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
