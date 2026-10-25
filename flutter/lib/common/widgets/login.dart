import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/common/hbbs/hbbs.dart';

import '../../common.dart';

Future<bool?>? _activeLoginDialog;

Future<bool?> loginDialog() {
  return _activeLoginDialog ??= _openCompanyLogin();
}

Future<bool?> _openCompanyLogin() async {
  final server = TextEditingController(
      text: bind.mainGetLocalOption(key: 'enterprise-server'));
  final username = TextEditingController();
  final password = TextEditingController();
  final displayName = TextEditingController();
  final passwordConfirmation = TextEditingController();
  var registering = false;
  var busy = false;
  var cancelled = false;
  String? error;
  try {
    if (server.text.isEmpty) server.text = await bind.mainGetApiServer();
    return await gFFI.dialogManager.show<bool>((setState, close, context) {
      cancel() {
        if (busy) return;
        cancelled = true;
        close(false);
      }

      submit() async {
        if (busy || cancelled) return;
        if (server.text.trim().isEmpty ||
            username.text.trim().isEmpty ||
            password.text.isEmpty) {
          setState(
              () => error = translate('Username and password are required'));
          return;
        }
        setState(() {
          busy = true;
          error = null;
        });
        try {
          await gFFI.userModel.loginCompany(
              server.text, username.text, password.text,
              register: registering,
              displayName: displayName.text,
              passwordConfirmation: passwordConfirmation.text);
          if (!cancelled) close(true);
        } catch (err) {
          if (!cancelled) {
            setState(() {
              error = err is RequestException
                  ? translate(err.cause)
                  : err is FormatException
                      ? translate(err.message)
                      : err.toString();
              busy = false;
            });
          }
        }
      }

      return CustomAlertDialog(
        title: Text(translate(
            registering ? 'Create company account' : 'Company account')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(translate(registering
                      ? 'New accounts require device permissions from an administrator'
                      : 'Sign in or create a company account')),
                  const SizedBox(height: 16),
                  TextField(
                      controller: server,
                      enabled: !busy,
                      autocorrect: false,
                      decoration: InputDecoration(
                          labelText: translate('Company server'),
                          hintText: 'https://management.example.com')),
                  const SizedBox(height: 12),
                  TextField(
                      controller: username,
                      enabled: !busy,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.username],
                      decoration:
                          InputDecoration(labelText: translate('Username'))),
                  if (registering) ...[
                    const SizedBox(height: 12),
                    TextField(
                        controller: displayName,
                        enabled: !busy,
                        maxLength: 100,
                        decoration: InputDecoration(
                            labelText: translate('Display name (optional)'))),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                      controller: password,
                      enabled: !busy,
                      obscureText: true,
                      autofillHints: registering
                          ? const [AutofillHints.newPassword]
                          : const [AutofillHints.password],
                      onSubmitted: (_) => submit(),
                      decoration:
                          InputDecoration(labelText: translate('Password'))),
                  if (registering) ...[
                    const SizedBox(height: 12),
                    TextField(
                        controller: passwordConfirmation,
                        enabled: !busy,
                        obscureText: true,
                        onSubmitted: (_) => submit(),
                        decoration: InputDecoration(
                            labelText: translate('Confirm password'))),
                  ],
                  const SizedBox(height: 16),
                  Text(translate(
                      'Only devices authorized to your account will be shown')),
                  TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                                registering = !registering;
                                error = null;
                                password.clear();
                                passwordConfirmation.clear();
                              }),
                      child: Text(translate(registering
                          ? 'Back to login'
                          : 'Create company account'))),
                  if (error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: SelectableText(error!,
                            style: const TextStyle(color: Colors.red))),
                  if (busy)
                    const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: LinearProgressIndicator()),
                ]),
          ),
        ),
        actions: [
          dialogButton(translate('Cancel'),
              onPressed: busy ? null : cancel, isOutline: true),
          dialogButton(
              translate(registering ? 'Register and sign in' : 'Login'),
              onPressed: busy ? null : submit),
        ],
        onSubmit: busy ? null : submit,
        onCancel: cancel,
      );
    });
  } finally {
    cancelled = true;
    server.dispose();
    username.dispose();
    password.dispose();
    displayName.dispose();
    passwordConfirmation.dispose();
    _activeLoginDialog = null;
  }
}

void logOutConfirmDialog() {
  gFFI.dialogManager.show((setState, close, context) {
    submit() {
      close();
      gFFI.userModel.logOut();
    }

    return CustomAlertDialog(
      content: Text(translate('logout_tip')),
      actions: [
        dialogButton(translate('Cancel'), onPressed: close, isOutline: true),
        dialogButton(translate('OK'), onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}
