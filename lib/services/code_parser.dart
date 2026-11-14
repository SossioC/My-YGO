class ParsedCode {
  final String prefix;
  final String langTag;
  final String number;

  const ParsedCode(this.prefix, this.langTag, this.number);

  String get raw =>
      langTag.isEmpty ? '$prefix-$number' : '$prefix-$langTag$number';

  /// 'it', 'en' oppure null se la lingua non è gestita.
  String? get lang {
    switch (langTag) {
      case 'IT':
      case 'I':
        return 'it';
      case 'EN':
      case 'E':
      case '':
        return 'en';
      default:
        return null;
    }
  }

  /// Codici da provare, in ordine, per trovare la carta nel database.
  List<String> get candidates {
    final list = <String>[raw];
    if (langTag.isNotEmpty) {
      list.add('$prefix-EN$number');
      list.add('$prefix-E$number');
      list.add('$prefix-$number');
    }
    return {...list}.toList();
  }
}

class CodeParser {
  static final RegExp _re = RegExp(
    r'\b([A-Z0-9]{2,5})\s?-\s?([A-Z]{0,2})\s?([0-9OIL]{3})(?![0-9])',
  );

  static List<ParsedCode> findAll(String text) {
    final t = text
        .toUpperCase()
        .replaceAll(RegExp(r'[\u2010-\u2015\u2212_]'), '-');
    final result = <ParsedCode>[];
    final seen = <String>{};
    for (final m in _re.allMatches(t)) {
      final prefix = m.group(1)!;
      final lang = m.group(2) ?? '';
      final number = m
          .group(3)!
          .replaceAll('O', '0')
          .replaceAll('I', '1')
          .replaceAll('L', '1');
      final code = ParsedCode(prefix, lang, number);
      if (seen.add(code.raw)) result.add(code);
    }
    return result;
  }
}
