# -*- coding: utf-8 -*-
from __future__ import print_function
import io, os

BASE = 'C:/Users/WALTON/Desktop/school-system'


def rd(p):
    b = io.open(p, 'rb').read()
    for e in ('utf-8', 'utf-8-sig'):
        try:
            t = b.decode(e)
            if '\x00' not in t:
                return t
        except Exception:
            pass
    return b.decode('latin-1')


def wr(p, t):
    io.open(p if os.path.isabs(p) else os.path.join(BASE, p),
            'w', encoding='utf-8', newline='').write(t)


P = 'apps/teacher_app/lib/screens/student_registration_screen.dart'
t = rd(P)

# STEP 1 — hoist the template + roll-parser to top-level private helpers
# Old members (methods on the registration state class):
old_def = '  String _promptTemplate() {'
print('  def anchor count=%d' % t.count(old_def))

# STEP 2 — replace the whole method body block (lines 121-139) with top-level fns.
frag = '''  /// চ structural Bengali copy template — key fields + ID is auto / roll is manual.
  String _promptTemplate() {
    final section = widget.classLabel.toLowerCase().contains('group')
        ? 'গ্রুপ (Group) + '
        : 'বিভাগ (Section) + ';
    return '''CLSS: ${widget.classLabel}
ছাত্র / ছাত্রীর তথ্য অনুসরণ করুন বিশ্লেষণ করে নিচের FORMAT-এ ফেরত পাঠান — JSON row:
{ "name": "...", "roll": "বাস্তব রোল", "dob": "YYYY-MM-DD", "religion": "...",
  "guardian_name": "...", "guardian_phone": "...", "father_name": "...",
  "mother_name": "...", "birth_cert_no": "...", "address": "...",
  "${widget.classLabel.contains('group') ? 'group' : 'section'}": "..." }

RULES:
- Student কোড (Student Code / Code): সার্ভার স্বয়ংক্রিয়ভাবে তৈরি করবে — লিখবেন না।
- রোল (Roll): শুধু এই Fিল্ডটি ম্যানুয়াল/ইমপোর্ট prompt থেকে আসে — বাধ্যতামূলকভাবে ভরুন যাচাই করে,
  প্লিজ school-এর এই ক্লাসের (${widget.classLabel}) ${section}স্বয়ংক্রিয় Code+Roll থেকে আলাদা ভাবে রেখে দিন।
- নিচের Prompt-এ নামের পাশে থাকা রোলটি পড়ে 'roll' কী-তে ভরুন.''';
  }

  /// Parser — reads a Bangla/English prompt blob and extracts 'Roll'/'রোল' into the roll input.
  void _parsePromptText(String raw) {
    // extract manually stated roll: রোল: 12 / Roll: 12 / রোল ১২ / roll=12
    final rg1 = RegExp(r'''[Rr]oll|রোল''');
    final m = rg1.firstMatch(raw);
    if (m != null) {
      final tail = raw.substring(m.end);
      final mv = RegExp(r'[:=]?\s*(\d+)').firstMatch(tail);
      if (mv != null) setState(() => _rollCtl.text = mv.group(1) ?? '');
    }
    // auto-fill other section/group if present with section label
    final sec = RegExp(
      r'(?:section|group|গ্রুপ|বিভাগ)\s*[:=]?\s*([শালা-হা-zA-Z0-9]+)',
    ).firstMatch(raw.toLowerCase());
    if (sec != null && _sectionGroupCtl.text.isEmpty) {
      setState(() => _sectionGroupCtl.text = sec.group(1) ?? '');
    }
  }
'''

new_frag = '''  /// চ structural Bengali copy template — key fields + ID is auto / roll is manual.
  String get _promptTemplate =>
      _bunkPromptTemplate(widget.classLabel, widget.sectionLabel);

  /// Parser — roll into controller / section-group into controller.
  void _parsePromptText(String raw) {
    _bunkParsePrompt(
      raw,
      roll: (v) => setState(() => _rollCtl.text = v),
      section: (v) {
        if (_sectionGroupCtl.text.isEmpty) {
          setState(() => _sectionGroupCtl.text = v);
        }
      },
    );
  }
'''

