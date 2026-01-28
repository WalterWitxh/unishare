import 'dart:io';
import 'dart:async';
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

  // Connection tracking
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  bool _isConnected = false;
  Timer? _disconnectTimer;
  final Duration _disconnectTimeout = const Duration(seconds: 5);

  // PC → Phone
  final Map<String, File> _sharedFiles = {};

  // Phone → PC
  Directory? _receiveDir;

  // ✅ UPLOAD STATE (SOURCE OF TRUTH)
  final Map<String, bool> _uploading = {};

  // ================= START / STOP =================

  Future<void> start() async {
    final router = Router();

    router.get('/ping', _handlePing);
    router.get('/files', _handleFileList);
    router.get('/files/<name>', _handleFileDownload);
    router.post('/upload', _handleUpload);

    _ensureReceiveDir();

    ip = await _getLocalIp();
    port = 52343;

    _server = await shelf_io.serve(router, InternetAddress.anyIPv4, port);
    print('Server running at http://$ip:$port');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _sharedFiles.clear();
    _uploading.clear();
    _disconnectTimer?.cancel();
  }

  // ================= PC → PHONE =================

  void addFile(File file) {
    _sharedFiles[path.basename(file.path)] = file;
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

    return Response.ok(
      file.openRead(),
      headers: {
        'content-type': lookupMimeType(file.path) ?? 'application/octet-stream',
        'content-length': (await file.length()).toString(),
        'content-disposition': 'attachment; filename="$name"',
      },
    );
  }

  // ================= PHONE → PC =================

  Future<Response> _handleUpload(Request request) async {
    _ensureReceiveDir();

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
      _uploading[filename] = true;

      final file = File(path.join(_receiveDir!.path, filename));
      final sink = file.openWrite();
      await part.pipe(sink);
      await sink.close();

      _uploading[filename] = false;
      _onPing();
    }

    return Response.ok('Saved');
  }

  // ================= STATUS =================

  bool isReceiving(String filename) {
    return _uploading[filename] == true;
  }

  // ================= CONNECTION =================

  Response _handlePing(Request request) {
    _onPing();
    return Response.ok('OK');
  }

  void _onPing() {
    _disconnectTimer?.cancel();

    if (!_isConnected) {
      _isConnected = true;
      _connectionController.add(true);
    }

    _disconnectTimer = Timer(_disconnectTimeout, () {
      _isConnected = false;
      _connectionController.add(false);
    });
  }

  Stream<bool> get connectionStream => _connectionController.stream;

  // ================= FILE ACCESS =================

  List<File> getReceivedFiles() {
    _ensureReceiveDir();
    return _receiveDir!.existsSync()
        ? _receiveDir!.listSync().whereType<File>().toList()
        : [];
  }

  void _ensureReceiveDir() {
    _receiveDir ??= _getReceiveDir();
    if (!_receiveDir!.existsSync()) {
      _receiveDir!.createSync(recursive: true);
    }
  }

  Directory _getReceiveDir() {
    final userProfile = Platform.environment['USERPROFILE'];
    return userProfile == null
        ? Directory('received')
        : Directory(path.join(userProfile, 'Downloads', 'UniShare'));
  }

  Future<String> _getLocalIp() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );

    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.address.startsWith('169.') &&
            !addr.address.startsWith('127.')) {
          return addr.address;
        }
      }
    }
    return '127.0.0.1';
  }
}
