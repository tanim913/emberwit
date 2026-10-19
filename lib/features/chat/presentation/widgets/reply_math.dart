import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

/// Markdown tag of an equation inside a sentence.
const String inlineMathTag = 'math-inline';

/// Markdown tag of an equation on its own line.
const String blockMathTag = 'math-block';

/// Size of equations relative to the surrounding text, so KaTeX glyphs
/// look as large as Noto Sans letters.
const double mathScale = 1.15;

/// Longest formula that is typeset; longer ones are shown as source. Keeps
/// untrusted model output from costing unbounded layout work.
const int maxMathLength = 2000;

/// Equations inside a line: `\(...\)`, `$...$`, and `$$...$$` or
/// `\[...\]` where they cannot be moved to their own line (in a list item,
/// for example; those keep the large display style).
///
/// Dollars are also used for money, so `$...$` counts as math only when:
///
/// * it hugs its content (`$x^2$`, `$f(x)$`), or it is spaced out the way
///   small models often write it (`$ f(x) = x^2 $`) and contains a math
///   character (`= ^ _ \ { }`) or is a single letter (`$ x $`);
/// * the closing dollar is not followed by a digit.
///
/// So `$5 and $10` and `costs $20, not $30` stay text. Escaped dollars
/// (`\$`) and code spans are handled by Markdown first and never reach this
/// syntax.
class InlineMathSyntax extends md.InlineSyntax {
  /// Creates the syntax.
  new()
    : super(
        r'\\\((.+?)\\\)|\\\[(.+?)\\\]|\$\$(.+?)\$\$|\$(?!\$)([^$\n]+?)\$(?!\d)',
      );

  static final RegExp _mathCharacter = RegExp(r'[=^_\\{}]');
  static final RegExp _singleLetter = RegExp(r'^[A-Za-z]$');

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    final start = startMatchPos ?? parser.pos;
    final match = pattern.matchAsPrefix(parser.source, start);
    if (match == null || _isEscaped(parser.source, start)) return false;
    final dollar = match[4];
    if (dollar != null && !_looksLikeMath(dollar)) return false;
    parser.writeText();
    final expression = (match[1] ?? match[2] ?? match[3] ?? dollar!).trim();
    if (expression.isEmpty) return false;
    final element = md.Element.text(inlineMathTag, expression)
      ..attributes['source'] = match[0]!;
    if (match[2] != null || match[3] != null) {
      element.attributes['display'] = 'true';
    }
    parser
      ..addNode(element)
      ..consume(match[0]!.length);
    return true;
  }

  static bool _looksLikeMath(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return false;
    final hugs = trimmed.length == content.length;
    if (hugs) return true;
    return _mathCharacter.hasMatch(trimmed) || _singleLetter.hasMatch(trimmed);
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) => false;
}

/// Display equations that start a line: `$$...$$` or `\[...\]`, on one
/// line or spread over several (matrices, aligned steps).
class BlockMathSyntax extends md.BlockSyntax {
  /// Creates the syntax.
  const new();

  static final RegExp _opener = RegExp(r'^ {0,3}(\$\$|\\\[)');

  @override
  RegExp get pattern => _opener;

  @override
  md.Node parse(md.BlockParser parser) {
    final first = parser.current.content;
    final open = _opener.firstMatch(first)!;
    final closer = open[1] == r'$$' ? r'$$' : r'\]';
    final lines = <String>[];
    var rest = first.substring(open.end);
    final source = <String>[];
    while (!parser.isDone) {
      source.add(parser.current.content);
      final end = rest.indexOf(closer);
      if (end >= 0) {
        lines.add(rest.substring(0, end));
        final after = rest.substring(end + closer.length).trim();
        parser.advance();
        final expression = lines.join('\n').trim();
        final raw = source.join('\n');
        if (after.isEmpty) {
          return md.Element.text(blockMathTag, expression)
            ..attributes['source'] = raw;
        }
        // Text follows on the same line: keep both, in one paragraph.
        return md.Element('p', [
          md.Element.text(inlineMathTag, expression)
            ..attributes['source'] = raw
            ..attributes['display'] = 'true',
          md.Text(' $after'),
        ]);
      }
      lines.add(rest);
      parser.advance();
      if (!parser.isDone) rest = parser.current.content;
    }
    // Still streaming (no closing delimiter yet): show the source as it is.
    return md.Element('p', [md.Text(source.join('\n'))]);
  }
}

