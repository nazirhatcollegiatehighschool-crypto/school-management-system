import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:guardian_app/fcm_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'push notifications are enabled by default for existing users',
    () async {
      SharedPreferences.setMockInitialValues({});
      expect(await isPushNotificationsEnabled(), isTrue);
    },
  );

  test('a saved opt-out is respected on the next login', () async {
    SharedPreferences.setMockInitialValues({
      'push_notifications_enabled': false,
    });
    expect(await isPushNotificationsEnabled(), isFalse);
  });
}
