/// Signing in, or making an account, with the same Noctorium account the player uses.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../service.dart';
import '../theme.dart';
import '../widgets/mark.dart';

enum _Mode { signIn, create }

/// The service's own floor, said before asking it so nobody waits for a refusal they could have read.
const int minimumPasswordLength = 10;

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.deps, required this.onSignedIn, this.notice});

  final Dependencies deps;
  final Future<void> Function(Session session) onSignedIn;

  /// Why the listener is here again, when the app signed them out.
  final String? notice;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  bool _hidden = true;
  String? _error;

  /// A browser sign-in waiting to be allowed; and which one, so an older wait that ends late is ignored.
  DeviceStart? _waiting;
  int _attempt = 0;

  Future<void> _signInInBrowser() async {
    if (_busy) return;
    final attempt = ++_attempt;
    setState(() {
      _busy = true;
      _error = null;
    });
    final service = widget.deps.service;
    try {
      final start = await service.startDeviceSignIn();
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _waiting = start;
        _busy = false;
      });
      unawaited(widget.deps.openLink(start.url));
      final until = DateTime.now().add(Duration(seconds: start.expiresIn));
      while (DateTime.now().isBefore(until)) {
        await Future<void>.delayed(Duration(seconds: start.interval));
        if (!mounted || attempt != _attempt) return;
        Session? session;
        try {
          session = await service.pollDeviceSignIn(start.pollToken);
        } on ServiceException catch (error) {
          // Not reached this time: asked again. Anything else ends the wait.
          if (error.failure != Failure.offline && error.failure != Failure.server) rethrow;
        }
        if (!mounted || attempt != _attempt) return;
        if (session != null) {
          await widget.onSignedIn(session);
          return;
        }
      }
      throw const ServiceException(Failure.refused, 'The code expired. Start again for a new one.');
    } on ServiceException catch (error) {
      if (mounted && attempt == _attempt) setState(() => _error = error.message);
    } finally {
      if (mounted && attempt == _attempt) {
        setState(() {
          _busy = false;
          _waiting = null;
        });
      }
    }
  }

  void _cancelBrowser() => setState(() {
        _attempt++;
        _waiting = null;
        _busy = false;
      });

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  /// What can be said without asking the service.
  String? _problem() {
    final email = _email.text.trim();
    if (email.isEmpty) return 'Enter the email address of your Noctorium account.';
    if (!RegExp(r'^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$').hasMatch(email)) return 'That does not look like an email address.';
    if (_password.text.isEmpty) return 'Enter your password.';
    if (_mode == _Mode.create && _password.text.length < minimumPasswordLength) {
      return 'Use at least $minimumPasswordLength characters for the password.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final problem = _problem();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = widget.deps.service;
      final session = _mode == _Mode.signIn
          ? await service.signIn(_email.text, _password.text)
          : await service.createAccount(_email.text, _password.text, displayName: _name.text);
      await widget.onSignedIn(session);
    } on ServiceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final creating = _mode == _Mode.create;
    final insets = MediaQuery.paddingOf(context);
    return Scaffold(
      body: DecoratedBox(
        // A little violet light behind the mark, as if the page were the night sky the name is about.
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -1.05),
            radius: 1.1,
            colors: [Night.accent.withValues(alpha: .16), Night.page.withValues(alpha: 0)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, insets.top + 32, 24, insets.bottom + 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: Mark(size: 88, glow: true)),
                    const SizedBox(height: 24),
                    Text(
                      'Noctorium Stats',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your listening, in numbers.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(color: Night.subtext),
                    ),
                    const SizedBox(height: 28),
                    if (widget.notice case final notice?) ...[
                      _Notice(text: notice),
                      const SizedBox(height: 16),
                    ],
                    SegmentedButton<_Mode>(
                      // On one line whatever the text size, shrinking to fit rather than wrapping inside a
                      // segment that does not grow to hold a second line.
                      segments: const [
                        ButtonSegment(value: _Mode.signIn, label: _OneLine('Sign in')),
                        ButtonSegment(value: _Mode.create, label: _OneLine('Create account')),
                      ],
                      selected: {_mode},
                      showSelectedIcon: false,
                      onSelectionChanged: _busy
                          ? null
                          : (selection) => setState(() {
                                _mode = selection.first;
                                _error = null;
                              }),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _email,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'Email address'),
                    ),
                    if (creating) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _name,
                        enabled: !_busy,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.name],
                        decoration: const InputDecoration(labelText: 'Your name (optional)'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      enabled: !_busy,
                      obscureText: _hidden,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      autofillHints: [creating ? AutofillHints.newPassword : AutofillHints.password],
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        helperText: creating ? 'At least $minimumPasswordLength characters.' : null,
                        suffixIcon: IconButton(
                          tooltip: _hidden ? 'Show the password' : 'Hide the password',
                          icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          color: Night.subtext,
                          onPressed: () => setState(() => _hidden = !_hidden),
                        ),
                      ),
                    ),
                    if (_error case final error?) ...[
                      const SizedBox(height: 16),
                      _ErrorLine(text: error),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: onAccent),
                            )
                          : Text(creating ? 'Create account' : 'Sign in'),
                    ),
                    const SizedBox(height: 12),
                    if (_waiting case final waiting?) ...[
                      Text('Allow Noctorium Stats in the browser. Check it shows this code:',
                          textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 8),
                      SelectableText(waiting.code,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 3)),
                      const SizedBox(height: 4),
                      Text('Waiting for you to allow it…',
                          textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: Night.subtext)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(onPressed: () => widget.deps.openLink(waiting.url), child: const Text('Open in browser')),
                          TextButton(onPressed: _cancelBrowser, child: const Text('Cancel')),
                        ],
                      ),
                    ] else
                      OutlinedButton(
                        onPressed: _busy ? null : _signInInBrowser,
                        child: const _OneLine('Sign in with Discord, Telegram or GitHub'),
                      ),
                    const SizedBox(height: 32),
                    Text(
                      creating
                          ? 'Then sign in to the same account in the Noctorium player, and everything you play '
                              'there is counted here.'
                          : 'Use the same account as in the Noctorium player. Whatever you play there while signed '
                              'in is counted here.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => widget.deps.openLink(widget.deps.service.website),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: Text('Open the website', style: theme.textTheme.labelLarge?.copyWith(color: Night.accent)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OneLine extends StatelessWidget {
  const _OneLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      FittedBox(fit: BoxFit.scaleDown, child: Text(text, maxLines: 1, softWrap: false));
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Night.accent.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Night.accent, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(color: Night.text, height: 1.35))),
        ],
      ),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Night.error, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: Night.error, height: 1.35))),
        ],
      ),
    );
  }
}
