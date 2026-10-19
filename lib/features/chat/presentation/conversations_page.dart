import 'dart:async';

import 'package:emberwit/core/l10n/l10n_extension.dart';
import 'package:emberwit/core/navigation/app_routes.dart';
import 'package:emberwit/features/chat/data/chat_providers.dart';
import 'package:emberwit/features/chat/domain/chat_models.dart';
import 'package:emberwit/features/chat/presentation/chat_controllers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// All conversations: search, open, start new, pin, rename, delete.
class ConversationsPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const new({super.key});

  @override
  ConsumerState<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends ConsumerState<ConversationsPage> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _newChat() async {
    final id = await createConversation(ref, title: context.l10n.chatUntitled);
    if (mounted) unawaited(context.push(AppRoutes.chat(id)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final conversations = ref.watch(conversationsProvider(_query));
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.chatsTitle),
        actions: [
          IconButton(
            key: const Key('open-models'),
            tooltip: l10n.modelsOpen,
            onPressed: () => context.push(AppRoutes.models),
            icon: const Icon(Icons.download_rounded),
          ),
          IconButton(
            key: const Key('open-settings'),
            tooltip: l10n.settingsTitle,
            onPressed: () => context.push(AppRoutes.settings),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-chat'),
        onPressed: _newChat,
        icon: const Icon(Icons.add_comment_rounded),
        label: Text(l10n.chatsNew),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SearchBar(
                key: const Key('chat-search'),
                controller: _search,
                hintText: l10n.chatsSearchHint,
                leading: const Icon(Icons.search_rounded),
                elevation: const WidgetStatePropertyAll(0),
                onChanged: (value) => setState(() => _query = value.trim()),
              ),
            ),
            Expanded(
              child: switch (conversations) {
                AsyncData(:final value) when value.isEmpty => _Empty(
                  _query.isEmpty
                      ? l10n.chatsEmpty
                      : l10n.chatsNoResults(_query),
                ),
                AsyncData(:final value) => ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: value.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) =>
                      _ConversationTile(conversation: value[index]),
                ),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}

enum _Action { pin, rename, delete }

class _ConversationTile extends ConsumerWidget {
  const new({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final repository = ref.read(chatRepositoryProvider);
    return ListTile(
      key: Key('conversation-${conversation.id}'),
      onTap: () => context.push(AppRoutes.chat(conversation.id)),
      title: Row(
        children: [
          if (conversation.pinned) ...[
            Icon(
              Icons.push_pin_rounded,
              size: 16,
              color: theme.colorScheme.primary,
              semanticLabel: l10n.chatsPinned,
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              conversation.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: conversation.preview.isEmpty
          ? null
          : Text(
              conversation.preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: PopupMenuButton<_Action>(
        key: Key('conversation-menu-${conversation.id}'),
        tooltip: l10n.chatsMore,
        onSelected: (action) async {
          switch (action) {
            case _Action.pin:
              await repository.setPinned(
                conversation.id,
                pinned: !conversation.pinned,
              );
            case _Action.rename:
              final title = await _askTitle(context, conversation.title);
              if (title != null && title.trim().isNotEmpty) {
                await repository.rename(conversation.id, title);
              }
            case _Action.delete:
              if (await _confirmDelete(context)) {
                await repository.deleteConversation(conversation.id);
              }
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: _Action.pin,
            child: Text(conversation.pinned ? l10n.chatsUnpin : l10n.chatsPin),
          ),
          PopupMenuItem(value: _Action.rename, child: Text(l10n.chatsRename)),
          PopupMenuItem(value: _Action.delete, child: Text(l10n.chatsDelete)),
        ],
      ),
    );
  }
}

Future<String?> _askTitle(BuildContext context, String current) =>
    showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(current: current),
    );

/// Owns its text controller so it outlives the dialog's exit animation.
class _RenameDialog extends StatefulWidget {
  const new({required this.current});

  final String current;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.current,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.chatsRenameTitle),
      content: TextField(
        key: const Key('rename-field'),
        enableIMEPersonalizedLearning: false,
        controller: _controller,
        autofocus: true,
        maxLength: 80,
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('rename-save'),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}

Future<bool> _confirmDelete(BuildContext context) async {
  final l10n = context.l10n;
  final scheme = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.chatsDeleteTitle),
      content: Text(l10n.chatsDeleteBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('confirm-delete-chat'),
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.chatsDelete),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
