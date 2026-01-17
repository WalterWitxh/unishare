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

  // PC → Phone
  final Map<String, File> _sharedFiles = {};

  // Phone → PC (saved files)
  late Directory _receiveDir;

  Future<void> start() async {
    final router = Router();

    router.get('/ping', (_) => Response.ok('OK'));

    // PC → Phone
    router.get('/files', _handleFileList);
    router.get('/files/<name>', _handleFileDownload);

    // Phone → PC
    router.post('/upload', _handleUpload);

    _receiveDir = _getReceiveDir();
    if (!await _receiveDir.exists()) {
      await _receiveDir.create(recursive: true);
    }

    ip = await _getLocalIp();
    port = 52343;

    _server = await shelf_io.serve(router, InternetAddress.anyIPv4, port);

    print('Server running at http://$ip:$port');
    print('📁 Saving received files to: ${_receiveDir.path}');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _sharedFiles.clear();
  }

  // ================= PC → PHONE =================

  void addFile(File file) {
    final name = path.basename(file.path);
    _sharedFiles[name] = file;
  }

  Response _handleFileList(Request request) {
    return Response.ok(
      jsonEncode(_sharedFiles.keys.toList()),
      headers: {'content-type': 'application/json'},
    );
  }

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

  // ================= PHONE → PC =================

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
      final file = File(path.join(_receiveDir.path, filename));

      final sink = file.openWrite();
      await part.pipe(sink);
      await sink.close();

      print('📥 Received from phone: ${file.path}');
    }

    return Response.ok('Saved');
  }

  // ================= UTIL =================

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

  Directory _getReceiveDir() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

    if (home == null) {
      return Directory('received');
    }

    return Directory('$home/Downloads/UniShare');
  }

  List<File> getReceivedFiles() {
    if (!_receiveDir.existsSync()) return [];
    return _receiveDir.listSync().whereType<File>().toList();
  }
}
