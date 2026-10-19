import 'package:emberwit/app/theme/app_theme.dart';
import 'package:emberwit/features/chat/domain/chat_models.dart';
import 'package:emberwit/features/chat/presentation/widgets/message_view.dart';
import 'package:emberwit/features/chat/presentation/widgets/reply_math.dart';
import 'package:emberwit/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

/// Parses like `ReplyMarkdown` does and returns the math elements.
List<md.Element> _math(String text) {
  final document = md.Document(
    blockSyntaxes: const [BlockMathSyntax()],
    inlineSyntaxes: [InlineMathSyntax()],
    extensionSet: md.ExtensionSet.gitHubFlavored,
  );
  final found = <md.Element>[];
  void walk(List<md.Node> nodes) {
    for (final node in nodes) {
      if (node is! md.Element) continue;
      if (node.tag == inlineMathTag || node.tag == blockMathTag) {
        found.add(node);
      }
      walk(node.children ?? const []);
    }
  }

  walk(document.parseLines(separateDisplayMath(text).split('\n')));
  return found;
}

Future<void> _pump(
  WidgetTester tester,
  String text, {
  Locale locale = const Locale('en'),
  ThemeMode mode = ThemeMode.light,
  bool streaming = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: MessageView(
            streaming: streaming,
            message: ChatMessage(
              id: 'm',
              conversationId: 'c',
              role: MessageRole.assistant,
              content: text,
              createdAt: DateTime.utc(2026),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const String _quadratic =
    r'$$x^2 - 5x + 6 = 0$$Solving the equation: '
    r'$$\Rightarrow (x-2)(x-3) = 0$$So, $x = 2$ or $x = 3$.';

/// A long step-by-step answer in the forms small models mix: a display
/// equation opened at the end of a sentence, `\[`, line breaks without an
/// environment, `align*`, `\tag`, and a boxed answer last.
const String _longSolution = r'''
Solve $x^2 - 5x + 6 = 0$ step by step. First write the equation: $$
x^2 - 5x + 6 = 0
$$
Find two numbers whose product is $6$ and sum is $-5$: \[
(-2)(-3) = 6, \quad (-2) + (-3) = -5 \]
Factor and expand back to check:
$$
(x - 2)(x - 3) \\
= x^2 - 3x - 2x + 6 \\
= x^2 - 5x + 6 \\
$$
Each factor can be zero:
$$
\begin{align*}
x - 2 &= 0 \tag{1} \\
x - 3 &= 0 \tag{2}
\end{align*}
$$
So the roots are:
$$
\boxed{x = 2 \text{ or } x = 3}
$$
So $x = 2$ or $x = 3$.''';

void main() {
  group('parsing', () {
    test('finds all four delimiter forms', () {
      final found = _math(
        r'Inline $a+b$ and \(c\).'
        '\n\n'
        r'$$\frac{1}{2}$$'
        '\n\n'
        r'\[d^2\]',
      );
      expect(found.map((e) => e.textContent), [
        'a+b',
        'c',
        r'\frac{1}{2}',
        'd^2',
      ]);
      expect(found.map((e) => e.tag), [
        inlineMathTag,
        inlineMathTag,
        blockMathTag,
        blockMathTag,
      ]);
    });

    test('accepts spaced dollar math as small models write it', () {
      expect(
        _math(r"Let $ f(x) = x^2 $. At $ x = 1 $, slope $ f'(1) = 2 $.")
            .map((e) => e.textContent),
        ['f(x) = x^2', 'x = 1', "f'(1) = 2"],
      );
      expect(_math(r'For $ x $ only.').single.textContent, 'x');
    });

    test('a hugging price pair with a math character is still text', () {
      expect(_math(r'costs $20, not $30'), isEmpty);
      expect(_math(r'from $5 to $ 10 each'), isEmpty);
    });

    test('leaves prices, escaped dollars and code alone', () {
      expect(_math(r'It costs $5 and $10 today.'), isEmpty);
      expect(_math(r'Pay \$5 or \$x\$.'), isEmpty);
      expect(_math(r'Use `$x$` literally.'), isEmpty);
      expect(_math('```\n\$\$x\$\$\n```'), isEmpty);
      expect(_math(r'A lone $ sign'), isEmpty);
    });

    test('reads multiline display math', () {
      final found = _math(
        '\$\$\n\\begin{pmatrix}\n1 & 0 \\\\\n0 & 1\n\\end{pmatrix}\n\$\$',
      );
      expect(found.single.tag, blockMathTag);
      expect(found.single.textContent, contains(r'\begin{pmatrix}'));
    });

    test('keeps an unfinished display equation as text while streaming', () {
      expect(_math(r'$$x^2 +'), isEmpty);
    });

    test('an equation opened mid-sentence keeps later ones paired', () {
      final found = _math(_longSolution);
      expect(
        found.map((e) => e.tag).where((t) => t == blockMathTag),
        hasLength(5),
      );
      expect(found.last.textContent, 'x = 3');
      expect(found[found.length - 3].textContent, contains(r'\boxed'));
    });

    test('display math in a list item stays inline in display style', () {
      final found = _math(r'- root: $$x=2$$');
      expect(found.single.tag, inlineMathTag);
      expect(found.single.attributes['display'], 'true');
    });
  });

  group('separateDisplayMath', () {
    test('puts display equations from a sentence on their own lines', () {
      expect(
        separateDisplayMath(_quadratic),
        '\$\$x^2 - 5x + 6 = 0\$\$\n\nSolving the equation:\n\n'
        '\$\$\\Rightarrow (x-2)(x-3) = 0\$\$\n\nSo, \$x = 2\$ or \$x = 3\$.',
      );
      expect(
        separateDisplayMath(r'Thus \[a+b\] holds.'),
        'Thus\n\n\\[a+b\\]\n\nholds.',
      );
    });

    test('moves an equation opened at the end of a sentence', () {
      expect(
        separateDisplayMath('Write: \$\$\nx = 1\n\$\$\nDone \$\$y\$\$'),
        'Write:\n\n\$\$\nx = 1\n\$\$\nDone\n\n\$\$y\$\$',
      );
      expect(
        separateDisplayMath('Then \\[\na \\\\ b\n\\]'),
        'Then\n\n\\[\na \\\\ b\n\\]',
      );
      // Lines inside an equation are never split.
      const inside = '\$\$\nx = 1 \$\$ trailing\n';
      expect(separateDisplayMath(inside), inside);
    });

    test('closes an equation left open when the reply is finished', () {
      const cut = 'Hence:\n\$\$\nx = 2 \\\\\nx = 3';
      expect(separateDisplayMath(cut), cut);
      expect(separateDisplayMath(cut, closeOpen: true), '$cut\n\$\$');
      expect(_math(separateDisplayMath(cut, closeOpen: true)), hasLength(1));
    });

    test('leaves blocks, code, lists, quotes and plain text alone', () {
      const text =
          '\$\$x\$\$\n'
          '```\nx \$\$a\$\$ y\n```\n'
          'Use `\$\$a\$\$` here\n'
          '- item \$\$b\$\$ more\n'
          '> quote \$\$c\$\$\n'
          r'Price $10 and inline $x$ stay';
      expect(separateDisplayMath(text), text);
    });
  });

  group('prepareTex', () {
    test('turns full LaTeX environments into ones KaTeX has', () {
      expect(
        prepareTex(r'\begin{align*} a &= b \\ c &= d \end{align*}'),
        r'\begin{aligned} a &= b \\ c &= d \end{aligned}',
      );
      expect(prepareTex(r'\begin{equation} a = b \end{equation}'), 'a = b');
      expect(
        prepareTex(r'\begin{gather} a \\ b \end{gather}'),
        r'\begin{aligned}&a \\& b\end{aligned}',
      );
    });

    test('drops numbering', () {
      expect(prepareTex(r'x = 2 \tag{1} \label{eq} \nonumber'), 'x = 2');
      expect(prepareTex(r'\notag x'), 'x');
    });

    test('puts bare line breaks in aligned rows', () {
      expect(prepareTex(r'a \\ b \\'), r'\begin{aligned}&a \\& b\end{aligned}');
      expect(
        prepareTex(r'a &= b \\ c &= d'),
        r'\begin{aligned}a &= b \\ c &= d\end{aligned}',
      );
      expect(
        prepareTex(r'a \newline b'),
        r'\begin{aligned}&a \\& b\end{aligned}',
      );
    });

    test('leaves breaks inside environments and escaped & alone', () {
      const cases = r'\begin{cases} a & b \\ c & d \end{cases}';
      expect(prepareTex(cases), cases);
      expect(prepareTex(r'\text{A} \& B'), r'\text{A} \& B');
    });
  });

  testWidgets('a long solution is typeset to the very end', (tester) async {
    await _pump(tester, _longSolution);
    expect(tester.takeException(), isNull);
    // Nothing fell back to source: no TeX or delimiters left as text.
    for (final raw in [r'$$', r'\[', r'\\', r'\begin', r'\boxed', r'\tag']) {
      expect(find.textContaining(raw), findsNothing, reason: raw);
    }
    expect(find.byType(Math), findsNWidgets(10));
    final last = tester.getRect(find.byType(Math).last);
    final boxed = tester.getRect(find.byType(Math).at(7));
    expect(last.top, greaterThan(boxed.bottom - 1));
  });

  testWidgets('the reported answer lays out line by line', (tester) async {
    await _pump(tester, _quadratic);
    expect(find.byType(Math), findsNWidgets(4));
    final first = tester.getRect(find.byType(Math).at(0));
    final solving = tester.getRect(find.textContaining('Solving'));
    final second = tester.getRect(find.byType(Math).at(1));
    final so = tester.getRect(find.textContaining('So,'));
    expect(solving.top, greaterThanOrEqualTo(first.bottom - 1));
    expect(second.top, greaterThanOrEqualTo(solving.bottom - 1));
    expect(so.top, greaterThanOrEqualTo(second.bottom - 1));
  });

  testWidgets('inline equations flow inside the sentence', (tester) async {
    await _pump(tester, r'So, $x = 2$ or $x = 3$.');
    final paragraph = tester.widget<SelectableText>(
      find.byWidgetPredicate(
        (w) =>
            w is SelectableText &&
            (w.textSpan?.toPlainText(includePlaceholders: false) ?? '')
                .contains('So,'),
      ),
    );
    var widgets = 0;
    paragraph.textSpan!.visitChildren((span) {
      if (span is WidgetSpan) widgets++;
      return true;
    });
    expect(widgets, 2);
    expect(
      paragraph.textSpan!.toPlainText(includePlaceholders: false),
      'So,  or .',
    );
  });

  testWidgets('formulas that cannot be typeset show their source', (
    tester,
  ) async {
    await _pump(tester, r'Bad: $\frac{1}{$ and $\notacommand{x}$ end');
    expect(tester.takeException(), isNull);
    final huge = 'a+' * (maxMathLength ~/ 2 + 1);
    await _pump(tester, '\$\$${huge}b\$\$');
    expect(find.textContaining('a+a+a+'), findsWidgets);
  });

  testWidgets('copying a reply copies the original TeX', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    await _pump(tester, _quadratic);
    await tester.tap(find.byTooltip('Copy'));
    await tester.pump();
    expect(copied, _quadratic);
  });

  for (final locale in const [Locale('en'), Locale('bn')]) {
    for (final mode in const [ThemeMode.light, ThemeMode.dark]) {
      testWidgets(
        'math reply ${locale.languageCode} ${mode.name}',
        tags: ['golden'],
        (tester) async {
          tester.view
            ..physicalSize = const Size(1080, 1500)
            ..devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          await _pump(
            tester,
            locale.languageCode == 'bn'
                ? r'$$x^2 - 5x + 6 = 0$$সমাধান: $$(x-2)(x-3) = 0$$ '
                      r'তাই, $x = 2$ অথবা $x = 3$।'
                      '\n\n'
                      r'ভগ্নাংশ: \(\frac{\sin\theta}{\cos\theta} = \tan\theta\)'
                : '$_quadratic\n\n'
                      r'Also \(\frac{\sin\theta}{\cos\theta} = \tan\theta\) '
                      r'and $\sqrt{x^2+y^2}$.',
            locale: locale,
            mode: mode,
          );
          await expectLater(
            find.byType(Scaffold),
            matchesGoldenFile(
              '../../../goldens/goldens/'
              'math_reply_${locale.languageCode}_${mode.name}.png',
            ),
          );
        },
      );
    }
  }
}
