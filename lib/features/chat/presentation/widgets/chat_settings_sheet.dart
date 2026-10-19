import 'package:emberwit/core/l10n/l10n_extension.dart';
import 'package:emberwit/core/models/model_library.dart';
import 'package:emberwit/features/chat/domain/chat_models.dart';
import 'package:flutter/material.dart';

/// Context lengths offered in chat settings.
const List<int> contextChoices = [1024, 2048, 4096, 8192];

/// Shows the settings of a conversation and returns the edited settings, or
/// `null` when dismissed.
Future<ConversationSettings?> showChatSettings(
  BuildContext context, {
  required ConversationSettings settings,
  required List<InstalledModel> models,
}) => showModalBottomSheet<ConversationSettings>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => ChatSettingsSheet(settings: settings, models: models),
);

/// Editor for [ConversationSettings]: model, instructions, sampling, context
/// length and reply length.
class ChatSettingsSheet extends StatefulWidget {
  /// Creates the sheet.
  const new({required this.settings, required this.models, super.key});

  /// Settings to start from.
  final ConversationSettings settings;

  /// Installed models to choose from.
  final List<InstalledModel> models;

  @override
  State<ChatSettingsSheet> createState() => _ChatSettingsSheetState();
}

class _ChatSettingsSheetState extends State<ChatSettingsSheet> {
  late ConversationSettings _settings = widget.settings;
  late final TextEditingController _prompt = TextEditingController(
    text: widget.settings.systemPrompt,
  );

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  void _reset() => setState(() {
    _settings = ConversationSettings(modelId: _settings.modelId);
    _prompt.text = _settings.systemPrompt;
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final modelIds = {for (final m in widget.models) m.id};
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text(l10n.chatSettingsTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            if (widget.models.isNotEmpty)
              DropdownButtonFormField<String>(
                key: const Key('settings-model'),
                initialValue: modelIds.contains(_settings.modelId)
                    ? _settings.modelId
                    : widget.models.first.id,
                decoration: InputDecoration(labelText: l10n.chatSettingsModel),
                items: [
                  for (final model in widget.models)
                    DropdownMenuItem(
                      value: model.id,
                      child: Text(model.displayName),
                    ),
                ],
                onChanged: (id) =>
                    setState(() => _settings = _settings.copyWith(modelId: id)),
              ),
            const SizedBox(height: 16),
            TextField(
              enableIMEPersonalizedLearning: false,
              key: const Key('settings-system-prompt'),
              controller: _prompt,
              minLines: 2,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: l10n.chatSettingsSystemPrompt,
              ),
            ),
            const SizedBox(height: 16),
            Text(l10n.chatSettingsTemperature(_settings.temperature)),
            Slider(
              value: _settings.temperature,
              max: 2,
              divisions: 20,
              onChanged: (v) => setState(
                () => _settings = _settings.copyWith(temperature: v),
              ),
            ),
            Text(l10n.chatSettingsTopP(_settings.topP)),
            Slider(
              value: _settings.topP,
              min: 0.05,
              divisions: 19,
              onChanged: (v) =>
                  setState(() => _settings = _settings.copyWith(topP: v)),
            ),
            Text(l10n.chatSettingsContext(_settings.contextLength)),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              key: const Key('settings-context'),
              showSelectedIcon: false,
              segments: [
                for (final c in contextChoices)
                  ButtonSegment(value: c, label: Text('${c ~/ 1024}K')),
              ],
              selected: {
                if (contextChoices.contains(_settings.contextLength))
                  _settings.contextLength
                else
                  2048,
              },
              onSelectionChanged: (s) => setState(
                () => _settings = _settings.copyWith(contextLength: s.first),
              ),
            ),
            const SizedBox(height: 16),
            Text(l10n.chatSettingsMaxTokens(_settings.maxTokens)),
            Slider(
              value: _settings.maxTokens.toDouble(),
              min: 64,
              max: 2048,
              divisions: 31,
              onChanged: (v) => setState(
                () => _settings = _settings.copyWith(maxTokens: v.round()),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: _reset,
                  child: Text(l10n.chatSettingsReset),
                ),
                const Spacer(),
                FilledButton(
                  key: const Key('settings-save'),
                  onPressed: () => Navigator.pop(
                    context,
                    _settings.copyWith(systemPrompt: _prompt.text.trim()),
                  ),
                  child: Text(l10n.commonSave),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
