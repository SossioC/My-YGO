/// Una carta nella collezione (un solo record, con nomi IT/EN e quantità separate).
class OwnedCard {
  int? id;
  int? ygoId;
  String nameIt;
  String nameEn;
  String code;
  String type;
  String attribute;
  String race;
  int? level;
  int? atk;
  int? def;
  String descIt;
  String descEn;
  String notes;
  String? imageUrl;
  String? imagePath;
  int qtyIt;
  int qtyEn;
  int createdAt;
  int updatedAt;

  OwnedCard({
    this.id,
    this.ygoId,
    this.nameIt = '',
    this.nameEn = '',
    this.code = '',
    this.type = '',
    this.attribute = '',
    this.race = '',
    this.level,
    this.atk,
    this.def,
    this.descIt = '',
    this.descEn = '',
    this.notes = '',
    this.imageUrl,
    this.imagePath,
    this.qtyIt = 0,
    this.qtyEn = 0,
    int? createdAt,
    int? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  int get totalQty => qtyIt + qtyEn;

  /// Nome da mostrare come principale: italiano se c'è, altrimenti inglese.
  String get displayName => nameIt.isNotEmpty ? nameIt : nameEn;

  bool get isExtraDeck {
    final t = type.toLowerCase();
    return t.contains('fusion') ||
        t.contains('synchro') ||
        t.contains('xyz') ||
        t.contains('link');
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'ygo_id': ygoId,
        'name_it': nameIt,
        'name_en': nameEn,
        'code': code,
        'type': type,
        'attribute': attribute,
        'race': race,
        'level': level,
        'atk': atk,
        'def': def,
        'desc_it': descIt,
        'desc_en': descEn,
        'notes': notes,
        'image_url': imageUrl,
        'image_path': imagePath,
        'qty_it': qtyIt,
        'qty_en': qtyEn,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory OwnedCard.fromMap(Map<String, Object?> m) {
    String s(String k) => (m[k] as String?) ?? '';
    return OwnedCard(
      id: m['id'] as int?,
      ygoId: m['ygo_id'] as int?,
      nameIt: s('name_it'),
      nameEn: s('name_en'),
      code: s('code'),
      type: s('type'),
      attribute: s('attribute'),
      race: s('race'),
      level: m['level'] as int?,
      atk: m['atk'] as int?,
      def: m['def'] as int?,
      descIt: s('desc_it'),
      descEn: s('desc_en'),
      notes: s('notes'),
      imageUrl: m['image_url'] as String?,
      imagePath: m['image_path'] as String?,
      qtyIt: (m['qty_it'] as int?) ?? 0,
      qtyEn: (m['qty_en'] as int?) ?? 0,
      createdAt: m['created_at'] as int?,
      updatedAt: m['updated_at'] as int?,
    );
  }
}
