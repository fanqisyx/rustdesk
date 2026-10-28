import 'package:flutter_hbb/utils/enterprise_http.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';

void main() {
  test('company server accepts HTTPS origins and loopback development only',
      () {
    expect(companyServerOrigin(' https://manage.example.com/ '),
        'https://manage.example.com');
    expect(companyServerOrigin('http://127.0.0.1:21114'),
        'http://127.0.0.1:21114');
    expect(companyServerOrigin('http://[::1]:21114'), 'http://[::1]:21114');
    for (final value in [
      'http://manage.example.com',
      'https://user:password@manage.example.com',
      'https://manage.example.com/api',
      'https://manage.example.com?token=secret',
      'https://manage.example.com#fragment',
      '',
    ]) {
      expect(() => companyServerOrigin(value), throwsFormatException);
    }
  });

  test('company credentials never follow a redirect', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var forwarded = false;
    final subscription = server.listen((request) async {
      if (request.uri.path == '/login') {
        request.response.statusCode = HttpStatus.temporaryRedirect;
        request.response.headers.set('Location', '/forwarded');
      } else {
        forwarded = true;
      }
      await request.response.close();
    });
    try {
      final http.Response response = await companyRequest(
          Uri.parse('http://127.0.0.1:${server.port}/login'), 'POST',
          headers: {'Authorization': 'Bearer private'}, body: '{}');
      expect(response.statusCode, HttpStatus.temporaryRedirect);
      expect(forwarded, isFalse);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test('plaintext HTTP requires approval for the exact server and port', () {
    const server = 'http://203.0.113.10:21114';
    expect(() => companyServerOrigin(server), throwsFormatException);
    expect(companyServerOrigin(server, httpOrigin: server), server);
    for (final value in [
      'http://203.0.113.10:24443',
      'http://203.0.113.11:21114',
      '$server/api',
      'http://user:password@203.0.113.10:21114',
    ]) {
      expect(() => companyServerOrigin(value, httpOrigin: server),
          throwsFormatException);
    }
  });

  test('registration sends account fields to the same trusted server',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final received = <Map<String, dynamic>>[];
    final subscription = server.listen((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/register');
      expect(request.headers.contentType?.mimeType, 'application/json');
      expect(request.headers.value('Authorization'), isNull);
      received.add(jsonDecode(await utf8.decoder.bind(request).join()));
      request.response.statusCode = HttpStatus.created;
      request.response.write('{"type":"access_token"}');
      await request.response.close();
    });
    try {
      final response = await registerCompanyAccount(
          'http://127.0.0.1:${server.port}',
          ' employee ',
          'employee-password',
          'employee-password',
          displayName: ' Employee ');
      expect(response.statusCode, HttpStatus.created);
      expect(received.single, {
        'username': 'employee',
        'display_name': 'Employee',
        'password': 'employee-password',
        'password_confirmation': 'employee-password',
      });
      for (final values in [
        ['bad name', 'employee-password', 'employee-password'],
        ['employee', 'short', 'short'],
        ['employee', 'employee-password', 'different-password'],
      ]) {
        expect(
            () => registerCompanyAccount('http://127.0.0.1:${server.port}',
                values[0], values[1], values[2]),
            throwsFormatException);
      }
      expect(received, hasLength(1));
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test('approved HTTP supports registration and requests without redirects',
      () async {
    final server = await HttpServer.bind('127.0.0.2', 0);
    final origin = 'http://127.0.0.2:${server.port}';
    var requests = 0;
    final subscription = server.listen((request) async {
      requests++;
      await request.drain<void>();
      request.response.statusCode = request.uri.path == '/api/register' ? 201 : 307;
      request.response.headers.set('Location', '/must-not-follow');
      request.response.write('{}');
      await request.response.close();
    });
    try {
      await expectLater(companyRequest(Uri.parse('$origin/api/login'), 'POST'),
          throwsFormatException);
      expect(requests, 0);
      final registered = await registerCompanyAccount(
          origin, 'employee', 'employee-password', 'employee-password',
          httpOrigin: origin);
      expect(registered.statusCode, 201);
      final response = await companyRequest(
          Uri.parse('$origin/api/login'), 'POST', httpOrigin: origin);
      expect(response.statusCode, 307);
      expect(requests, 2);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });
}