bool _isEscaped(String text, int index) {
  var slashes = 0;
  for (var i = index - 1; i >= 0 && text[i] == r'\'; i--) {
    slashes++;
  }
  return slashes.isOdd;
}

/// Puts display equations written inside a sentence on their own lines, so
/// `$$a$$Solving: $$b$$So, done` renders as equation, text, equation, text.
///
/// A display equation opened at the end of a sentence and closed on a later
/// line (`To solve: $$` ... `$$`) is moved to its own line too. Left in the
/// sentence, Markdown would not see it start, would take its closing `$$`
/// as an opener, and every equation after it would stay raw text.
///
/// With [closeOpen], an equation still open at the end of the text is
/// closed: a finished reply cut short by the length limit then typesets
/// what it has instead of showing its last lines as source.
///
/// Only the rendered copy changes; saved and copied replies keep the model's
/// text. Fenced code, lines with code spans, and list, quote and table
/// lines are left alone, as are escaped delimiters and the lines inside an
/// equation.
String separateDisplayMath(String text, {bool closeOpen = false}) {
  if (!text.contains(r'$$') && !text.contains(r'\[')) return text;
  final out = <String>[];
  String? fence;
  // Closing delimiter of a display equation that spans lines.
  String? closer;
  for (final line in text.split('\n')) {
    final marker = RegExp('^ {0,3}(`{3,}|~{3,})').firstMatch(line)?[1];
    if (closer != null) {
      out.add(line);
      if (_indexOfUnescaped(line, closer) >= 0) closer = null;
    } else if (fence != null) {
      if (marker != null && marker[0] == fence) fence = null;
      out.add(line);
    } else if (marker != null) {
      fence = marker[0];
      out.add(line);
    } else if (line.contains('`') || _structured.hasMatch(line)) {
      out.add(line);
    } else {
      final (separated, open) = _separate(line);
      out.add(separated);
      closer = open;
    }
  }
  if (closeOpen && closer != null) out.add(closer);
  return out.join('\n');
}

final RegExp _structured = RegExp(r'^\s*([-*+]\s|\d+[.)]\s|>|\|)');

final RegExp _displayInLine = RegExp(r'\$\$(?!\$)(.+?)\$\$|\\\[(.+?)\\\]');

final RegExp _displayOpener = RegExp(r'\$\$|\\\[');

/// [line] with its display equations on their own lines, and the closing
/// delimiter still expected when an equation opened in it continues on the
/// next lines.
(String, String?) _separate(String line) {
  final parts = <String>[];
  var last = 0;
  for (final match in _displayInLine.allMatches(line)) {
    if (_isEscaped(line, match.start)) continue;
    parts
      ..add(line.substring(last, match.start).trim())
      ..add(match[0]!);
    last = match.end;
  }
  String? open;
  for (final match in _displayOpener.allMatches(line, last)) {
    if (_isEscaped(line, match.start)) continue;
    parts
      ..add(line.substring(last, match.start).trim())
      ..add(line.substring(match.start).trim());
    last = line.length;
    open = match[0] == r'$$' ? r'$$' : r'\]';
    break;
  }
  if (parts.isEmpty) return (line, null);
  parts.add(line.substring(last).trim());
  return (parts.where((p) => p.isNotEmpty).join('\n\n'), open);
}

int _indexOfUnescaped(String text, String delimiter) {
  var from = 0;
  while (true) {
    final index = text.indexOf(delimiter, from);
    if (index < 0 || !_isEscaped(text, index)) return index;
    from = index + delimiter.length;
  }
}

