import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_app/student_prompt_parser.dart';

void main() {
  group('parseStudentPrompt', () {
    test('parses Bengali prompt blob with all fields', () {
      const text = '''
Name: Anik Chowdhury
Class: 10
Group: Science
Roll: ১২
Father's Name: Md. Jahangir Chowdhury
Mother's Name: Hosne Ara Begum
Guardian Name: Jahangir Chowdhury
Guardian Phone: ০১৭১২৩৪৫৬৭৮
Phone: 01798765432
Date of Birth: 12-05-2013
Gender: Male
Religion: ইসলাম
Blood Group: B+
Optional Subject: Higher Mathematics
Email: anik@example.com
Address: village, Chattogram
''';
      final r = parseStudentPrompt(text);
      expect(r['name'], 'Anik Chowdhury');
      expect(r['roll'], '12');
      expect(r['class'], '10');
      expect(r['group'], 'Science');
      expect(r['father_name'], 'Md. Jahangir Chowdhury');
      expect(r['mother_name'], 'Hosne Ara Begum');
      expect(r['guardian_name'], 'Jahangir Chowdhury');
      expect(r['guardian_phone'], '01712345678');
      expect(r['phone'], '01798765432');
      expect(r['dob'], '2013-05-12');
      expect(r['gender'], 'Male');
      expect(r['religion'], 'Islam');
      expect(r['blood_group'], 'B+');
      expect(r['optional_subject'], 'Higher Mathematics');
      expect(r['email'], 'anik@example.com');
      expect(r['address'], 'village, Chattogram');
    });

    test('inline single-line blob captures next-label values', () {
      const text =
          'নাম: Rahim Roll: 5 পিতা: Karim মাতা: Rahim Sultana'; // ignore: lines_longer_than_80_chars
      final r = parseStudentPrompt(text);
      expect(r['name'], 'Rahim');
      expect(r['roll'], '5');
      expect(r['father_name'], 'Karim');
    });

    test('empty / gibberish returns empty map', () {
      expect(parseStudentPrompt(''), isEmpty);
      expect(parseStudentPrompt('random gibberish words here'), isEmpty);
    });

    test('bare group keyword inference', () {
      final r = parseStudentPrompt('Name: X, subject Commerce group, Roll: 2');
      expect(r['group'], 'Commerce');
      // Name captures everything up to the next label (mirrors ai-parsers.js).
      expect(r['name'], 'X, subject Commerce');
      expect(r['roll'], '2');
    });
  });

  group('father/mother after each other', () {
    test('two-name edge: পিতা then মাতা not confused by نام label', () {
      const text = 'নাম: Sumaiya Rahman, পিতা: Rahman, মাতা: Hasina';
      final r = parseStudentPrompt(text);
      expect(r['name'], 'Sumaiya Rahman');
      expect(r['father_name'], 'Rahman');
      expect(r['mother_name'], 'Hasina');
    });
  });

  group('strict field mapping (AI instruction)', () {
    test('Female never mislabelled Male; cert never leaks into DOB', () {
      const text = '''
Name: Nosaiba Noha
Roll: 7
Date of Birth: 2011-05-15
Gender: Female
Birth Certificate No: 20110515001234567
''';
      final r = parseStudentPrompt(text);
      expect(r['dob'], '2011-05-15');
      expect(r['gender'], 'Female');
      expect(r['birth_cert_no'], '20110515001234567');
    });

    test('DD-MM-YYYY still normalizes; bare cert-like value rejected from DOB', () {
      const text = 'Name: T\nDate of Birth: 15-05-2011\nGender: মেয়ে';
      final r = parseStudentPrompt(text);
      expect(r['dob'], '2011-05-15');
      expect(r['gender'], 'Female');
    });
  });
}