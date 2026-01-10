import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:mime/mime.dart';

class ServerService {
  HttpServer? _server;
  late String ip;
  late int port;

  final Map<String, File> _sharedFiles = {};

  /// Start server
  Future<void> start() async {
    final router = Router();

    router.get('/ping', (Request request) {
      return Response.ok('OK');
    });

    router.get('/files', _handleFileList);
    router.get('/files/<name>', _handleFileDownload);

    ip = await _getLocalIp();
    port = 52343;

    _server = await shelf_io.serve(router, ip, port);
    print('Server running at http://$ip:$port');
  }

  /// Stop server
  Future<void> stop() async {
    await _server?.close(force: true);
    _sharedFiles.clear();
  }

  /// Register file to share
  void addFile(File file) {
    final name = path.basename(file.path);
    _sharedFiles[name] = file;
  }

  /// GET /files
  Response _handleFileList(Request request) {
    return Response.ok(
      jsonEncode(_sharedFiles.keys.toList()),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET /files/<name>
  Future<Response> _handleFileDownload(Request request, String name) async {
    final file = _sharedFiles[name];

    if (file == null || !await file.exists()) {
      return Response.notFound('File not found');
    }

    final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
    final stream = file.openRead();
    final length = await file.length();

    return Response.ok(
      stream,
      headers: {
        'content-type': mimeType,
        'content-length': length.toString(),
        'content-disposition': 'attachment; filename="$name"',
      },
    );
  }

  /// Get local IPv4
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
