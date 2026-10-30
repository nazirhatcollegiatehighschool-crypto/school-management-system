import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/update_check.dart';

void main() {
  test('compares semantic version components numerically', () {
    expect(isNewerVersion('1.4.10', '1.4.9'), isTrue);
    expect(isNewerVersion('1.4.9', '1.4.10'), isFalse);
  });

  test('recognizes a newer build when the display version is unchanged', () {
    final decision = decideUpdate(
      serverVersion: '1.4.5',
      serverBuild: 14,
      installedVersion: '1.4.5',
      installedBuild: 13,
    );

    expect(decision.newer, isTrue);
  });

  test('rejects same or older builds', () {
    final decision = decideUpdate(
      serverVersion: '1.4.5',
      serverBuild: 13,
      installedVersion: '1.4.5',
      installedBuild: 13,
    );

    expect(decision.newer, isFalse);
    expect(
      decideUpdate(
        serverVersion: '1.4.5',
        serverBuild: 12,
        installedVersion: '1.4.5',
        installedBuild: 13,
      ).newer,
      isFalse,
    );
  });

  test('requires a complete hexadecimal SHA-256 checksum', () {
    expect(hasValidApkSha256(List.filled(64, 'a').join()), isTrue);
    expect(hasValidApkSha256(List.filled(64, 'A').join()), isTrue);
    expect(hasValidApkSha256(List.filled(63, 'a').join()), isFalse);
    expect(hasValidApkSha256(List.filled(64, 'g').join()), isFalse);
    expect(hasValidApkSha256(null), isFalse);
  });
}