/// Rewrites LaTeX that models write for full LaTeX into what the bundled
/// KaTeX port typesets:
///
/// * `align`, `align*`, `eqnarray`, `split` and `flalign` become `aligned`;
///   `equation`, `gather` and `multline` are dropped (their lines are
///   handled below);
/// * `\label`, `\tag`, `\nonumber` and `\notag` are removed;
/// * line breaks (`\\`, `\newline`) outside an environment cannot be
///   typeset, so the lines go into `aligned`: as they are when they use `&`,
///   otherwise each starting with `&`, which lines them up on the left.
String prepareTex(String tex) {
  final out = tex
      .replaceAllMapped(_environment, (m) {
        final name = _environments[m[2]!];
        if (name == null) return m[0]!;
        return name.isEmpty ? '' : '\\${m[1]}{$name}';
      })
      .replaceAll(_numbering, '')
      .replaceAll(r'\newline', r'\\')
      .trim()
      .replaceFirst(_trailingBreaks, '')
      .trim();
  final breaks = <int>[];
  var columns = false;
  var depth = 0;
  for (var i = 0; i < out.length; i++) {
    if (out.startsWith(r'\begin{', i)) {
      depth++;
    } else if (out.startsWith(r'\end{', i)) {
      depth--;
    } else if (out.startsWith(r'\\', i)) {
      if (depth == 0) breaks.add(i + 2);
      i++;
      continue;
    }
    if (out[i] == r'\') {
      i++; // Skips the escaped character, so `\&` is not a column.
    } else if (out[i] == '&' && depth == 0) {
      columns = true;
    }
  }
  if (breaks.isEmpty) return out;
  if (columns) return '\\begin{aligned}$out\\end{aligned}';
  final lines = StringBuffer(r'\begin{aligned}&');
  var last = 0;
  for (final end in breaks) {
    lines.write('${out.substring(last, end)}&');
    last = end;
  }
  lines.write('${out.substring(last)}\\end{aligned}');
  return lines.toString();
}

final RegExp _environment = RegExp(r'\\(begin|end)\{([a-z]+\*?)\}');

const Map<String, String> _environments = {
  'align': 'aligned',
  'align*': 'aligned',
  'flalign': 'aligned',
  'flalign*': 'aligned',
  'eqnarray': 'aligned',
  'eqnarray*': 'aligned',
  'split': 'aligned',
  'gather': '',
  'gather*': '',
  'multline': '',
  'multline*': '',
  'equation': '',
  'equation*': '',
};

final RegExp _numbering = RegExp(
  r'\\(label|tag\*?)\{[^{}]*\}|\\(nonumber|notag)(?![a-zA-Z])',
);

final RegExp _trailingBreaks = RegExp(r'(\\\\\s*)+$');

/// Typesets [inlineMathTag] and [blockMathTag] elements offline with
/// bundled KaTeX fonts. Anything that cannot be typeset is shown as the
/// model wrote it, never hidden.
class MathBuilder extends MarkdownElementBuilder {
  /// Creates a builder for inline ([block] false) or display equations.
  new({this.block = false});

  /// Whether this builds display equations.
  final bool block;

  @override
  bool isBlockElement() => block;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final base = DefaultTextStyle.of(context).style
        .merge(parentStyle)
        .merge(preferredStyle);
    // KaTeX glyphs are drawn smaller than Noto Sans at the same size.
    final style = base.copyWith(fontSize: (base.fontSize ?? 14) * mathScale);
    final equation = ReplyEquation(
      expression: element.textContent,
      source: element.attributes['source'] ?? element.textContent,
      display: block || element.attributes['display'] == 'true',
      style: style,
    );
    if (block) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: equation,
      );
    }
    // Returned as text holding a WidgetSpan: Markdown merges it into the
    // paragraph's own rich text, so the equation flows inside the sentence
    // with its spaces. A plain widget would become a separate item of the
    // paragraph's Wrap and break the line around it.
    return Text.rich(
      WidgetSpan(alignment: PlaceholderAlignment.middle, child: equation),
    );
  }
}

/// One typeset equation, scrolling sideways when wider than the screen.
class ReplyEquation extends StatelessWidget {
  /// Creates the equation.
  const new({
    required this.expression,
    required this.source,
    required this.display,
    required this.style,
    super.key,
  });

  /// TeX to typeset.
  final String expression;

  /// The text as the model wrote it, delimiters included. Shown when the
  /// formula cannot be typeset, and read by screen readers.
  final String source;

  /// Display (large) or text (inline) style.
  final bool display;

  /// Font size and color.
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final fallback = Text(source, style: style);
    final Widget math = expression.length > maxMathLength
        ? fallback
        : Math.tex(
            prepareTex(expression),
            mathStyle: display ? MathStyle.display : MathStyle.text,
            textStyle: style,
            settings: const TexParserSettings(
              strict: Strict.ignore,
              maxExpand: 100,
            ),
            onErrorFallback: (_) => fallback,
          );
    return Semantics(
      label: source,
      excludeSemantics: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: display ? EdgeInsets.zero : const EdgeInsets.only(bottom: 1),
        child: math,
      ),
    );
  }
}
