import 'package:emberwit/app/debug/engine_debug_controller.dart';
import 'package:emberwit/core/l10n/failure_messages.dart';
import 'package:emberwit/core/l10n/l10n_extension.dart';
import 'package:emberwit/core/widgets/error_banner.dart';
import 'package:emberwit/engine/inference_engine.dart';
import 'package:emberwit/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Developer screen that proves the inference engine works end to end: pick
/// a GGUF file, load it, prompt it, watch tokens stream and read the stats.
///
/// Reachable only in dev and staging builds.
class EngineDebugPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const new({super.key});

  @override
  ConsumerState<EngineDebugPage> createState() => _EngineDebugPageState();
}

class _EngineDebugPageState extends ConsumerState<EngineDebugPage> {
  final TextEditingController _prompt = TextEditingController(
    text: 'Once upon a time',
  );

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(engineDebugControllerProvider);
    final controller = ref.read(engineDebugControllerProvider.notifier);
    final loading = state.engineState == EngineState.loading;
    final generating = state.engineState == EngineState.generating;
    final ready = state.engineState == EngineState.ready;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.debugEngineTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SectionTitle(l10n.debugModelSection),
            if (state.models.isEmpty && state.modelsDirectory != null)
              Text(l10n.debugNoModels(state.modelsDirectory!))
            else
              DropdownButton<String>(
                key: const Key('debug-model-picker'),
                isExpanded: true,
                value: state.selectedModel,
                items: [
                  for (final path in state.models)
                    DropdownMenuItem(
                      value: path,
                      child: Text(
                        path.split('/').last,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: loading || generating ? null : controller.select,
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed:
                      state.selectedModel == null || loading || generating
                      ? null
                      : controller.load,
                  child: Text(l10n.debugLoad),
                ),
                OutlinedButton(
                  onPressed: ready ? controller.unload : null,
                  child: Text(l10n.debugUnload),
                ),
                TextButton(
                  onPressed: controller.refreshModels,
                  child: Text(l10n.debugRefresh),
                ),
              ],
            ),
            if (state.loadProgress != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: state.loadProgress),
              const SizedBox(height: 4),
              Text(l10n.debugLoading((state.loadProgress! * 100).round())),
            ],
            if (state.model != null)
              _ModelDetails(state.model!, state.loadDuration),
            const Divider(height: 32),
            _SectionTitle(l10n.debugPromptSection),
            TextField(
              key: const Key('debug-prompt'),
              controller: _prompt,
              minLines: 2,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: l10n.debugPromptHint,
                border: const OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.debugUseChatTemplate),
              value: state.useChatTemplate,
              onChanged: (value) => controller.setUseChatTemplate(value: value),
            ),
            Text(l10n.debugMaxTokens(state.maxTokens)),
            Slider(
              value: state.maxTokens.toDouble(),
              min: 16,
              max: 1024,
              divisions: 63,
              onChanged: (v) => controller.setMaxTokens(v.round()),
            ),
            Text(l10n.debugTemperature(state.temperature)),
            Slider(
              value: state.temperature,
              max: 2,
              divisions: 20,
              onChanged: controller.setTemperature,
            ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('debug-generate'),
                    onPressed: ready
                        ? () => controller.generate(_prompt.text)
                        : null,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(l10n.debugGenerate),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('debug-stop'),
                    onPressed: generating || loading ? controller.stop : null,
                    icon: const Icon(Icons.stop_rounded),
                    label: Text(l10n.debugStop),
                  ),
                ),
              ],
            ),
            if (state.failure != null) ...[
              const SizedBox(height: 12),
              ErrorBanner(describeFailure(l10n, state.failure!)),
            ],
            const Divider(height: 32),
            _SectionTitle(l10n.debugOutputSection),
            SelectableText(
              state.output,
              key: const Key('debug-output'),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (state.stats != null) _StatsView(state.stats!),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _ModelDetails extends StatelessWidget {
  const new(this.model, this.loadDuration);

  final ModelInfo model;
  final Duration? loadDuration;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              model.description,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(l10n.debugArchitecture(model.architecture)),
            Text(l10n.debugParameters(model.parameterCount)),
            Text(l10n.debugContext(model.contextLength)),
            Text(l10n.debugThreads(model.threads, model.gpuLayers)),
            Text(l10n.debugDevices(model.devices.join(', '))),
            if (loadDuration != null)
              Text(l10n.debugLoadTime(loadDuration!.inMilliseconds)),
          ],
        ),
      ),
    );
  }
}

class _StatsView extends StatelessWidget {
  const new(this.stats);

  final GenerationStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.debugStatsTtft(stats.timeToFirstToken.inMilliseconds)),
          Text(l10n.debugStatsSpeed(stats.tokensPerSecond)),
          Text(
            l10n.debugStatsTokens(stats.promptTokens, stats.generatedTokens),
          ),
          Text(l10n.debugStopReason(stopReasonLabel(l10n, stats.stopReason))),
        ],
      ),
    );
  }
}

/// Localized description of why generation stopped.
String stopReasonLabel(AppLocalizations l10n, StopReason reason) =>
    switch (reason) {
      StopReason.endOfSequence => l10n.stopReasonEndOfSequence,
      StopReason.maxTokens => l10n.stopReasonMaxTokens,
      StopReason.stopSequence => l10n.stopReasonStopSequence,
      StopReason.cancelled => l10n.stopReasonCancelled,
      StopReason.contextFull => l10n.stopReasonContextFull,
    };
