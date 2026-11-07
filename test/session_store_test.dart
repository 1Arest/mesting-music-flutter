import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/security/session_store.dart';
import 'package:mesting_music/features/auth/domain/auth_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('active sign-out keeps an encrypted remembered account', () async {
    final store = SessionStore();
    final session = AuthSession(
      user: const AuthUser(
        uid: 'remembered-user',
        nickname: 'Mesting',
        phoneMasked: '138****5678',
      ),
      accessToken: 'access',
      refreshToken: 'refresh',
      expiresAt: DateTime.utc(2099),
    );

    await store.write(session);
    await store.clear();

    expect(await store.read(), isNull);
    expect((await store.readRemembered())?.user.uid, 'remembered-user');

    await store.restoreRememberedAsActive();
    expect((await store.read())?.refreshToken, 'refresh');

    await store.clearAll();
    expect(await store.read(), isNull);
    expect(await store.readRemembered(), isNull);
  });
}
