/// Dart port of transcript-generator's `parseStudentInfo` (public/js/ai-parsers.js).
/// Parses a Bangla/English student-info prompt blob into structured fields.
/// Used by the teacher app's "Prompt ইমপোর্ট" add-student flow.
library;

const Map<String, String> _banglaDigits = {
  '০': '0',
  '১': '1',
  '২': '2',
  '৩': '3',
  '৪': '4',
  '৫': '5',
  '৬': '6',
  '৭': '7',
  '৮': '8',
  '৯': '9',
};

const Map<String, String> _arabicDigits = {
  '٠': '0',
  '١': '1',
  '٢': '2',
  '٣': '3',
  '٤': '4',
  '٥': '5',
  '٦': '6',
  '٧': '7',
  '٨': '8',
  '٩': '9',
};

const Map<String, int> _numWords = {
  'শূন্য': 0,
  'সিফর': 0,
  'জিরো': 0,
  'এক': 1,
  'দুই': 2,
  'দু': 2,
  'তিন': 3,
  'চার': 4,
  'পাঁচ': 5,
  'ছয়': 6,
  'সাত': 7,
  'আট': 8,
  'নয়': 9,
  'দশ': 10,
  'এগারো': 11,
  'এগার': 11,
  'বারো': 12,
  'তেরো': 13,
  'চৌদ্দ': 14,
  'পনেরো': 15,
  'ষোল': 16,
  'সতেরো': 17,
  'আঠারো': 18,
  'ঊনিশ': 19,
  'উনিশ': 19,
  'বিশ': 20,
  'ত্রিশ': 30,
  'চল্লিশ': 40,
  'পঞ্চাশ': 50,
  'ষাট': 60,
  'সত্তর': 70,
  'আশি': 80,
  'নব্বই': 90,
  'একুশ': 21,
  'বাইশ': 22,
  'তেইশ': 23,
  'চব্বিশ': 24,
  'পঁচিশ': 25,
  'ছাব্বিশ': 26,
  'সাতাশ': 27,
  'আঠাশ': 28,
  'উনত্রিশ': 29,
  'একত্রিশ': 31,
  'বত্রিশ': 32,
  'তেত্রিশ': 33,
  'চৌত্রিশ': 34,
  'পঁয়ত্রিশ': 35,
  'ছত্রিশ': 36,
  'সাইত্রিশ': 37,
  'আটত্রিশ': 38,
  'উনচল্লিশ': 39,
  'একচল্লিশ': 41,
  'বিয়াল্লিশ': 42,
  'তেতাল্লিশ': 43,
  'চুয়াল্লিশ': 44,
  'পঁয়তাল্লিশ': 45,
  'ছেচল্লিশ': 46,
  'সাতচল্লিশ': 47,
  'আটচল্লিশ': 48,
  'উনপঞ্চাশ': 49,
  'একান্ন': 51,
  'বায়ান্ন': 52,
  'তেপ্পান্ন': 53,
  'চুয়ান্ন': 54,
  'পঞ্চান্ন': 55,
  'ছাপ্পান্ন': 56,
  'সাতান্ন': 57,
  'আটান্ন': 58,
  'উনষাট': 59,
  'একষট্টি': 61,
  'বাষট্টি': 62,
  'তেষট্টি': 63,
  'চৌষট্টি': 64,
  'পঁয়ষট্টি': 65,
  'ছয়ষট্টি': 66,
  'সাতষট্টি': 67,
  'আটষট্টি': 68,
  'উনসত্তর': 69,
  'একাত্তর': 71,
  'বাহাত্তর': 72,
  'তেহাত্তর': 73,
  'চৌহাত্তর': 74,
  'পঁচাত্তর': 75,
  'ছিয়াত্তর': 76,
  'সাতাত্তর': 77,
  'আটাত্তর': 78,
  'উনআশি': 79,
  'একাশি': 81,
  'বিরাশি': 82,
  'তিরাশি': 83,
  'চুরাশি': 84,
  'পঁচাশি': 85,
  'ছিয়াশি': 86,
  'সাতাশি': 87,
  'আটাশি': 88,
  'নিরাশি': 89,
  'একানব্বই': 91,
  'বিরানব্বই': 92,
  'তিরানব্বই': 93,
  'চুরানব্বই': 94,
  'পঁচানব্বই': 95,
  'ছিয়ানব্বই': 96,
  'সাতানব্বই': 97,
  'আটানব্বই': 98,
  'নিরানব্বই': 99,
  'একশ': 100,
  'একশত': 100,
  'দেড়শ': 150,
  'দেড়শত': 150,
  'দুইশ': 200,
  'দুইশত': 200,
  'আড়াইশ': 250,
  'আড়াইশত': 250,
  'তিনশ': 300,
  'চারশ': 400,
  'পাঁচশ': 500,
  'ছয়শ': 600,
  'সাতশ': 700,
  'আটশ': 800,
  'নয়শ': 900,
  'zero': 0,
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
  'ten': 10,
  'eleven': 11,
  'twelve': 12,
  'thirteen': 13,
  'fourteen': 14,
  'fifteen': 15,
  'sixteen': 16,
  'seventeen': 17,
  'eighteen': 18,
  'nineteen': 19,
  'twenty': 20,
  'thirty': 30,
  'forty': 40,
  'fifty': 50,
  'sixty': 60,
  'seventy': 70,
  'eighty': 80,
  'ninety': 90,
  'hundred': 100,
};

