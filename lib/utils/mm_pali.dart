class MmPali {
  MmPali._();
  static final Map<String, String> _independentVowels = {
    'a': 'အ',
    'ā': 'အာ',
    'i': 'ဣ',
    'ī': 'ဤ',
    'u': 'ဥ',
    'ū': 'ဦ',
    'e': 'ဧ',
    'o': 'ဩ'
  };

  static final Map<String, String> _dependentVowels = {
    // 'a': '',
    'ā': 'ာ',
    'i': 'ိ',
    'ī': 'ီ',
    'u': 'ု',
    'ū': 'ူ',
    'o': 'ော',
    'e': 'ေ'
  };

  static final Map<String, String> _consonants = {
    'kh': 'ခ',
    'k': 'က',
    'gh': 'ဃ',
    'g': 'ဂ',
    'ṅ': 'င',
    'ch': 'ဆ',
    'c': 'စ',
    'jh': 'ဈ',
    'j': 'ဇ',
    'ñ': 'ဉ',
    'ṭh': 'ဌ',
    'ṭ': 'ဋ',
    'ḍh': 'ဎ',
    'ḍ': 'ဍ',
    'ṇ': 'ဏ',
    'th': 'ထ',
    't': 'တ',
    'dh': 'ဓ',
    'd': 'ဒ',
    'n': 'န',
    'ph': 'ဖ',
    'p': 'ပ',
    'bh': 'ဘ',
    'b': 'ဗ',
    'm': 'မ',
    'y': 'ယ',
    'r': 'ရ',
    'l': 'လ',
    'v': 'ဝ',
    's': 'သ',
    'h': 'ဟ',
    'ḷ': 'ဠ',
    //  'ṃ' : 'ံ'
  };

  static const String _virama = '္';

  static final Map<String, String> _specialShapes = {
    'ဉ္ဉ': 'ည',
    'သ္သ': 'ဿ',
    '္ယ': 'ျ',
    '္ရ': 'ြ',
    '္ဝ': 'ွ',
    '္ဟ': 'ှ',
    'င္': 'င်္',
    // 'သင်္ဃ': 'သံဃ',
  };

  static final Map<String, String> _digits = {
    '1': '၁',
    '2': '၂',
    '3': '၃',
    '4': '၄',
    '5': '၅',
    '6': '၆',
    '7': '၇',
    '8': '၈',
    '9': '၉',
    '0': '၀',
  };

  static final Map<String, String> _puntutations = {
    ',': '၊',
    '.': '။',
  };

  static toRoman(String text) {
    _specialShapes.forEach((key, value) {
      text = text.replaceAll(value, key);
    });

    _independentVowels.forEach((key, value) {
      text = text.replaceAll(value, key);
    });

    _consonants.forEach((key, value) {
      text = text.replaceAll(value + _virama, key);
    });

    _consonants.forEach((key, value) {
      text = text.replaceAll(value, '${key}a');
    });

    // text = text.replaceAll('a' + 'ါ', 'ā');
    // text = text.replaceAll('a' + 'ေါ', 'o');
    text = text.replaceAll('ါ', 'ာ');
    _dependentVowels.forEach((key, value) {
      text = text.replaceAll('a$value', key);
    });

    text = text.replaceAll('ံ', 'ṃ');

    _digits.forEach((key, value) {
      text = text.replaceAll(value, key);
    });

    _puntutations.forEach((key, value) {
      text = text.replaceAll(value, key);
    });

    // special word
    text = text.replaceAll('saṃgh', 'saṅgh');
    return text;
  }

  static fromRoman(String text) {
    text = text.toLowerCase();

    _consonants.forEach((key, value) {
      text = text.replaceAll(key, value + _virama);
    });

    text = text.replaceAll('${_virama}a', '');
    _dependentVowels.forEach((key, value) {
      text = text.replaceAll(_virama + key, value);
    });

    _independentVowels.forEach((key, value) {
      text = text.replaceAll(key, value);
    });

    text = text.replaceAll('ṃ', 'ံ');

    _specialShapes.forEach((key, value) {
      text = text.replaceAll(key, value);
    });
    text = text.replaceAll('သင်္ဃ', 'သံဃ');

    text = text.replaceAllMapped(
        RegExp(r"([ခဂငဒပဝ]ေ?)\u102c"), (match) => "${match.group(1)}\u102b");
    text = text.replaceAllMapped(
        RegExp(r"(က္ခ|န္ဒ|ပ္ပ|မ္ပ)(ေ?)\u102b"),
        (match) =>
            "${match.group(1)}${match.group(2)}\u102c"); // restore back tall aa to aa for some pattern
    text = text.replaceAllMapped(RegExp(r"(ဒ္ဓ|ဒွ)(ေ?)\u102c"),
        (match) => "${match.group(1)}${match.group(2)}\u102b"); //

    _digits.forEach((key, value) {
      text = text.replaceAll(key, value);
    });

    _puntutations.forEach((key, value) {
      text = text.replaceAll(key, value);
    });

    // special word
    text = text.replaceAll('သင်္ဃ', 'သံဃ');
    return text;
  }
}
