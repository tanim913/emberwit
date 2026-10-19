import 'package:emberwit/features/onboarding/presentation/onboarding_page.dart';
import 'package:emberwit/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a fresh install starts on onboarding', (tester) async {
    await app.main();
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingPage), findsOneWidget);
  });
}