const Map<String, int> _months = {
  'january': 1,
  'february': 2,
  'march': 3,
  'april': 4,
  'may': 5,
  'june': 6,
  'july': 7,
  'august': 8,
  'september': 9,
  'october': 10,
  'november': 11,
  'december': 12,
  'জানুয়ারি': 1,
  'জানুয়ারী': 1,
  'ফেব্রুয়ারি': 2,
  'ফেব্রুয়ারী': 2,
  'মার্চ': 3,
  'এপ্রিল': 4,
  'মে': 5,
  'জুন': 6,
  'জুলাই': 7,
  'আগস্ট': 8,
  'সেপ্টেম্বর': 9,
  'অক্টোবর': 10,
  'নভেম্বর': 11,
  'ডিসেম্বর': 12,
};

String _pad2(Object n) {
  final s = n.toString();
  return s.length < 2 ? '0$s' : s;
}

/// Recursively each number word; also merge "twenty five" -> 25.
String _convertNumberWords(String str) {
  if (str.isEmpty) return str;
  final tokens = str.split(RegExp(r'\s+'));
  final result = <String>[];
  for (final tok in tokens) {
    final bare = tok.replaceAll(
      RegExp(
        r'[।,.;:!?()\[\]{}'
        "']",
      ),
      '',
    );
    if (_numWords.containsKey(bare)) {
      result.add(_numWords[bare].toString());
    } else if (bare == 'শ' || bare == 'শত') {
      final last = result.isEmpty ? '' : result.last;
      if (RegExp(r'^\d+$').hasMatch(last)) {
        result[result.length - 1] = (int.parse(last) * 100).toString();
      } else {
        result.add('100');
      }
    } else if (bare == 'হাজার') {
      final last = result.isEmpty ? '' : result.last;
      if (RegExp(r'^\d+$').hasMatch(last)) {
        result[result.length - 1] = (int.parse(last) * 1000).toString();
      } else {
        result.add('1000');
      }
    } else {
      result.add(tok);
    }
  }
  for (var j = 0; j < result.length - 1; j++) {
    if (RegExp(r'^(20|30|40|50|60|70|80|90)$').hasMatch(result[j]) &&
        RegExp(r'^[1-9]$').hasMatch(result[j + 1])) {
      result[j] = (int.parse(result[j]) + int.parse(result[j + 1])).toString();
      result.removeAt(j + 1);
    }
  }
  return result.join(' ');
}

/// Convert Bengali/Arabic digits + spoken number words to Latin digits.
String toLatinDigits(String str) {
  var s = str;
  _banglaDigits.forEach((k, v) => s = s.replaceAll(k, v));
  _arabicDigits.forEach((k, v) => s = s.replaceAll(k, v));
  return _convertNumberWords(s);
}

String _normalizeDob(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return '';
  Match? m;
  m = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$').firstMatch(v);
  if (m != null) {
    return '${m.group(1)}-${_pad2(m.group(2)!)}-${_pad2(m.group(3)!)}';
  }
  m = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})$').firstMatch(v);
  if (m != null) {
    return '${m.group(3)}-${_pad2(m.group(2)!)}-${_pad2(m.group(1)!)}';
  }
  m = RegExp(r'(\d{4})\s+(\d{1,2})\s+([A-Za-z\u0980-\u09FF]+)').firstMatch(v);
  if (m != null) {
    final mn = _months[m.group(3)!.toLowerCase()];
    if (mn != null) return '${m.group(1)}-${_pad2(mn)}-${_pad2(m.group(2)!)}';
  }
  m = RegExp(r'(\d{1,2})\s+([A-Za-z\u0980-\u09FF]+)\s+(\d{4})').firstMatch(v);
  if (m != null) {
    final mn = _months[m.group(2)!.toLowerCase()];
    if (mn != null) return '${m.group(3)}-${_pad2(mn)}-${_pad2(m.group(1)!)}';
  }
  return v;
}

