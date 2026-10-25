import 'package:flutter/material.dart';
import '../../common.dart';
import '../../models/platform_model.dart';
import '../../utils/company_device_sharing.dart';

Future<void> showCompanyDeviceSharing(String deviceId) async {
  final api = CompanyDeviceSharing(
      bind.mainGetLocalOption(key: 'enterprise-server'),
      bind.mainGetLocalOption(key: 'access_token'));
  final loading = gFFI.dialogManager.showLoading(translate('Waiting'));
  Map<String, dynamic> options;
  List<Map<String, dynamic>> shares;
  try {
    options = await api.options(deviceId);
    shares = await api.list(deviceId);
  } catch (e) {
    showToast(translate(e.toString()));
    return;
  } finally {
    gFFI.dialogManager.dismissByTag(loading);
  }
  final username = TextEditingController();
  final available = List<String>.from(options['permissions']);
  final selected = <String>{
    'view',
    if (available.contains('connect')) 'connect'
  };
  const labels = {
    'view': 'View device directory',
    'connect': 'Remote desktop',
    'file_transfer': 'File transfer',
    'terminal': 'Terminal',
    'tunnel': 'TCP tunneling',
    'camera': 'View camera',
  };
  var hours = 24;
  var busy = false;
  var closed = false;
  String? error;
  try {
    await gFFI.dialogManager.show((setState, close, context) {
      cancel() {
        if (!busy) close();
      }

      operation(Future<void> Function() action) async {
        if (busy || closed) return;
        setState(() {
          busy = true;
          error = null;
        });
        try {
          await action();
          final updated = await api.list(deviceId);
          if (!closed)
            setState(() {
              shares = updated;
              username.clear();
            });
        } catch (e) {
          if (!closed) setState(() => error = translate(e.toString()));
        } finally {
          if (!closed) setState(() => busy = false);
        }
      }

      submit() => operation(() async {
            if (username.text.trim().isEmpty) {
              throw CompanySharingException('Enter the recipient username');
            }
            await api.share(deviceId, username.text, selected.toList(),
                expiresAt: hours == 0
                    ? null
                    : DateTime.now().millisecondsSinceEpoch ~/ 1000 +
                        hours * 3600);
            showToast(translate('Device shared successfully'));
          });
      return CustomAlertDialog(
        title: Text(translate('Share remote computer')),
        content: SizedBox(
            width: 480,
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 500),
                child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${options['name']} ($deviceId)'),
                        const SizedBox(height: 12),
                        Text(translate(
                            'Only this computer is shared. Recipients cannot forward this share.')),
                        TextField(
                            controller: username,
                            enabled: !busy,
                            decoration: InputDecoration(
                                labelText: translate('Recipient username'))),
                        const SizedBox(height: 8),
                        for (final permission in available)
                          CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(
                                  translate(labels[permission] ?? permission)),
                              value: selected.contains(permission),
                              onChanged: busy || permission == 'view'
                                  ? null
                                  : (value) => setState(() {
                                        if (value == true) {
                                          selected.add(permission);
                                        } else {
                                          selected.remove(permission);
                                        }
                                      })),
                        DropdownButtonFormField<int>(
                            value: hours,
                            decoration: InputDecoration(
                                labelText: translate('Share duration')),
                            items: [
                              for (final option in {
                                1: 'One hour',
                                24: 'One day',
                                168: 'Seven days',
                                0: 'No expiry'
                              }.entries)
                                DropdownMenuItem(
                                    value: option.key,
                                    child: Text(translate(option.value))),
                            ],
                            onChanged: busy
                                ? null
                                : (value) =>
                                    setState(() => hours = value ?? 24)),
                        const SizedBox(height: 16),
                        Text(translate('Existing device shares')),
                        for (final share in shares)
                          ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(
                                  '${share['grantor_name']} → ${share['recipient_name']}'),
                              subtitle: Text(
                                  '${translate(share['active'] == true ? 'Active' : 'Inactive')} · '
                                  '${(share['effective_permissions'] as List).map((p) => translate(labels[p] ?? p)).join(', ')}\n'
                                  '${share['expires_at'] == null ? translate('No expiry') : DateTime.fromMillisecondsSinceEpoch((share['expires_at'] as int) * 1000).toLocal()}'),
                              trailing: share['can_revoke'] == true
                                  ? TextButton(
                                      onPressed: busy
                                          ? null
                                          : () => operation(() =>
                                              api.revoke(share['id'] as int)),
                                      child: Text(translate('Revoke share')))
                                  : null),
                        if (error != null)
                          Text(error!,
                              style: const TextStyle(color: Colors.red)),
                        if (busy) const LinearProgressIndicator(),
                      ]),
                ))),
        actions: [
          dialogButton(translate('Close'),
              onPressed: busy ? null : cancel, isOutline: true),
          dialogButton(translate('Share remote computer'),
              onPressed: busy ? null : submit),
        ],
        onSubmit: busy ? null : submit,
        onCancel: cancel,
      );
    });
  } finally {
    closed = true;
    username.dispose();
  }
}
