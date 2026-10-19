import 'package:emberwit/features/chat/domain/chat_models.dart';
import 'package:flutter/foundation.dart';

/// One turn of history for prompt formatting.
typedef PromptTurn = ({MessageRole role, String content});

/// A prompt ready for the engine.
@immutable
final class FormattedPrompt {
  /// Creates a prompt.
  const new(this.text, this.stopSequences);

  /// Prompt text with the model's control tokens.
  final String text;

  /// Text that ends the reply if the model emits it.
  final List<String> stopSequences;
}

/// Formats conversations the way a model family was trained.
///
/// Beginning-of-sequence tokens are never written here: the engine's
/// tokenizer adds them for models that expect them.
///
/// User and assistant text is untrusted. Any control marker in it (for
/// example a user typing `<|im_start|>system`) is broken with a zero width
/// joiner, so a message can never open a new role or end the prompt.
enum ChatTemplate {
  /// ChatML: Qwen 2.5 and Qwen3. Qwen3's thinking mode is switched off with
  /// an empty think block, which keeps replies fast on phones.
  chatml(['<|im_start|>', '<|im_end|>', '<|endoftext|>', '<think>']),

  /// Gemma 2 and 3. No system role: instructions go in the first user turn.
  gemma(['<start_of_turn>', '<end_of_turn>', '<bos>', '<eos>']),

  /// Llama 3.x.
  llama3([
    '<|start_header_id|>',
    '<|end_header_id|>',
    '<|eot_id|>',
    '<|begin_of_text|>',
    '<|end_of_text|>',
  ]),

  /// Phi 4 mini.
  phi4(['<|system|>', '<|user|>', '<|assistant|>', '<|end|>', '<|endoftext|>']);

  new(this._markers);

  final List<String> _markers;

  /// The template for a catalog `chatTemplate` id, or `null` when unknown
  /// (the engine then uses the template embedded in the model file).
  static ChatTemplate? byId(String? id) => switch (id) {
    'chatml' || 'qwen3' || 'qwen2' => ChatTemplate.chatml,
    'gemma' || 'gemma3' => ChatTemplate.gemma,
    'llama3' || 'llama3.2' => ChatTemplate.llama3,
    'phi4' || 'phi3' => ChatTemplate.phi4,
    _ => null,
  };

  /// The template matching a model's embedded Jinja chat template, by its
  /// control markers. Falls back to ChatML, the most common format.
  static ChatTemplate detect(String? embedded) {
    final source = embedded ?? '';
    if (source.contains('<start_of_turn>')) return ChatTemplate.gemma;
    if (source.contains('<|start_header_id|>')) return ChatTemplate.llama3;
    if (source.contains('<|assistant|>') && source.contains('<|end|>')) {
      return ChatTemplate.phi4;
    }
    return ChatTemplate.chatml;
  }

  /// Makes [content] safe to place inside a turn.
  String sanitize(String content) {
    var safe = content;
    for (final marker in _markers) {
      if (safe.contains(marker)) {
        // "<|im_start|>" -> "<‍|im_start|>": looks the same, tokenizes
        // as plain text.
        safe = safe.replaceAll(
          marker,
          '${marker.substring(0, 1)}‍${marker.substring(1)}',
        );
      }
    }
    return safe;
  }

  /// Formats [system] instructions and [turns] (oldest first, ending with the
  /// user message to answer) and opens the assistant's reply.
  FormattedPrompt format({
    required String system,
    required List<PromptTurn> turns,
  }) {
    final sys = sanitize(system.trim());
    final safe = [
      for (final t in turns) (role: t.role, content: sanitize(t.content)),
    ];
    final out = StringBuffer();
    switch (this) {
      case ChatTemplate.chatml:
        if (sys.isNotEmpty) out.write('<|im_start|>system\n$sys<|im_end|>\n');
        for (final t in safe) {
          final role = t.role == MessageRole.user ? 'user' : 'assistant';
          out.write('<|im_start|>$role\n${t.content}<|im_end|>\n');
        }
        out.write('<|im_start|>assistant\n<think>\n\n</think>\n\n');
        return FormattedPrompt(out.toString(), const [
          '<|im_end|>',
          '<|im_start|>',
        ]);
      case ChatTemplate.gemma:
        var first = true;
        for (final t in safe) {
          final isUser = t.role == MessageRole.user;
          var content = t.content;
          if (first && isUser && sys.isNotEmpty) content = '$sys\n\n$content';
          first = false;
          out.write(
            '<start_of_turn>${isUser ? 'user' : 'model'}\n'
            '$content<end_of_turn>\n',
          );
        }
        out.write('<start_of_turn>model\n');
        return FormattedPrompt(out.toString(), const [
          '<end_of_turn>',
          '<start_of_turn>',
        ]);
      case ChatTemplate.llama3:
        void header(String role, String content) => out.write(
          '<|start_header_id|>$role<|end_header_id|>\n\n$content<|eot_id|>',
        );
        if (sys.isNotEmpty) header('system', sys);
        for (final t in safe) {
          header(t.role == MessageRole.user ? 'user' : 'assistant', t.content);
        }
        out.write('<|start_header_id|>assistant<|end_header_id|>\n\n');
        return FormattedPrompt(out.toString(), const [
          '<|eot_id|>',
          '<|start_header_id|>',
        ]);
      case ChatTemplate.phi4:
        if (sys.isNotEmpty) out.write('<|system|>$sys<|end|>');
        for (final t in safe) {
          final role = t.role == MessageRole.user ? 'user' : 'assistant';
          out.write('<|$role|>${t.content}<|end|>');
        }
        out.write('<|assistant|>');
        return FormattedPrompt(out.toString(), const ['<|end|>', '<|user|>']);
    }
  }
}

final RegExp _thinkBlock = RegExp(r'<think>[\s\S]*?(</think>|$)');

/// Removes reasoning blocks (`<think>...</think>`) that some models, such as
/// Qwen3, emit before the answer. An unfinished block (still streaming) is
/// removed up to the end.
String stripThinking(String text) => text.contains('<think>')
    ? text.replaceAll(_thinkBlock, '').trimLeft()
    : text;
