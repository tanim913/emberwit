import 'package:emberwit/app/theme/app_theme.dart';
import 'package:emberwit/features/chat/domain/chat_models.dart';
import 'package:emberwit/features/chat/presentation/widgets/message_view.dart';
import 'package:emberwit/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessage _reply(String content, {MessageStats? stats}) => ChatMessage(
  id: 'm',
  conversationId: 'c',
  role: MessageRole.assistant,
  content: content,
  createdAt: DateTime.utc(2026),
  stats: stats,
);

Future<List<Uri>> _pump(WidgetTester tester, ChatMessage message) async {
  final opened = <Uri>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: SingleChildScrollView(
          child: MessageView(
            message: message,
            openLink: (uri) async {
              opened.add(uri);
              return true;
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return opened;
}

String _allText(WidgetTester tester) => [
  for (final w in tester.widgetList<SelectableText>(
    find.byType(SelectableText),
  ))
    w.data ?? w.textSpan?.toPlainText() ?? '',
  for (final r in tester.widgetList<RichText>(find.byType(RichText)))
    r.text.toPlainText(),
].join('\n');

void main() {
  testWidgets('renders markdown and hides thinking', (tester) async {
    await _pump(
      tester,
      _reply('<think>plan</think>**Stay calm.**\n\n- Water\n- Torch'),
    );
    final text = _allText(tester);
    expect(text, contains('Stay calm.'));
    expect(text, contains('Water'));
    expect(text, isNot(contains('plan')));
  });

  testWidgets('shows HTML as text, never interprets it', (tester) async {
    await _pump(
      tester,
      _reply('<script>alert(1)</script>\n\n<b>not bold</b> <img src="x">'),
    );
    final text = _allText(tester);
    expect(text, contains('<script>'));
    expect(text, contains('<b>not bold</b>'));
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('never loads images', (tester) async {
    await _pump(tester, _reply('![map](https://evil.example/track.png)'));
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('Image not loaded: map'), findsOneWidget);
  });

  testWidgets('opens links only after confirmation', (tester) async {
    final opened = await _pump(
      tester,
      _reply('See [the guide](https://example.org/floods).'),
    );
    await tester.tap(find.textContaining('the guide'));
    await tester.pumpAndSettle();
    expect(find.textContaining('https://example.org/floods'), findsWidgets);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);

    await tester.tap(find.textContaining('the guide'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-link')));
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse('https://example.org/floods')]);
  });

  testWidgets('ignores dangerous link schemes', (tester) async {
    final opened = await _pump(
      tester,
      _reply('[click](javascript:alert(1)) [file](file:///etc/passwd)'),
    );
    await tester.tap(find.textContaining('click'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.textContaining('file'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(opened, isEmpty);
  });

  testWidgets('code blocks have a copy button', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    await _pump(tester, _reply('Run:\n\n```bash\necho "hi"\n```'));
    await tester.tap(find.byKey(const Key('copy-code')));
    await tester.pumpAndSettle();
    expect(copied, ['echo "hi"']);
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('shows stats and user bubbles', (tester) async {
    await _pump(
      tester,
      _reply(
        'Done',
        stats: const MessageStats(
          promptTokens: 100,
          generatedTokens: 20,
          timeToFirstTokenMs: 450,
          tokensPerSecond: 11.25,
        ),
      ),
    );
    expect(
      find.text('11.3 tokens/s · first word 450 ms · 120 tokens used'),
      findsOneWidget,
    );
    await _pump(
      tester,
      ChatMessage(
        id: 'u',
        conversationId: 'c',
        role: MessageRole.user,
        content: 'আমার প্রশ্ন',
        createdAt: DateTime.utc(2026),
      ),
    );
    expect(find.text('আমার প্রশ্ন'), findsOneWidget);
  });
}
