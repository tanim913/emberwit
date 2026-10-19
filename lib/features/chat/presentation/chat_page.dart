import 'dart:async';

import 'package:emberwit/core/l10n/failure_messages.dart';
import 'package:emberwit/core/l10n/l10n_extension.dart';
import 'package:emberwit/core/models/model_library.dart';
import 'package:emberwit/core/navigation/app_routes.dart';
import 'package:emberwit/core/widgets/action_colors.dart';
import 'package:emberwit/core/widgets/error_banner.dart';
import 'package:emberwit/core/widgets/runtime_banner.dart';
import 'package:emberwit/features/chat/domain/chat_models.dart';
import 'package:emberwit/features/chat/domain/voice_input.dart';
import 'package:emberwit/features/chat/presentation/chat_controllers.dart';
import 'package:emberwit/features/chat/presentation/voice_typing.dart';
import 'package:emberwit/features/chat/presentation/widgets/chat_settings_sheet.dart';
import 'package:emberwit/features/chat/presentation/widgets/message_view.dart';
import 'package:emberwit/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Longest message the composer accepts, in characters.
const int maxMessageLength = 16000;

/// One conversation: streaming replies, stop, settings.
class ChatPage extends ConsumerStatefulWidget {
  /// Creates the page for conversation [conversationId].
  const new({
    required this.conversationId,
    this.openLink,
    this.startVoice = false,
    super.key,
  });

  /// Conversation to show.
  final String conversationId;

  /// Opens confirmed links; defaults to the system browser.
  final LinkOpener? openLink;

  /// Starts voice typing once the page shows (opened from the home screen
  /// widget). Waits while the app lock covers the app.
  final bool startVoice;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final TextEditingController _input = TextEditingController();

  /// Message field text when dictation started; heard text goes after it.
  String? _voiceBase;

