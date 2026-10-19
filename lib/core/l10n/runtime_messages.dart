import 'package:emberwit/core/runtime/runtime_policy.dart';
import 'package:emberwit/l10n/gen/app_localizations.dart';

/// User facing explanation of a [RuntimeConcern] and what the app does
/// about it.
String describeRuntimeConcern(AppLocalizations l10n, RuntimeConcern concern) =>
    switch (concern) {
      RuntimeConcern.overheated => l10n.runtimeOverheated,
      RuntimeConcern.criticalBattery => l10n.runtimeCriticalBattery,
      RuntimeConcern.warm => l10n.runtimeWarm,
      RuntimeConcern.lowBattery => l10n.runtimeLowBattery,
      RuntimeConcern.batterySaver => l10n.runtimeBatterySaver,
    };
