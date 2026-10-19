// Checks line coverage from coverage/lcov.info against a minimum.
//
// Usage: dart run tool/coverage_check.dart [--min=80] [--lcov=coverage/lcov.info]
//
// Generated files are ignored. The threshold applies to the layers that hold
// logic: lib/core, lib/engine and every feature's domain and data layer.
// Presentation code is covered by widget and golden tests instead.
import 'dart:io';

final _generated = RegExp(r'(\.g\.dart|\.freezed\.dart|/l10n/gen/)');
final _gated = RegExp('^lib/(core|engine)/|^lib/features/[^/]+/(domain|data)/');

void main(List<String> args) {
  var min = 80.0;
  var lcovPath = 'coverage/lcov.info';
  for (final arg in args) {
    if (arg.startsWith('--min=')) min = double.parse(arg.substring(6));
    if (arg.startsWith('--lcov=')) lcovPath = arg.substring(7);
  }

  final lcov = File(lcovPath);
  if (!lcov.existsSync()) {
    stderr.writeln('No $lcovPath. Run: flutter test --coverage');
    exit(2);
  }

  final files = <String, (int found, int hit)>{};
  String? current;
  var found = 0;
  var hit = 0;
  for (final line in lcov.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      current = line.substring(3).replaceAll(r'\', '/');
      final libIndex = current.indexOf('lib/');
      if (libIndex > 0) current = current.substring(libIndex);
      found = 0;
      hit = 0;
    } else if (line.startsWith('DA:')) {
      found++;
      if (!line.endsWith(',0')) hit++;
    } else if (line == 'end_of_record' && current != null) {
      files[current] = (found, hit);
      current = null;
    }
  }

  var gatedFound = 0;
  var gatedHit = 0;
  var totalFound = 0;
  var totalHit = 0;
  final report = <String>[];
  for (final MapEntry(key: path, value: (f, h)) in files.entries) {
    if (_generated.hasMatch(path)) continue;
    totalFound += f;
    totalHit += h;
    if (_gated.hasMatch(path)) {
      gatedFound += f;
      gatedHit += h;
      report.add('${_pct(h, f).padLeft(7)}  $path');
    }
  }

  report.sort();
  stdout
    ..writeln('Gated files (core, engine, domain, data):')
    ..writeln(report.join('\n'))
    ..writeln('Overall:  ${_pct(totalHit, totalFound)} ($totalHit/$totalFound)')
    ..writeln(
      'Gated:    ${_pct(gatedHit, gatedFound)} ($gatedHit/$gatedFound)',
    );

  final gated = gatedFound == 0 ? 100 : gatedHit * 100 / gatedFound;
  if (gated < min) {
    stderr.writeln('Gated coverage ${gated.toStringAsFixed(1)}% < $min%');
    exit(1);
  }
}

String _pct(int hit, int found) =>
    found == 0 ? '100.0%' : '${(hit * 100 / found).toStringAsFixed(1)}%';
