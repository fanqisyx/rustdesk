import 'dart:convert';
import 'enterprise_http.dart';

class CompanySharingException implements Exception {
  final String message;
  CompanySharingException(this.message);
  @override
  String toString() => message;
}

class CompanyDeviceSharing {
  final String server;
  final String token;
  final String httpOrigin;
  CompanyDeviceSharing(String server, this.token, {this.httpOrigin = ''})
      : server = companyServerOrigin(server, httpOrigin: httpOrigin);

  Future<dynamic> _request(String method, String path,
      {Map<String, dynamic>? body}) async {
    if (token.isEmpty)
      throw CompanySharingException('Company login is required');
    final response = await companyRequest(Uri.parse('$server$path'), method,
        httpOrigin: httpOrigin,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token'
        },
        body: body == null ? null : jsonEncode(body));
    final data = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CompanySharingException(data is Map && data['error'] is String
          ? data['error']
          : 'Device sharing request failed');
    }
    return data;
  }

  Future<Map<String, dynamic>> options(String deviceId) async =>
      Map<String, dynamic>.from(await _request('GET',
          '/api/device-shares/options/${Uri.encodeComponent(deviceId)}'));

  Future<List<Map<String, dynamic>>> list(String deviceId) async {
    final data = await _request(
        'GET', '/api/device-shares?device_id=${Uri.encodeComponent(deviceId)}');
    return (data as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> share(String deviceId, String username, List<String> permissions,
      {int? expiresAt}) async {
    await _request('POST', '/api/device-shares', body: {
      'device_id': deviceId,
      'username': username.trim(),
      'permissions': permissions,
      'expires_at': expiresAt,
    });
  }

  Future<void> revoke(int shareId) async {
    await _request('DELETE', '/api/device-shares/$shareId');
  }
}
