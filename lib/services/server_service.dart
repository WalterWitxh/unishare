import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:typed_data';
import 'dart:math';
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:mime/mime.dart';
import 'encryption_service.dart';

class ServerService {
  HttpServer? _server;
  late String ip;
  late int port;

  // PIN authentication
  String? _sessionPin;
  final Set<String> _validTokens = {};

  // Connection tracking
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  bool _isConnected = false;
  Timer? _disconnectTimer;
  final Duration _disconnectTimeout = const Duration(seconds: 30);

  // PC → Phone
  final Map<String, File> _sharedFiles = {};

  // Phone → PC
  Directory? _receiveDir;

  // UPLOAD STATE (SOURCE OF TRUTH)
  final Map<String, bool> _uploading = {};

  // Callback fired when a file is fully received
  void Function(String fileName)? onFileReceived;

  // Track last saved file hash
  String? lastSavedSha;

  String? get sessionPin => _sessionPin;

  String _generatePin() {
    final r = Random();
    return List.generate(6, (_) => r.nextInt(10)).join();
  }

  Response? _requireAuth(Request request) {
    final token =
        request.headers['x-auth-token'] ?? request.headers['X-Auth-Token'];
    if (token == null || token.isEmpty || !_validTokens.contains(token)) {
      return Response(401, body: 'Unauthorized');
    }
    return null;
  }

  // ================= START / STOP =================

  Future<void> start() async {
    final router = Router();

    router.post('/verify-pin', _handleVerifyPin);
    router.get('/ping', _handlePing);
    router.get('/files', _handleFileList);
    router.get('/files/<name>', _handleFileDownload);
    router.post('/upload', _handleUpload);

    _sessionPin = _generatePin();
    _validTokens.clear();
    _ensureReceiveDir();

    ip = await _getLocalIp();
    port = 52343;

    _server = await shelf_io.serve(router, InternetAddress.anyIPv4, port);
    print('Server running at http://$ip:$port');
    print('Session PIN: $_sessionPin');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _sharedFiles.clear();
    _uploading.clear();
    _sessionPin = null;
    _validTokens.clear();
    _disconnectTimer?.cancel();
  }

  // ================= PC → PHONE =================

  void addFile(File file) {
    _sharedFiles[path.basename(file.path)] = file;
  }

  Future<Response> _handleVerifyPin(Request request) async {
    try {
      if (_validTokens.isNotEmpty) {
        return Response(
          403,
          body: jsonEncode({'error': 'Another device is already connected'}),
        );
      }
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final pin = json['pin']?.toString();
      if (pin == null || pin.isEmpty) {
        return Response(400, body: jsonEncode({'error': 'PIN required'}));
      }
      if (pin != _sessionPin) {
        return Response(401, body: jsonEncode({'error': 'Invalid PIN'}));
      }
      _validTokens.clear();
      final token =
          _generatePin() + DateTime.now().millisecondsSinceEpoch.toString();
      _validTokens.add(token);
      return Response.ok(
        jsonEncode({'token': token}),
        headers: {'content-type': 'application/json'},
      );
    } catch (_) {
      return Response(400, body: jsonEncode({'error': 'Invalid request'}));
    }
  }

