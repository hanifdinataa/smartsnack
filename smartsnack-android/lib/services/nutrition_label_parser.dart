class NutritionLabelDraft {
  const NutritionLabelDraft({
    required this.name,
    required this.category,
    required this.sugarGrams,
    required this.netWeight,
    required this.rawText,
  });

  final String name;
  final String category;
  final double? sugarGrams;
  final double? netWeight;
  final String rawText;

  bool get hasUsefulData =>
      name.isNotEmpty || sugarGrams != null || netWeight != null;
}

class NutritionLabelParser {
  static const List<String> _headerFragments = <String>[
    'inform',
    'gizi',
    'nutri',
    'nutrition',
    'takaran',
    'serving',
    'jumlah persajian',
    'amount per serving',
    'energi',
    'energy',
    'lemak',
    'fat',
    'protein',
    'karbo',
    'carbo',
    'gula',
    'sugar',
    'garam',
    'sodium',
    'vitamin',
    'mineral',
    'akg',
    'dv',
    'persen',
    'daily value',
  ];

  static const List<String> _ignoredNameTerms = <String>[
    'informasi nilai gizi',
    'informasi gizi',
    'nutrition facts',
    'nutrition information',
    'takaran saji',
    'sajian per kemasan',
    'jumlah per sajian',
    'jumlah persajian',
    'energi total',
    'gula',
    'karbohidrat',
    'lemak',
    'protein',
    'natrium',
    'komposisi',
    'ingredient',
    'ingredients',
  ];

  static const List<String> _drinkKeywords = <String>[
    'drink',
    'minuman',
    'teh',
    'coffee',
    'kopi',
    'juice',
    'jus',
    'soda',
    'cola',
    'isotonik',
    'beverage',
  ];

  static const List<String> _weakDrinkKeywords = <String>[
    'susu',
    'milk',
    'yogurt',
  ];

  static const List<String> _foodKeywords = <String>[
    'food',
    'makanan',
    'snack',
    'wafer',
    'biskuit',
    'biscuit',
    'mie',
    'noodle',
    'chips',
    'roti',
    'bread',
    'coklat',
    'chocolate',
    'cookies',
    'cracker',
    'permen',
    'candy',
  ];

  static NutritionLabelDraft parse(String rawText) {
    final normalized = cleanRawText(rawText);
    final lines = _toCleanLines(normalized);

    final sugar = _extractSugar(lines);
    final netWeight = _extractNetWeight(lines);
    final name = _extractName(lines);
    final category = _detectCategory(lines, name);

    return NutritionLabelDraft(
      name: name,
      category: category,
      sugarGrams: sugar,
      netWeight: netWeight,
      rawText: normalized.trim(),
    );
  }

  static String cleanRawText(String rawText) {
    return rawText
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[|]'), 'I')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAllMapped(
          RegExp(
            r'(gula\s*/?\s*sugar)\s+(\d{1,3})9\b',
            caseSensitive: false,
          ),
          (match) => '${match.group(1)} ${match.group(2)} g',
        )
        .replaceAllMapped(
          RegExp(
            r'(takaran saji\s*/?\s*serving size\s*[: ]+)(\d{1,3})9\b',
            caseSensitive: false,
          ),
          (match) => '${match.group(1)}${match.group(2)} g',
        )
        .replaceAllMapped(
          RegExp(r'(?<=\d)(?=[A-Za-z%])'),
          (_) => ' ',
        )
        .replaceAllMapped(
          RegExp(r'(?<=[A-Za-z])(?=\d)'),
          (_) => ' ',
        )
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static List<String> _toCleanLines(String normalized) {
    return normalized
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map(_cleanupLine)
        .where((line) => line.isNotEmpty)
        .toList();
  }

  static String _cleanupLine(String line) {
    return line
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[^A-Za-z0-9]+'), '')
        .replaceAll(RegExp(r'[^A-Za-z0-9)%/.,:+ -]+$'), '')
        .trim();
  }