bool _isRealDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return false;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day;
}

String _esc(String s) =>
    s.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (m) => '\\${m[0]}');

bool _hasWord(String str, String word) {
  final re = RegExp(
    '(^|[^\\w\\u0980-\\u09FF])${_esc(word)}([^\\w\\u0980-\\u09FF]|\$)',
    caseSensitive: false,
  );
  return re.hasMatch(str);
}

/// Mirrors JS `String.slice` (clamps + never throws) for overlapping labels.
String _slice(String s, int a, int b) {
  if (a < 0) a = 0;
  if (b < 0) b = 0;
  if (b < a) return '';
  if (a > s.length) a = s.length;
  if (b > s.length) b = s.length;
  return s.substring(a, b);
}

/// Structured parser — mirrors `parseStudentInfo` from ai-parsers.js.
/// Returns a map of parsed fields (empty map if nothing recognised).
Map<String, String> parseStudentPrompt(String text) {
  final raw = toLatinDigits(text);
  final data = <String, String>{};
  void set(String key, String? val) {
    if (val != null && val.trim().isNotEmpty) data[key] = val.trim();
  }

  const fields = <List<Object>>[
    [
      'name',
      ['name', 'student name', 'ছাত্রের নাম', 'নাম'],
    ],
    [
      'roll',
      ['roll', 'roll no', 'roll number', 'রোল'],
    ],
    [
      'class',
      ['class', 'শ্রেণী', 'শ্রেণি', 'ক্লাস'],
    ],
    [
      'group',
      ['group', 'গ্রুপ', 'বিভাগ'],
    ],
    [
      'section',
      ['section', 'শাখা', 'sec'],
    ],
    [
      'gender',
      ['gender', 'sex', 'লিঙ্গ', 'জেন্ডার'],
    ],
    // NOTE: no bare 'birth' label here — it used to swallow the
    // "Birth Certificate No:" line and dump the 17-digit number into DOB.
    [
      'dob',
      ['date of birth', 'birth date', 'dob', 'জন্মতারিখ', 'জন্ম তারিখ'],
    ],
    [
      'birth_cert_no',
      [
        'birth certificate no',
        'birth certificate number',
        'birth certificate',
        'birth cert',
        'birth reg',
        'birth registration',
        'birth registration no',
        'জন্ম নিবন্ধন',
        'জন্মনিবন্ধন',
        'জন্ম সনদ',
        'জন্মসনদ',
      ],
    ],
    [
      'religion',
      ['religion', 'ধর্ম'],
    ],
    [
      'blood_group',
      ['blood group', 'blood', 'রক্ত', 'রক্তের গ্রুপ'],
    ],
    [
      'optional_subject',
      [
        'optional subject',
        'optional',
        'oecho',
        'ঐচ্ছিক বিষয়',
        'ঐচ্ছিক',
        'নৈবিক বিষয়',
        'অপশনাল',
      ],
    ],
    [
      'father_name',
      ["father's name", 'father name', 'father', 'পিতার নাম', 'পিতা'],
    ],
    [
      'mother_name',
      ["mother's name", 'mother name', 'mother', 'মাতার নাম', 'মাতা'],
    ],
    [
      'phone',
      ['phone', 'mobile', 'contact', 'ফোন', 'মোবাইল'],
    ],
    [
      'email',
      ['email', 'ইমেইল', 'মেইল'],
    ],
    [
      'guardian_name',
      ['guardian name', 'guardian', 'অভিভাবকের নাম', 'অভিভাবক'],
    ],
    [
      'guardian_phone',
      ['guardian phone', 'guardian contact', 'অভিভাবক ফোন', 'অভিভাবক নম্বর'],
    ],
    [
      'address',
      [
        'address',
        'present address',
        'current address',
        'permanent address',
        'residential address',
        'village',
        'location',
        'ঠিকানা',
        'বর্তমান ঠিকানা',
        'স্থায়ী ঠিকানা',
        'বাসস্থান',
        'residence',
      ],
    ],
    [
      'student_id',
      ['student id', 'student no', 'id', 'student code'],
    ],
  ];

  final hits = <({String key, int index, int end})>[];
  for (final f in fields) {
    final key = f[0] as String;
    for (final lab in f[1] as List<String>) {
      final labelRe = RegExp(
        '(^|\\s)${_esc(lab)}\\s*[:\\-\\=]?\\s*',
        caseSensitive: false,
      );
      for (final mItem in labelRe.allMatches(raw)) {
        final sep = (mItem.group(1) ?? '').length;
        hits.add((key: key, index: mItem.start + sep, end: mItem.end));
      }
    }
  }
  // Drop nested/shadowed labels: when two labels start at the same index keep
  // the longest (more specific); when a label starts inside an already-kept
  // label's span (e.g. 'name' inside "Guardian Name") drop it too. This keeps
  // values clean even for sequential "Guardian Name:" / "Guardian Phone:" rows.
  hits.sort((a, b) {
    if (a.index != b.index) return a.index - b.index;
    return b.end - a.end;
  });
  final kept = <({String key, int index, int end})>{};
  for (final h in hits) {
    if (kept.isNotEmpty) {
      final last = kept.last;
      if (h.index >= last.index && h.index <= last.end) {
        continue;
      }
    }
    kept.add(h);
  }
  final keptList = kept.toList()..sort((a, b) => a.end.compareTo(b.end));
  for (var i = 0; i < keptList.length; i++) {
    final h = keptList[i];
    final nextStart = (i + 1 < keptList.length)
        ? keptList[i + 1].index
        : raw.length;
    final prevEnd = (i > 0) ? keptList[i - 1].end : 0;
    final after = _slice(
      raw,
      h.end,
      nextStart,
    ).trim().replaceFirst(RegExp(r'[:.,;]+$'), '');
    final before = _slice(
      raw,
      prevEnd,
      h.index,
    ).trim().replaceFirst(RegExp(r'^[:.,;\s]+'), '');
    final val = after.isNotEmpty ? after : before;
    if (val.isNotEmpty) set(h.key, val);
  }

  if (!data.containsKey('group')) {
    if (_hasWord(raw, 'বিজ্ঞান') ||
        _hasWord(raw, 'সায়েন্স') ||
        _hasWord(raw, 'সায়েন্স') ||
        RegExp(r'\bscience\b', caseSensitive: false).hasMatch(raw)) {
      data['group'] = 'Science';
    } else if (_hasWord(raw, 'ব্যবসায়') ||
        _hasWord(raw, 'ব্যবসায়') ||
        _hasWord(raw, 'কমার্স') ||
        RegExp(
          r'\b(commerce|business)\b',
          caseSensitive: false,
        ).hasMatch(raw)) {
      data['group'] = 'Commerce';
    } else if (_hasWord(raw, 'মানবিক') ||
        RegExp(r'\b(arts|humanities)\b', caseSensitive: false).hasMatch(raw)) {
      data['group'] = 'Arts';
    }
  }

  final out = <String, String>{};
  if (data.containsKey('name')) {
    out['name'] = data['name']!.replaceFirst(RegExp(r'\.$'), '');
  }
  if (data.containsKey('roll')) {
    final r = int.tryParse(data['roll']!);
    if (r != null) out['roll'] = r.toString();
  }
  if (data.containsKey('class')) {
    final c = int.tryParse(data['class']!);
    if (c != null && c >= 1 && c <= 12) out['class'] = c.toString();
  }
  if (data.containsKey('group')) {
    final g = data['group']!.toLowerCase();
    if (_hasWord(g, 'science') ||
        _hasWord(g, 'বিজ্ঞান') ||
        _hasWord(g, 'সায়েন্স') ||
        _hasWord(g, 'সায়েন্স')) {
      out['group'] = 'Science';
    } else if (_hasWord(g, 'commerce') ||
        _hasWord(g, 'business') ||
        _hasWord(g, 'ব্যবসায়') ||
        _hasWord(g, 'ব্যবসায়') ||
        _hasWord(g, 'কমার্স') ||
        _hasWord(g, 'বাণিজ্য')) {
      out['group'] = 'Commerce';
    } else if (_hasWord(g, 'arts') ||
        _hasWord(g, 'humanities') ||
        _hasWord(g, 'মানবিক')) {
      out['group'] = 'Arts';
    }
  }
  if (data.containsKey('section')) {
    final sv = data['section']!.trim().toUpperCase();
    final sm = RegExp(r'\b[ABC]\b').firstMatch(sv);
    if (sm != null) {
      out['section'] = sm.group(0)!;
    } else if (sv == 'এ') {
      out['section'] = 'A';
    } else if (sv == 'বি') {
      out['section'] = 'B';
    } else if (sv == 'সি') {
      out['section'] = 'C';
    }
  }
  if (data.containsKey('gender')) {
    // Female FIRST with word boundaries: plain contains('male') would match
    // "Female" and mislabel girls as Male (e.g. Nosaiba Noha).
    final gd = data['gender']!.toLowerCase().trim();
    if (gd.contains('female') ||
        gd.contains('মেয়ে') ||
        _hasWord(gd, 'girl') ||
        gd == 'f' ||
        _hasWord(gd, 'নারী')) {
      out['gender'] = 'Female';
    } else if (_hasWord(gd, 'male') ||
        _hasWord(gd, 'boy') ||
        gd == 'm' ||
        gd.contains('ছেলে') ||
        _hasWord(gd, 'পুরুষ')) {
      out['gender'] = 'Male';
    } else {
      out['gender'] = 'Other';
    }
  }
  if (data.containsKey('dob')) {
    final d = _normalizeDob(data['dob']!);
    // Strict, real YYYY-MM-DD only — never a birth-certificate number.
    if (_isRealDate(d)) {
      out['dob'] = d;
    }
  }
  if (data.containsKey('birth_cert_no')) {
    // Only populate the admission field when the complete value is a
    // 17-digit registration number; never salvage a partial or mixed value.
    final raw = data['birth_cert_no']!.trim();
    final digits = raw.replaceAll(RegExp(r'[\s-]'), '');
    if (RegExp(r'^\d{17}$').hasMatch(digits)) {
      out['birth_cert_no'] = digits;
    }
  }
  if (data.containsKey('religion')) {
    final rl = data['religion']!.toLowerCase();
    if (rl.contains('islam') || rl.contains('ইসলাম')) {
      out['religion'] = 'Islam';
    } else if (rl.contains('hindu') || rl.contains('হিন্দু')) {
      out['religion'] = 'Hinduism';
    } else if (rl.contains('christ') || rl.contains('খ্রিস্ট')) {
      out['religion'] = 'Christianity';
    } else if (rl.contains('buddh') || rl.contains('বৌদ্ধ')) {
      out['religion'] = 'Buddhism';
    } else if (rl.contains('other') || rl.contains('অন্য')) {
      out['religion'] = 'Other';
    }
  }
  if (data.containsKey('blood_group')) {
    final bm = RegExp(r'(A|B|AB|O)[+-]')
        .firstMatch(data['blood_group']!.toUpperCase());
    if (bm != null) {
      out['blood_group'] = bm.group(0)!;
    } else if (RegExp(
      r'unknown|জানা নেই',
      caseSensitive: false,
    ).hasMatch(data['blood_group']!.toLowerCase())) {
      out['blood_group'] = 'Unknown';
    }
  }
  if (data.containsKey('optional_subject')) {
    final os = data['optional_subject']!.toLowerCase();
    if (os.contains('home science') ||
        os.contains('গৃহ') ||
        os.contains('হোম')) {
      out['optional_subject'] = 'Home Science';
    } else if (os.contains('higher') ||
        os.contains('উচ্চ') ||
        os.contains('হায়ার') ||
        os.contains('highermath')) {
      out['optional_subject'] = 'Higher Mathematics';
    } else if (os.contains('agriculture') || os.contains('কৃষি')) {
      out['optional_subject'] = 'Agriculture Studies';
    } else {
      out['optional_subject'] = data['optional_subject']!
          .replaceFirst(RegExp(r'\.$'), '')
          .trim();
    }
  }
  for (final k in const [
    'father_name',
    'mother_name',
    'guardian_name',
    'address',
    'email',
    'student_id',
  ]) {
    if (data.containsKey(k)) out[k] = data[k]!.replaceFirst(RegExp(r'\.$'), '');
  }
  if (data.containsKey('phone')) {
    out['phone'] = data['phone']!.replaceAll(RegExp(r'[\s\-]'), '');
  }
  if (data.containsKey('guardian_phone')) {
    out['guardian_phone'] = data['guardian_phone']!.replaceAll(
      RegExp(r'[\s\-]'),
      '',
    );
  }
  return out;
}