  Response _handleFileList(Request request) {
    final authErr = _requireAuth(request);
    if (authErr != null) return authErr;
    return Response.ok(
      jsonEncode(_sharedFiles.keys.toList()),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _handleFileDownload(Request request, String name) async {
    final authErr = _requireAuth(request);
    if (authErr != null) return authErr;
    final file = _sharedFiles[name];
    if (file == null || !await file.exists()) {
      return Response.notFound('File not found');
    }

    // Skip encryption for large files (>50MB) to avoid OOM
    final fileSize = await file.length();
    if (_sessionPin != null &&
        _sessionPin!.isNotEmpty &&
        fileSize < 50 * 1024 * 1024) {
      final bytes = await file.readAsBytes();
      final encrypted = await EncryptionService.encryptBytes(
        Uint8List.fromList(bytes),
        _sessionPin!,
      );
      return Response.ok(
        encrypted,
        headers: {
          'content-type':
              lookupMimeType(file.path) ?? 'application/octet-stream',
          'content-length': encrypted.length.toString(),
          'content-disposition': 'attachment; filename="$name"',
          'x-encrypted': 'true',
        },
      );
    }

    // Stream directly for large files or when no PIN
    return Response.ok(
      file.openRead(),
      headers: {
        'content-type': lookupMimeType(file.path) ?? 'application/octet-stream',
        'content-length': fileSize.toString(),
        'content-disposition': 'attachment; filename="$name"',
      },
    );
  }

  // ================= PHONE → PC =================

  Future<Response> _handleUpload(Request request) async {
    final authErr = _requireAuth(request);
    if (authErr != null) return authErr;
    _ensureReceiveDir();
    _onPing(); // mark connected at start of upload

    final contentType = request.headers['content-type'];
    if (contentType == null || !contentType.contains('multipart/form-data')) {
      return Response(400, body: 'Expected multipart/form-data');
    }

    // Keep-alive timer: resets disconnect timer every 10s during long uploads
    final keepAliveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _onPing();
    });

    try {
      final boundary = contentType.split('boundary=').last;
      final transformer = MimeMultipartTransformer(boundary);
      final isEncrypted =
          (request.headers['x-encrypted'] ?? '').toLowerCase() == 'true';

      await for (final part in transformer.bind(request.read())) {
        final disposition = part.headers['content-disposition'];
        if (disposition == null) continue;

        final match = RegExp(r'filename="(.+)"').firstMatch(disposition);
        if (match == null) continue;

        final filename = match.group(1)!;
        _uploading[filename] = true;
        _connectionController.add(_isConnected); // notify UI: receiving started

        final file = File(path.join(_receiveDir!.path, filename));

        try {
          if (isEncrypted) {
            // Encrypted: buffer all chunks then decrypt
            final bb = BytesBuilder();
            await for (final chunk in part) {
              bb.add(chunk);
            }
            final partBytes = Uint8List.fromList(bb.takeBytes());
            final decrypted = await EncryptionService.decryptBytes(
              partBytes,
              _sessionPin!,
            );
            await file.writeAsBytes(decrypted);
          } else {
            // Unencrypted: stream chunks directly to disk (no memory buffer)
            final sink = file.openWrite();
            try {
              await for (final chunk in part) {
                sink.add(chunk);
              }
              await sink.flush();
            } finally {
              await sink.close();
            }

            // Compute SHA only for small files to avoid reading large files back into RAM
            try {
              final savedSize = await file.length();
              if (savedSize < 50 * 1024 * 1024) {
                final savedBytes = await file.readAsBytes();
                lastSavedSha = sha256.convert(savedBytes).toString();
              } else {
                lastSavedSha = null;
              }
            } catch (_) {
              lastSavedSha = null;
            }
          }
        } finally {
          _uploading[filename] = false;
          _connectionController.add(_isConnected); // notify UI: receiving done
          onFileReceived?.call(filename); // notify desktop UI with snackbar
        }

        _onPing(); // reset disconnect timer after each file
      }
    } finally {
      keepAliveTimer.cancel();
    }

    return Response.ok('Saved');
  }

  // ================= STATUS =================

  bool isReceiving(String filename) {
    return _uploading[filename] == true;
  }

  // ================= CONNECTION =================

  Response _handlePing(Request request) {
    final authErr = _requireAuth(request);
    if (authErr != null) return authErr;
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
      _validTokens.clear();
      _connectionController.add(false);
    });
  }

  Stream<bool> get connectionStream => _connectionController.stream;

  // ================= IP DETECTION =================

  Future<String> detectLocalIp() async {
    return await _getLocalIp();
  }

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
    final home = Platform.isWindows
        ? Platform.environment['USERPROFILE']
        : Platform.environment['HOME'];
    return home == null
        ? Directory(path.join(path.current, 'received'))
        : Directory(path.join(home, 'Downloads', 'UniShare'));
  }

  Future<String> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      final preferredPatterns = [
        RegExp(r'wi-?fi|wlan', caseSensitive: false),
        RegExp(r'ethernet', caseSensitive: false),
      ];

      // First pass: prefer Wi-Fi / WLAN (mobile hotspot shows up here)
      for (final pattern in preferredPatterns) {
        for (final iface in interfaces) {
          if (pattern.hasMatch(iface.name)) {
            for (final addr in iface.addresses) {
              if (_isValidIp(addr.address)) {
                print('Selected IP from ${iface.name}: ${addr.address}');
                return addr.address;
              }
            }
          }
        }
      }

      // Second pass: any valid interface
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (_isValidIp(addr.address)) {
            print('Selected IP from ${iface.name}: ${addr.address}');
            return addr.address;
          }
        }
      }
    } catch (e) {
      print('Error detecting IP: $e');
    }

    return '127.0.0.1';
  }

  bool _isValidIp(String address) {
    if (address.startsWith('169.254.')) return false; // link-local
    if (address.startsWith('127.')) return false; // loopback
    if (address.startsWith('::')) return false; // IPv6
    return true;
  }
}
