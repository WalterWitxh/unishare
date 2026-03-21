import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'encryption_service.dart';

class HttpClientService {
  // pin for encryption
  static String? sessionPin;

  static String? _authToken;
  static String? get authToken => _authToken;
  static set authToken(String? v) {
    if (v == null) sessionPin = null; // clear PIN on disconnect
    _authToken = v;
  }

  // shelf makes headers lowercase
  static Map<String, String> get _authHeaders {
    if (authToken == null || authToken!.isEmpty) return {};
    return {'x-auth-token': authToken!};
  }

  // auth
  static String? lastVerifyError;

  static Future<String?> verifyPin(String baseUrl, String pin) async {
    lastVerifyError = null;
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/verify-pin'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'pin': pin}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        sessionPin = pin;
        return data['token']?.toString();
      }
      try {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        lastVerifyError = data['error']?.toString() ?? 'Connection failed';
      } catch (_) {
        lastVerifyError = res.statusCode == 403
            ? 'Another device is already connected'
            : 'Connection failed';
      }
      return null;
    } catch (_) {
      lastVerifyError = 'Connection failed';
      return null;
    }
  }

  static Future<bool> ping(String baseUrl) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/ping'),
        headers: _authHeaders,
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // download to phone
  static Future<List<String>> getFiles(String baseUrl) async {
    final res = await http.get(
      Uri.parse('$baseUrl/files'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) throw Exception('Failed to fetch file list');
    final data = jsonDecode(res.body) as List;
    return data.map((e) => e.toString()).toList();
  }

  // download file
  static Future<void> downloadFile(
    String baseUrl,
    String fileName,
    String savePath,
  ) async {
    final res = await http
        .get(Uri.parse('$baseUrl/files/$fileName'), headers: _authHeaders)
        .timeout(
          const Duration(minutes: 10),
          onTimeout: () => throw Exception('Download timed out'),
        );

    if (res.statusCode != 200) {
      throw Exception('Download failed (HTTP ${res.statusCode})');
    }

    // server sends lowercase
    final isEncrypted =
        (res.headers['x-encrypted'] ?? '').toLowerCase() == 'true';

    final file = File(savePath);

    if (isEncrypted && sessionPin != null && sessionPin!.isNotEmpty) {
      // decrypt
      final decrypted = await EncryptionService.decryptBytes(
        Uint8List.fromList(res.bodyBytes),
        sessionPin!,
      );
      await file.writeAsBytes(decrypted);
    } else {
      // write bytes
      await file.writeAsBytes(res.bodyBytes);
    }
  }

  // upload to pc
  static Future<void> uploadFile(String baseUrl, File file) async {
    final uri = Uri.parse('$baseUrl/upload');
    final fileName = path.basename(file.path);
    final fileSize = await file.length();

    // encrypt small files
    final useEncryption =
        sessionPin != null &&
        sessionPin!.isNotEmpty &&
        fileSize < 50 * 1024 * 1024;

    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_authHeaders);

    if (useEncryption) {
      request.headers['x-encrypted'] = 'true';
      final bytes = await file.readAsBytes();
      final encrypted = await EncryptionService.encryptBytes(
        Uint8List.fromList(bytes),
        sessionPin!,
      );
      request.files.add(
        http.MultipartFile.fromBytes('file', encrypted, filename: fileName),
      );
    } else {
      // stream big files
      request.files.add(
        http.MultipartFile(
          'file',
          file.openRead(),
          fileSize,
          filename: fileName,
        ),
      );
    }

    final streamed = await request.send().timeout(
      const Duration(minutes: 15),
      onTimeout: () => throw Exception('Upload timed out'),
    );

    // finish request
    await streamed.stream.drain<void>();

    if (streamed.statusCode != 200) {
      throw Exception('Upload failed (HTTP ${streamed.statusCode})');
    }
  }

  // local files
  static Future<String> getDownloadPath(String fileName) async {
    final dir = await _uniShareDir();
    return path.join(dir.path, fileName);
  }

  static Future<List<String>> getLocalHistory() async {
    final dir = await _uniShareDir();
    if (!await dir.exists()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .map((f) => path.basename(f.path))
        .toList();
  }

  static Future<Directory> _uniShareDir() async {
    Directory dir;
    if (Platform.isAndroid) {
      dir = Directory('/storage/emulated/0/Download/UniShare');
    } else {
      final base =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      dir = Directory(path.join(base.path, 'UniShare'));
    }
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