# 3) Also add the two top-level helpers at end of file (after final closing brace line).
top = '''
/// চ prompt template (shared by import-dialog clipboard + AI auto-fill).
String _bunkPromptTemplate(String classLabel, String sectionLabel) {
  final section = classLabel.toLowerCase().contains('group')
      ? 'গ্রুপ (Group) + '
      : 'বিভাগ (Section) + ';
  final slug = classLabel.toLowerCase().contains('group') ? 'group' : 'section';
  return '''CLSS: $classLabel
ছাত্র / ছাত্রীর তথ্য অনুসরণ করুন বিশ্লেষণ করে নিচের FORMAT-এ ফেরত পাঠান — JSON row:
{ "name": "...", "roll": "বাস্তব রোল", "dob": "YYYY-MM-DD", "religion": "...",
  "guardian_name": "...", "guardian_phone": "...", "father_name": "...",
  "mother_name": "...", "birth_cert_no": "...", "address": "...",
  "$slug": "..." }

RULES:
- Student কোড (Student Code / Code): সার্ভার স্বয়ংক্রিয়ভাবে তৈরি করবে — লিখবেন না।
- রোল (Roll): শুধু এই ফিল্ডটি ম্যানুয়াল/ইমপোর্ট prompt থেকে আসে — বাধ্যতামূলকভাবে ভরুন যাচাই করে,
  প্লিজ school-এর এই ক্লাসের ($classLabel) $sectionস্বয়ংক্রিয় Code+Roll থেকে আলাদা ভাবে রেখে দিন।
- নিচের Prompt-এ নামের পাশে থাকা রোলটি পড়ে 'roll' কী-তে ভরুন.''';
}

/// Parser — Bangla/English prompt blob → roll + section helpers.
void _bunkParsePrompt(
  String raw, {
  required void Function(String) roll,
  void Function(String)? section,
}) {
  final rg1 = RegExp(r'''[Rr]oll|রোল''');
  final m = rg1.firstMatch(raw);
  if (m != null) {
    final tail = raw.substring(m.end);
    final mv = RegExp(r'[:=]?\s*(\d+)').firstMatch(tail);
    if (mv != null) roll(mv.group(1) ?? '');
  }
  final sec = RegExp(
    r'(?:section|group|গ্রুপ|বিভাগ)\s*[:=]?\s*([শা-হা-zA-Z0-9]+)',
  ).firstMatch(raw.toLowerCase());
  if (sec != null && section != null) section(sec.group(1) ?? '');
}
'''

# 4) window title: the dialog BUTTON target refers to a getter — already fine.
old_call = 'ClipboardData(text: _promptTemplate),'
new_call = 'ClipboardData(text: _promptTemplate),'
print('  call anchor count=%d (expect 0/1 depending on final state)' % t.count(old_call))

# Apply if present:
if t.count(old_call) == 1:
    t = t.replace(old_call, new_call)
    wr(P, t)
    print('  PATCH1 call -> getter ok')
else:
    # method-call form is the current body; that is what new _bunkPromptTemplate replaces
    pass

# Replace the OLD two-member block with the new getter+parser version:
if t.count(frag) == 1:
    t = t.replace(frag, new_frag)
    wr(P, t)
    print('  PATCH2 members -> getter + lean parser ok')
else:
    print('  PATCH2 SKIP frag count=%d' % t.count(frag))

# Append top-level helpers once (guard)
t = rd(P)
if '_bunkPromptTemplate(' not in t:
    t = t.rstrip() + '\n' + top
    wr(P, t)
    print('  PATCH3 top-level helpers appended ok')
else:
    print('  PATCH3 helpers already present')

print('\nDONE — teacher_app student_registration hoisted to shared top-level helpers.')
