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
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );

    if (interfaces.isEmpty) {
      return '127.0.0.1';
    }

    // Windows network interface names
    final windowsWifiNames = ['wi-fi', 'wifi', 'wlan', 'wireless'];
    final windowsEthernetNames = ['ethernet', 'local area connection'];

    // Linux network interface names
    final linuxWifiNames = ['wlan', 'wl', 'wifi'];
    final linuxEthernetNames = ['eth', 'enp', 'eno', 'ens'];

    // Priority order: Wi-Fi > Ethernet > Others
    // Check for Wi-Fi interfaces first
    for (final iface in interfaces) {
      final nameLower = iface.name.toLowerCase();

      // Check if it's a Wi-Fi interface
      final isWifi =
          windowsWifiNames.any((pattern) => nameLower.contains(pattern)) ||
          linuxWifiNames.any((pattern) => nameLower.contains(pattern));

      if (isWifi && iface.addresses.isNotEmpty) {
        // Skip link-local addresses (169.254.x.x)
        for (final addr in iface.addresses) {
          if (!addr.address.startsWith('169.254.')) {
            return addr.address;
          }
        }
      }
    }

    // Check for Ethernet interfaces
    for (final iface in interfaces) {
      final nameLower = iface.name.toLowerCase();

      final isEthernet =
          windowsEthernetNames.any((pattern) => nameLower.contains(pattern)) ||
          linuxEthernetNames.any((pattern) => nameLower.contains(pattern));

      if (isEthernet && iface.addresses.isNotEmpty) {
        // Skip link-local addresses (169.254.x.x)
        for (final addr in iface.addresses) {
          if (!addr.address.startsWith('169.254.')) {
            return addr.address;
          }
        }
      }
    }

    // Fallback: Use first non-link-local address
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.address.startsWith('169.254.') &&
            !addr.address.startsWith('127.')) {
          return addr.address;
        }
      }
    }

    // Last resort: first available address
    return interfaces.first.addresses.first.address;
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
