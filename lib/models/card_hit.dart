/// Un risultato di ricerca per nome (dati essenziali, per scegliere la carta giusta).
class CardHit {
  final int id;
  final String? nameEn;
  final String? nameIt;
  final String type;
  final String? imageSmallUrl;

  const CardHit({
    required this.id,
    this.nameEn,
    this.nameIt,
    this.type = '',
    this.imageSmallUrl,
  });

  String get title {
    if (nameIt != null && nameIt!.isNotEmpty) return nameIt!;
    return nameEn ?? '';
  }

  /// Seconda riga: l'altro nome (se diverso) e il tipo.
  String get subtitle {
    final parts = <String>[];
    if (nameIt != null &&
        nameIt!.isNotEmpty &&
        nameEn != null &&
        nameEn!.isNotEmpty &&
        nameEn != nameIt) {
      parts.add(nameEn!);
    }
    if (type.isNotEmpty) parts.add(type);
    return parts.join('  ·  ');
  }
}

class SearchResult {
  final List<CardHit> hits;
  final int total;
  final bool networkError;

  const SearchResult({
    this.hits = const [],
    this.total = 0,
    this.networkError = false,
  });
}
