import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

class ServerService {
  HttpServer? _server;
  late String ip;
  late int port;

  /// Start the local HTTP server
  Future<void> start() async {
    final router = Router();

    // Simple test endpoint
    router.get('/ping', (Request request) {
      return Response.ok('OK');
    });

    // Get local IP
    ip = await _getLocalIp();
    port = 52343; // fixed for now (safe)

    _server = await shelf_io.serve(router, ip, port);

    print('Server running at http://$ip:$port');
  }

  /// Stop the server
  Future<void> stop() async {
    await _server?.close(force: true);
  }

  /// Get local IPv4 address
  Future<String> _getLocalIp() async {
    for (final interface in await NetworkInterface.list()) {
      for (final addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          return addr.address;
        }
      }
    }
    return '127.0.0.1';
  }
}