  /// Voice typing still to start for [ChatPage.startVoice].
  late bool _voicePending = widget.startVoice;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  ChatControllerProvider get _provider =>
      chatControllerProvider(widget.conversationId);

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    if (ref.read(voiceTypingProvider).listening) {
      // Send what is in the field; drop the rest of the dictation.
      _voiceBase = null;
      unawaited(ref.read(voiceTypingProvider.notifier).cancel());
    }
    _input.clear();
    unawaited(
      ref
          .read(_provider.notifier)
          .send(text, untitled: context.l10n.chatUntitled),
    );
  }

  /// Language to listen for: the user's last choice, else the app's.
  VoiceLanguage get _voiceLanguage =>
      ref.read(voiceTypingProvider).language ??
      VoiceLanguage.forLanguageCode(
        Localizations.localeOf(context).languageCode,
      );

  void _toggleVoice() {
    final voice = ref.read(voiceTypingProvider.notifier);
    if (ref.read(voiceTypingProvider).listening) {
      unawaited(voice.stop());
    } else {
      unawaited(voice.start(_voiceLanguage));
    }
  }

  void _switchVoiceLanguage() {
    final next = _voiceLanguage == VoiceLanguage.english
        ? VoiceLanguage.bengali
        : VoiceLanguage.english;
    final listening = ref.read(voiceTypingProvider).listening;
    unawaited(ref.read(voiceTypingProvider.notifier).switchLanguage(next));
    if (!listening) {
      // Held the microphone: say which language the next tap listens for.
      final l10n = context.l10n;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          _voiceSnackBar(
            content: Text(
              l10n.chatVoiceLanguageSet(voiceLanguageName(l10n, next)),
            ),
          ),
        );
    }
  }

  void _onVoice(VoiceTypingState? previous, VoiceTypingState next) {
    if (next.session != previous?.session && next.listening) {
      _voiceBase = _input.text;
    }
    final base = _voiceBase;
    if (base != null && next.text != previous?.text) {
      var text = joinDictation(base, next.text);
      if (text.length > maxMessageLength) {
        text = text.substring(0, maxMessageLength);
      }
      _input.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    if (!next.listening) _voiceBase = null;
    final problem = next.problem;
    if (problem != null && problem != previous?.problem) {
      _showVoiceProblem(
        problem,
        next.problemLanguage ?? _voiceLanguage,
        backToEnglish: next.backToEnglish,
      );
    }
  }

  void _showVoiceProblem(
    VoiceProblem problem,
    VoiceLanguage language, {
    required bool backToEnglish,
  }) {
    final l10n = context.l10n;
    final name = voiceLanguageName(l10n, language);
    final reason = switch (problem) {
      VoiceProblem.permissionDenied => l10n.chatVoicePermission,
      VoiceProblem.unavailable => l10n.chatVoiceUnavailable,
      VoiceProblem.notInstalled => l10n.chatVoiceNotInstalled(name),
      VoiceProblem.downloading => l10n.chatVoiceDownloading(name),
      VoiceProblem.unsupported => l10n.chatVoiceUnsupported(name),
      VoiceProblem.noSpeech => l10n.chatVoiceNoSpeech,
      VoiceProblem.busy => l10n.chatVoiceBusy,
      VoiceProblem.failed => l10n.chatVoiceFailed,
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        _voiceSnackBar(
          content: Text(
            backToEnglish ? '$reason ${l10n.chatVoiceBackToEnglish}' : reason,
          ),
          action: problem == VoiceProblem.notInstalled
              ? SnackBarAction(
                  label: l10n.chatVoiceInstall,
                  onPressed: () => unawaited(_installVoice(language)),
                )
              : null,
        ),
      );
  }

  Future<void> _installVoice(VoiceLanguage language) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final name = voiceLanguageName(l10n, language);
    final started = await ref
        .read(voiceTypingProvider.notifier)
        .install(language);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        _voiceSnackBar(
          content: Text(
            started
                ? l10n.chatVoiceInstallStarted(name)
                : l10n.chatVoiceNotInstalledManual(name),
          ),
        ),
      );
  }

  Future<void> _openSettings(
    ConversationSettings settings,
    List<InstalledModel> models,
  ) async {
    final edited = await showChatSettings(
      context,
      settings: settings,
      models: models,
    );
    if (edited != null) {
      await ref.read(_provider.notifier).updateSettings(edited);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(_provider);
    final voice = ref.watch(voiceTypingProvider);
    ref.listen(voiceTypingProvider, _onVoice);
    final models = ref.watch(installedModelsProvider).value ?? const [];
    final conversation = state.conversation;
    final messages = state.visibleMessages.reversed.toList();
    InstalledModel? model;
    for (final m in models) {
      if (m.id == conversation?.settings.modelId) model = m;
    }
    model ??= models.isEmpty ? null : models.first;
    // The lock screen pauses tickers below it, so listening never starts
    // behind it.
    if (_voicePending &&
        voice.available &&
        conversation != null &&
        models.isNotEmpty &&
        TickerMode.valuesOf(context).enabled) {
      _voicePending = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !ref.read(voiceTypingProvider).listening) _toggleVoice();
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              conversation?.title ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (model != null)
              Text(
                model.displayName,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: [
          if (conversation != null)
            IconButton(
              key: const Key('chat-settings'),
              tooltip: l10n.chatSettingsOpen,
              onPressed: state.generating
                  ? null
                  : () => _openSettings(conversation.settings, models),
              icon: const Icon(Icons.tune_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (state.loadProgress != null) ...[
              LinearProgressIndicator(value: state.loadProgress),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  l10n.chatLoadingModel((state.loadProgress! * 100).round()),
                ),
              ),
            ],
            Expanded(
              child:
                  models.isEmpty && ref.watch(installedModelsProvider).hasValue
                  ? const _NoModel()
                  : ListView.separated(
                      key: const Key('messages'),
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      itemCount: messages.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        return MessageView(
                          key: ValueKey(message.id),
                          message: message,
                          streaming: message.id == state.liveMessageId,
                          openLink: widget.openLink ?? openExternally,
                        );
                      },
                    ),
            ),
            if (state.failure != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: ErrorBanner(describeFailure(l10n, state.failure!)),
              ),
            const RuntimeBanner(),
            _Composer(
              controller: _input,
              generating: state.generating,
              enabled: conversation != null && models.isNotEmpty,
              onSend: _send,
              onStop: () => ref.read(_provider.notifier).stop(),
              voice: voice,
              voiceLanguage: voiceLanguageName(
                l10n,
                voice.language ??
                    VoiceLanguage.forLanguageCode(
                      Localizations.localeOf(context).languageCode,
                    ),
              ),
              onVoice: _toggleVoice,
              onVoiceLanguage: _switchVoiceLanguage,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoModel extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.download_rounded,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(l10n.chatNoModelTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(l10n.chatNoModelBody, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => context.push(AppRoutes.models),
              child: Text(l10n.modelsOpen),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const new({
    required this.controller,
    required this.generating,
    required this.enabled,
    required this.onSend,
    required this.onStop,
    required this.voice,
    required this.voiceLanguage,
    required this.onVoice,
    required this.onVoiceLanguage,
  });

  final TextEditingController controller;
  final bool generating;
  final bool enabled;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoiceTypingState voice;
  final String voiceLanguage;
  final VoidCallback onVoice;
  final VoidCallback onVoiceLanguage;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final filled = IconButton.styleFrom(
      backgroundColor: scheme.action,
      foregroundColor: scheme.onAction,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (voice.listening)
              _ListeningBar(
                ready: voice.ready,
                level: voice.level,
                language: voiceLanguage,
                onLanguage: onVoiceLanguage,
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('chat-input'),
                    controller: controller,
                    enabled: enabled,
                    minLines: 1,
                    maxLines: 6,
                    // Ask the keyboard not to learn from private conversations
                    // (Gboard incognito mode).
                    enableIMEPersonalizedLearning: false,
                    // A very long paste cannot fit any phone sized context and
                    // makes layout slow; the limit is far above real messages.
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(maxMessageLength),
                    ],
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: l10n.chatInputHint,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      // Tap to listen, hold to change the language. No
                      // tooltip: it would take the long press.
                      suffixIcon: voice.available
                          ? Semantics(
                              label: voice.listening
                                  ? l10n.chatVoiceStop
                                  : l10n.chatVoiceStart,
                              onLongPressHint: l10n.chatVoiceHoldHint,
                              button: true,
                              excludeSemantics: true,
                              child: GestureDetector(
                                onLongPress: enabled ? onVoiceLanguage : null,
                                child: IconButton(
                                  key: const Key('chat-voice'),
                                  onPressed: enabled ? onVoice : null,
                                  color: voice.listening ? scheme.action : null,
                                  icon: Icon(
                                    voice.listening
                                        ? Icons.stop_circle_outlined
                                        : Icons.mic_none_rounded,
                                  ),
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (generating)
                  IconButton.filled(
                    key: const Key('chat-stop'),
                    style: filled,
                    tooltip: l10n.chatStop,
                    onPressed: onStop,
                    icon: const Icon(Icons.stop_rounded),
                  )
                else
                  IconButton.filled(
                    key: const Key('chat-send'),
                    style: filled,
                    tooltip: l10n.chatSend,
                    onPressed: enabled ? onSend : null,
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown above the message field while voice typing listens: a dot that
/// grows with the voice, and the language, tap to switch.
class _ListeningBar extends StatelessWidget {
  const new({
    required this.ready,
    required this.level,
    required this.language,
    required this.onLanguage,
  });

  /// The microphone is open; until then the bar says it is getting ready.
  final bool ready;
  final double level;
  final String language;
  final VoidCallback onLanguage;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final size = 10 + 14 * level;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 24,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: scheme.action,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ready ? l10n.chatVoiceListening : l10n.chatVoiceStarting,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Tooltip(
            message: l10n.chatVoiceLanguage(language),
            excludeFromSemantics: true,
            child: Semantics(
              label: l10n.chatVoiceLanguage(language),
              excludeSemantics: true,
              button: true,
              child: ActionChip(
                key: const Key('chat-voice-language'),
                avatar: const Icon(Icons.translate_rounded, size: 18),
                label: Text(language),
                onPressed: onLanguage,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A voice typing message, floating above the message box so the
/// microphone stays reachable while it shows.
SnackBar _voiceSnackBar({required Widget content, SnackBarAction? action}) =>
    SnackBar(
      content: content,
      action: action,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 88),
    );

/// Name of [language] for voice typing controls.
String voiceLanguageName(AppLocalizations l10n, VoiceLanguage language) =>
    switch (language) {
      VoiceLanguage.english => l10n.voiceLanguageEnglish,
      VoiceLanguage.bengali => l10n.voiceLanguageBengali,
    };
