import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zic/state/app_kv.dart';

/// AppKv keeps the first [AppKv.open] future for the process. A
/// testWidgets runs in its own fake-async zone, and the next test's
/// await on that future never resumes. Reset before every test.
Future<void> testExecutable(Future<void> Function() testMain) async {
  setUp(() {
    AppKv.instance.debugReset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });
  await testMain();
}