  static double? _extractSugar(List<String> lines) {
    final labeledPattern = RegExp(
      r'(?:gula|sugar|sugars|jumlah gula|gula total)[^0-9]{0,20}(\d+(?:[.,]\d+)?)\s*(?:g|gr|gram)\b',
      caseSensitive: false,
    );
    final loosePattern = RegExp(
      r'(?:gula|sugar|sugars)[^0-9]{0,12}(\d+(?:[.,]\d+)?)\b',
      caseSensitive: false,
    );
    final adjacentNumberPattern = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(?:g|gr|gram)\b',
      caseSensitive: false,
    );

    for (var i = 0; i < lines.length; i++) {
      final current = lines[i];
      final labeled = labeledPattern.firstMatch(current);
      if (labeled != null) {
        return _toDouble(labeled.group(1));
      }

      final loose = loosePattern.firstMatch(current);
      if (loose != null) {
        final candidate = _normalizeDetachedUnitValue(loose.group(1));
        final suffix = _suffixAfterSugar(current).toLowerCase();
        final isMilligram = suffix.contains('mg');
        if (candidate != null && !isMilligram && candidate <= 80) {
          return candidate;
        }
      }

      if (current.toLowerCase().contains('gula') ||
          current.toLowerCase().contains('sugar')) {
        final afterKeyword = _extractAfterSugarKeyword(current);
        if (afterKeyword != null) {
          return afterKeyword;
        }

        final suffix = _suffixAfterSugar(current);
        final adjacent = adjacentNumberPattern.firstMatch(suffix);
        if (adjacent != null) {
          return _toDouble(adjacent.group(1));
        }

        final sameLineNumber = RegExp(r'(\d+(?:[.,]\d+)?)').firstMatch(suffix);
        final looseValue = _normalizeDetachedUnitValue(sameLineNumber?.group(1));
        final isMilligram = suffix.toLowerCase().contains('mg');
        if (looseValue != null && !isMilligram && looseValue <= 80) {
          return looseValue;
        }

        if (i + 1 < lines.length) {
          final next = adjacentNumberPattern.firstMatch(lines[i + 1]);
          if (next != null) {
            return _toDouble(next.group(1));
          }
        }
      }
    }

