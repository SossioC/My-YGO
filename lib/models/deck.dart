import 'owned_card.dart';

const String kMain = 'main';
const String kExtra = 'extra';
const String kSide = 'side';

String sectionLabel(String section) {
  switch (section) {
    case kExtra:
      return 'Extra';
    case kSide:
      return 'Side';
    default:
      return 'Main';
  }
}

class DeckSummary {
  final int id;
  final String name;
  final int main;
  final int extra;
  final int side;

  const DeckSummary({
    required this.id,
    required this.name,
    required this.main,
    required this.extra,
    required this.side,
  });

  int get total => main + extra + side;
}

/// Una carta dentro un deck, in una certa sezione.
class DeckEntry {
  final OwnedCard card;
  final String section;
  final int qty;

  const DeckEntry(this.card, this.section, this.qty);
}

/// In quali deck compare una carta.
class DeckUse {
  final int deckId;
  final String name;
  final int main;
  final int extra;
  final int side;

  const DeckUse({
    required this.deckId,
    required this.name,
    required this.main,
    required this.extra,
    required this.side,
  });

  int get total => main + extra + side;
}
