import 'package:emberwit/l10n/gen/app_localizations.dart';
import 'package:flutter/widgets.dart';

/// Shorthand access to localized strings: `context.l10n.welcomeTitle`.
extension L10nContext on BuildContext {
  /// Localized strings for the nearest [Localizations] scope.
  AppLocalizations get l10n => AppLocalizations.of(this);
}
