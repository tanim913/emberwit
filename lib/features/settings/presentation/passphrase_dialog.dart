import 'package:emberwit/core/l10n/l10n_extension.dart';
import 'package:flutter/material.dart';

/// Shortest passphrase accepted for exports. Matches the codec's minimum.
const int minPassphraseLength = 8;

/// Asks for a passphrase. With [confirm], asks twice and requires a match
/// and at least [minPassphraseLength] characters. Returns `null` when
/// cancelled.
Future<String?> showPassphraseDialog(
  BuildContext context, {
  required String title,
  required String body,
  required bool confirm,
}) => showDialog<String>(
  context: context,
  builder: (context) =>
      _PassphraseDialog(title: title, body: body, confirm: confirm),
);

class _PassphraseDialog extends StatefulWidget {
  const new({required this.title, required this.body, required this.confirm});

  final String title;
  final String body;
  final bool confirm;

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final TextEditingController _first = TextEditingController();
  final TextEditingController _second = TextEditingController();
  final GlobalKey<FormState> _form = GlobalKey();
  bool _visible = false;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState?.validate() ?? false) {
      Navigator.pop(context, _first.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final toggle = IconButton(
      tooltip: _visible ? l10n.passphraseHide : l10n.passphraseShow,
      onPressed: () => setState(() => _visible = !_visible),
      icon: Icon(
        _visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      ),
    );
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.body),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('passphrase'),
                controller: _first,
                obscureText: !_visible,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                keyboardType: TextInputType.visiblePassword,
                decoration: InputDecoration(
                  labelText: l10n.passphraseLabel,
                  suffixIcon: toggle,
                ),
                validator: (value) =>
                    widget.confirm && (value ?? '').length < minPassphraseLength
                    ? l10n.passphraseTooShort(minPassphraseLength)
                    : ((value ?? '').isEmpty ? l10n.passphraseRequired : null),
                onFieldSubmitted: widget.confirm ? null : (_) => _submit(),
              ),
              if (widget.confirm) ...[
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('passphrase-confirm'),
                  controller: _second,
                  obscureText: !_visible,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  keyboardType: TextInputType.visiblePassword,
                  decoration: InputDecoration(
                    labelText: l10n.passphraseConfirmLabel,
                  ),
                  validator: (value) =>
                      value != _first.text ? l10n.passphraseMismatch : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('passphrase-submit'),
          onPressed: _submit,
          child: Text(l10n.passphraseContinue),
        ),
      ],
    );
  }
}
