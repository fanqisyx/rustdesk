import 'dart:convert';
import 'dart:io';
import 'package:flutter_hbb/utils/company_device_sharing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('device sharing sends authenticated, device-scoped requests', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <String>[];
    final subscription = server.listen((request) async {
      expect(
          request.headers.value('Authorization'), 'Bearer private-test-token');
      requests.add('${request.method} ${request.uri}');
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path.endsWith('/denied')) {
        request.response.statusCode = 403;
        request.response
            .write('{"error":"Device sharing permission is required"}');
      } else if (request.method == 'POST') {
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        expect(body, {
          'device_id': '123456789',
          'username': 'bob',
          'permissions': ['view', 'connect'],
          'expires_at': 1893456000
        });
        request.response.write('{"id":7}');
      } else if (request.method == 'DELETE') {
        request.response.write('{}');
      } else if (request.uri.path.contains('/options/')) {
        request.response.write(
            '{"device_id":"123456789","permissions":["view","connect"]}');
      } else {
        request.response.write('[{"id":7,"recipient_name":"bob"}]');
      }
      await request.response.close();
    });
    try {
      final api = CompanyDeviceSharing(
          'http://127.0.0.1:${server.port}', 'private-test-token');
      expect((await api.options('123456789'))['device_id'], '123456789');
      await api.share('123456789', ' bob ', ['view', 'connect'],
          expiresAt: 1893456000);
      expect((await api.list('123456789')).single['recipient_name'], 'bob');
      await api.revoke(7);
      expect(requests, [
        'GET /api/device-shares/options/123456789',
        'POST /api/device-shares',
        'GET /api/device-shares?device_id=123456789',
        'DELETE /api/device-shares/7',
      ]);
      await expectLater(
          api.options('denied'), throwsA(isA<CompanySharingException>()));
      final signedOut =
          CompanyDeviceSharing('http://127.0.0.1:${server.port}', '');
      await expectLater(signedOut.options('123456789'),
          throwsA(isA<CompanySharingException>()));
      expect(requests, hasLength(5));
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });
}
