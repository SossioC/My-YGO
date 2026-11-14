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
  // Forma normale: LOB-IT001, RA01-EN012, LDK2-ENK01, SDY-E022, SDY-046
  static final RegExp _main = RegExp(
    r'\b([A-Z0-9]{2,5})\s?-\s?([A-Z01]{0,2})\s?([0-9OIL]{3}|[A-Z][0-9]{2})(?![0-9])',
  );

  // Trattino non letto: LOBIT001, LOB IT001
  static final RegExp _noHyphen = RegExp(
    r'\b([A-Z0-9]{2,5}?)[\s-]?(IT|EN|LT)\s?([0-9OIL]{3}|[A-Z][0-9]{2})(?![0-9])',
  );

  static final RegExp _digits = RegExp(r'^[0-9OIL]{3}$');

  static const Map<String, String> _langFix = {
    'LT': 'IT',
    'FN': 'EN',
    'EH': 'EN',
    'EM': 'EN',
    'IL': 'IT',
    'TT': 'IT',
  };

  static String _normLang(String s) {
    final t = s.replaceAll('1', 'I').replaceAll('0', 'O');
    return _langFix[t] ?? t;
  }

  static String _normNumber(String s) {
    if (_digits.hasMatch(s)) {
      return s.replaceAll('O', '0').replaceAll('I', '1').replaceAll('L', '1');
    }
    return s;
  }

  static List<ParsedCode> findAll(String text) {
    final t = text
        .toUpperCase()
        .replaceAll(RegExp(r'[\u2010-\u2015\u2212_]'), '-');
    final result = <ParsedCode>[];
    final seen = <String>{};

    void add(String prefix, String lang, String number) {
      final code = ParsedCode(prefix, _normLang(lang), _normNumber(number));
      if (seen.add(code.raw)) result.add(code);
    }

    for (final m in _main.allMatches(t)) {
      add(m.group(1)!, m.group(2) ?? '', m.group(3)!);
    }
    if (result.isEmpty) {
      for (final m in _noHyphen.allMatches(t)) {
        add(m.group(1)!, m.group(2) ?? '', m.group(3)!);
      }
    }
    return result;
  }
}
