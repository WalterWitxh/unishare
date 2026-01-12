import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';

class ServerService {
  HttpServer? _server;
  late String ip;
  late int port;
  late Directory _receivedDir;

  // PC → Phone files
  final Map<String, File> _sharedFiles = {};

  /// Start HTTP server
  Future<void> start() async {
    final router = Router();

    // ---------- BASIC ----------
    router.get('/ping', (Request request) {
      return Response.ok('OK');
    });

    // ---------- PC → PHONE ----------
    router.get('/files', _handleFileList);
    router.get('/files/<name>', _handleFileDownload);

    // ---------- PHONE → PC ----------
    router.post('/upload', _handleUpload);

    // Setup
    ip = await _getLocalIp();
    port = 52343;

    _receivedDir = Directory('received');
    if (!await _receivedDir.exists()) {
      await _receivedDir.create(recursive: true);
    }

    _server = await shelf_io.serve(router, InternetAddress.anyIPv4, port);

    print('Server running at http://$ip:$port');
  }

  /// Stop server
  Future<void> stop() async {
    await _server?.close(force: true);
    _sharedFiles.clear();
  }

  /// Register file (PC → Phone)
  void addFile(File file) {
    final name = path.basename(file.path);
    _sharedFiles[name] = file;
  }

  // ============================
  // PC → PHONE
  // ============================

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

    return Response.ok(
      file.openRead(),
      headers: {
        'content-type': mimeType,
        'content-length': (await file.length()).toString(),
        'content-disposition': 'attachment; filename="$name"',
      },
    );
  }

  // ============================
  // PHONE → PC
  // ============================

  /// POST /upload (multipart/form-data)
  Future<Response> _handleUpload(Request request) async {
    final contentType = request.headers['content-type'];

    if (contentType == null || !contentType.contains('multipart/form-data')) {
      return Response(400, body: 'Expected multipart/form-data');
    }

    final boundary = contentType.split('boundary=').last;
    final transformer = MimeMultipartTransformer(boundary);

    await for (final part in transformer.bind(request.read())) {
      final disposition = part.headers['content-disposition'];
      if (disposition == null) continue;

      final match = RegExp(r'filename="(.+)"').firstMatch(disposition);
      if (match == null) continue;

      final filename = match.group(1)!;
      final file = File(path.join(_receivedDir.path, filename));

      final sink = file.openWrite();
      await part.pipe(sink);
      await sink.close();

      print('📥 Received from phone: ${file.path}');
    }

    return Response.ok('Upload successful');
  }

  // ============================
  // NETWORK
  // ============================

  /// Get local IPv4
  Future<String> _getLocalIp() async {
    for (final iface in await NetworkInterface.list()) {
      for (final addr in iface.addresses) {
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          return addr.address;
        }
      }
    }
    return '127.0.0.1';
  }

  List<File> getReceivedFiles() {
    if (!_receivedDir.existsSync()) return [];
    return _receivedDir.listSync().whereType<File>().toList();
  }
}
