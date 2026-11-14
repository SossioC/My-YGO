/// Dati di una carta ricevuti da internet (YGOPRODeck).
class CardInfo {
  final int id;
  final String nameEn;
  final String? nameIt;
  final String type;
  final String? attribute;
  final String? race;
  final int? level;
  final int? atk;
  final int? def;
  final String? descEn;
  final String? descIt;
  final String? imageUrl;
  final String? imageSmallUrl;

  const CardInfo({
    required this.id,
    required this.nameEn,
    this.nameIt,
    required this.type,
    this.attribute,
    this.race,
    this.level,
    this.atk,
    this.def,
    this.descEn,
    this.descIt,
    this.imageUrl,
    this.imageSmallUrl,
  });
}
