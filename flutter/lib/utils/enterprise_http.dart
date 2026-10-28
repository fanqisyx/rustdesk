import 'dart:convert';

import 'package:http/http.dart' as http;

String companyServerOrigin(String value, {String httpOrigin = ''}) {
  final uri = Uri.tryParse(value.trim());
  final loopback =
      uri != null && const ['localhost', '127.0.0.1', '::1'].contains(uri.host);
  if (uri == null ||
      uri.host.isEmpty ||
      !(uri.scheme == 'https' ||
          uri.scheme == 'http' && (loopback || uri.origin == httpOrigin)) ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw const FormatException(
        'Use HTTPS or explicitly enable plaintext HTTP for this server');
  }
  return uri.origin;
}

Future<http.Response> registerCompanyAccount(String server, String username,
    String password, String passwordConfirmation,
    {String displayName = '', String httpOrigin = ''}) {
  final origin = companyServerOrigin(server, httpOrigin: httpOrigin);
  final account = username.trim();
  if (!RegExp(r'^[a-zA-Z0-9_.@-]{1,80}$').hasMatch(account)) {
    throw const FormatException(
        'Use 1 to 80 letters, digits, or _.@- for your username');
  }
  if (password.runes.length < 12 || password.runes.length > 1024) {
    throw const FormatException('Password must contain 12 to 1024 characters');
  }
  if (password != passwordConfirmation) {
    throw const FormatException('Passwords do not match');
  }
  return companyRequest(Uri.parse('$origin/api/register'), 'POST',
      httpOrigin: httpOrigin,
      body: jsonEncode({
        'username': account,
        'display_name': displayName.trim(),
        'password': password,
        'password_confirmation': passwordConfirmation,
      }));
}

Future<http.Response> companyRequest(Uri url, String method,
    {Map<String, String>? headers, Object? body, String httpOrigin = ''}) async {
  companyServerOrigin(url.origin, httpOrigin: httpOrigin);
  final client = http.Client();
  try {
    final request = http.Request(method.toUpperCase(), url)
      ..followRedirects = false;
    request.headers.addAll(headers ?? {'Content-Type': 'application/json'});
    if (body != null) request.body = body as String;
    final response =
        await client.send(request).timeout(const Duration(seconds: 15));
    return await http.Response.fromStream(response)
        .timeout(const Duration(seconds: 15));
  } finally {
    client.close();
  }
}
