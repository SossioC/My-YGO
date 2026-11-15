enum TypeGroup { monster, spell, trap, extra }

enum LangFilter { any, hasIt, hasEn, onlyIt, onlyEn }

enum DeckFilter { any, inDeck, notInDeck }

enum SortKey { name, qty, added, level, atk }

String typeGroupLabel(TypeGroup g) {
  switch (g) {
    case TypeGroup.monster:
      return 'Mostro';
    case TypeGroup.spell:
      return 'Magia';
    case TypeGroup.trap:
      return 'Trappola';
    case TypeGroup.extra:
      return 'Extra Deck';
  }
}

String sortKeyLabel(SortKey k) {
  switch (k) {
    case SortKey.name:
      return 'Nome';
    case SortKey.qty:
      return 'Quantità';
    case SortKey.added:
      return 'Data di aggiunta';
    case SortKey.level:
      return 'Livello';
    case SortKey.atk:
      return 'ATK';
  }
}

/// Attributi: valore salvato (inglese) -> etichetta italiana.
const Map<String, String> kAttributes = {
  'DARK': 'Oscurità',
  'LIGHT': 'Luce',
  'EARTH': 'Terra',
  'WATER': 'Acqua',
  'FIRE': 'Fuoco',
  'WIND': 'Vento',
  'DIVINE': 'Divino',
};

/// Filtri e ordinamento della collezione.
class CardFilter {
  String query;
  Set<TypeGroup> types;
  Set<String> attributes;
  Set<int> levels;
  LangFilter lang;
  bool duplicatesOnly;
  DeckFilter deck;
  SortKey sort;
  bool ascending;

  CardFilter({
    this.query = '',
    Set<TypeGroup>? types,
    Set<String>? attributes,
    Set<int>? levels,
    this.lang = LangFilter.any,
    this.duplicatesOnly = false,
    this.deck = DeckFilter.any,
    this.sort = SortKey.name,
    this.ascending = true,
  })  : types = types ?? <TypeGroup>{},
        attributes = attributes ?? <String>{},
        levels = levels ?? <int>{};

  CardFilter copy() => CardFilter(
        query: query,
        types: {...types},
        attributes: {...attributes},
        levels: {...levels},
        lang: lang,
        duplicatesOnly: duplicatesOnly,
        deck: deck,
        sort: sort,
        ascending: ascending,
      );

  /// Quanti filtri sono attivi (l'ordinamento e la ricerca non contano).
  int get activeCount {
    var n = 0;
    if (types.isNotEmpty) n++;
    if (attributes.isNotEmpty) n++;
    if (levels.isNotEmpty) n++;
    if (lang != LangFilter.any) n++;
    if (duplicatesOnly) n++;
    if (deck != DeckFilter.any) n++;
    return n;
  }

  bool get isDefaultSort => sort == SortKey.name && ascending;

  void clearFilters() {
    types.clear();
    attributes.clear();
    levels.clear();
    lang = LangFilter.any;
    duplicatesOnly = false;
    deck = DeckFilter.any;
  }
}