    return null;
  }

  static String _suffixAfterSugar(String line) {
    final lowered = line.toLowerCase();
    final gulaIndex = lowered.indexOf('gula');
    final sugarIndex = lowered.indexOf('sugar');
    final indexes = <int>[gulaIndex, sugarIndex].where((v) => v >= 0).toList();
    if (indexes.isEmpty) return line;
    final start = indexes.reduce((a, b) => a < b ? a : b);
    return line.substring(start);
  }

  static double? _extractAfterSugarKeyword(String line) {
    final suffix = _suffixAfterSugar(line);
    final splitDigitsPattern = RegExp(
      r'(?:gula|sugar)[^0-9]{0,20}(\d)\s+(\d)\s*(?:g|gr|gram)\b',
      caseSensitive: false,
    );
    final splitDigits = splitDigitsPattern.firstMatch(suffix);
    if (splitDigits != null) {
      final combined = '${splitDigits.group(1)}${splitDigits.group(2)}';
      final value = _toDouble(combined);
      if (value != null && value >= 0 && value <= 80) {
        return value;
      }
    }

    final strictPattern = RegExp(
      r'(?:gula|sugar)[^0-9]{0,20}(\d+(?:[.,]\d+)?)\s*(?:g|gr|gram)\b',
      caseSensitive: false,
    );
    final strict = strictPattern.firstMatch(suffix);
    if (strict != null) {
      final value = _toDouble(strict.group(1));
      if (value != null && value >= 0 && value <= 80) {
        return value;
      }
    }

    final loosePattern = RegExp(
      r'(?:gula|sugar)[^0-9]{0,20}(\d+(?:[.,]\d+)?)',
      caseSensitive: false,
    );
    final loose = loosePattern.firstMatch(suffix);
    if (loose != null) {
      final value = _normalizeDetachedUnitValue(loose.group(1));
      if (value != null && value >= 0 && value <= 80) {
        return value;
      }
    }

    return null;
  }

  static double? _extractNetWeight(List<String> lines) {
    final weightPattern = RegExp(
      r'(?:takaran saji|serving size|berat bersih|isi bersih|netto|net weight)[^0-9]{0,20}(\d+(?:[.,]\d+)?)\s*(?:g|gr|gram|ml)\b',
      caseSensitive: false,
    );
    final weightLoosePattern = RegExp(
      r'(?:takaran saji|serving size|berat bersih|isi bersih|netto|net weight)[^0-9]{0,20}(\d+(?:[.,]\d+)?)\b',
      caseSensitive: false,
    );
    final simpleWeightPattern = RegExp(
      r'\b(\d+(?:[.,]\d+)?)\s*(?:g|gr|gram|ml)\b',
      caseSensitive: false,
    );

    for (final line in lines) {
      final weight = weightPattern.firstMatch(line);
      if (weight != null) {
        final value = _toDouble(weight.group(1));
        if (value != null && value >= 5) {
          return value;
        }
      }

      final loose = weightLoosePattern.firstMatch(line);
      if (loose != null) {
        final candidate = _normalizeDetachedUnitValue(loose.group(1));
        if (candidate != null && candidate >= 5) {
          return candidate;
        }
      }
    }

    for (final line in lines.take(4)) {
      final normalized = line.toLowerCase();
      if (normalized.contains('gula') || normalized.contains('sugar')) {
        continue;
      }

      final match = simpleWeightPattern.firstMatch(line);
      final value = _toDouble(match?.group(1));
      if (value != null && value >= 5) {
        return value;
      }

      if (normalized.contains('takaran') ||
          normalized.contains('serving') ||
          normalized.contains('netto') ||
          normalized.contains('berat')) {
        final loose = RegExp(r'(\d+(?:[.,]\d+)?)').firstMatch(line);
        final looseValue = _normalizeDetachedUnitValue(loose?.group(1));
        if (looseValue != null && looseValue >= 5) {
          return looseValue;
        }
      }
    }

    return null;
  }

  static String _extractName(List<String> lines) {
    for (final line in lines.take(8)) {
      final normalized = _normalizedForCompare(line);
      if (normalized.length < 3 || normalized.length > 48) {
        continue;
      }
      if (RegExp(r'^\d+$').hasMatch(normalized)) {
        continue;
      }
      if (_looksLikeNutritionHeader(normalized)) {
        continue;
      }
      if (RegExp(r'^\d+(?:[.,]\d+)?\s*(?:g|gr|gram|ml)$').hasMatch(normalized)) {
        continue;
      }
      return line;
    }

    return '';
  }

  static String _detectCategory(List<String> lines, String name) {
    final corpus = _normalizedForCompare('${lines.join(' ')} $name');
    var drinkScore = 0;
    var foodScore = 1;

    for (final keyword in _drinkKeywords) {
      if (corpus.contains(keyword)) {
        drinkScore += 2;
      }
    }
    for (final keyword in _weakDrinkKeywords) {
      if (corpus.contains(keyword)) {
        drinkScore += 1;
      }
    }
    for (final keyword in _foodKeywords) {
      if (corpus.contains(keyword)) {
        foodScore += 2;
      }
    }

    if (RegExp(
      r'(takaran saji|serving size)[^0-9]{0,20}\d+(?:[.,]\d+)?\s*ml\b',
      caseSensitive: false,
    ).hasMatch(corpus)) {
      drinkScore += 4;
    } else if (RegExp(
      r'\b\d+(?:[.,]\d+)?\s*ml\b',
      caseSensitive: false,
    ).hasMatch(corpus)) {
      drinkScore += 1;
    }

    return drinkScore >= foodScore + 2 ? 'drink' : 'food';
  }

  static bool _looksLikeNutritionHeader(String value) {
    if (_ignoredNameTerms.any(value.contains)) {
      return true;
    }
    if (_headerFragments.where(value.contains).length >= 2) {
      return true;
    }
    if (value.contains('%')) {
      return true;
    }
    return false;
  }

  static String _normalizedForCompare(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9%/ ]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static double? _normalizeDetachedUnitValue(String? raw) {
    final value = _toDouble(raw);
    if (value == null) return null;

    if (value >= 100 && value <= 999) {
      final candidate = (value / 10).roundToDouble();
      if (candidate <= 100) {
        return candidate;
      }
    }

    if (value > 80) {
      return null;
    }

    return value;
  }

  static double? _toDouble(String? value) {
    if (value == null) return null;
    return double.tryParse(value.replaceAll(',', '.'));
  }
}
