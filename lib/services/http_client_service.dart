import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'encryption_service.dart';

class HttpClientService {
  // AES-256 E2E Encryption Final Patch (UniShare)
  // Keep session PIN in memory after successful verifyPin.
  static String? sessionPin;

  static String? _authToken;
  static String? get authToken => _authToken;
  static set authToken(String? v) {
    // When client clears token (disconnect), clear session PIN from memory as well
    if (v == null) sessionPin = null;
    _authToken = v;
  }

  static Map<String, String> get _authHeaders {
    if (authToken == null || authToken!.isEmpty) return {};
    return {'X-Auth-Token': authToken!};
  }

  // =========================
  // AUTH
  // =========================

  static String? lastVerifyError;

  /// Verifies PIN with server. Returns token on success, null on failure.
  /// Sets [lastVerifyError] when failed (e.g. "Invalid PIN", "Another device is already connected").
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
        // Store session PIN in memory for E2E encryption/decryption
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

  /// Ping with auth token.
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

  // =========================
  // PC → PHONE
  // =========================

  static Future<List<String>> getFiles(String baseUrl) async {
    final res = await http.get(
      Uri.parse('$baseUrl/files'),
      headers: _authHeaders,
    );

    if (res.statusCode != 200) {
      throw Exception('Failed to fetch file list');
    }

    final data = jsonDecode(res.body) as List;
    return data.map((e) => e.toString()).toList();
  }

  static Future<void> downloadFile(
    String baseUrl,
    String fileName,
    String savePath,
  ) async {
    final res = await http.get(
      Uri.parse('$baseUrl/files/$fileName'),
      headers: _authHeaders,
    );

    if (res.statusCode != 200) {
      throw Exception('Failed to download file');
    }

    final isEncrypted = (res.headers['x-encrypted'] ?? '').toLowerCase() == 'true';
    final file = File(savePath);

    if (isEncrypted) {
      if (sessionPin == null || sessionPin!.isEmpty) {
        throw Exception('Missing session PIN for decryption');
      }
      final encrypted = res.bodyBytes;
      final decrypted = await EncryptionService.decryptBytes(
          Uint8List.fromList(encrypted), sessionPin!);
      await file.writeAsBytes(decrypted);
    } else {
      await file.writeAsBytes(res.bodyBytes);
    }
  }

  // =========================
  // PHONE → PC
  // =========================

  static Future<void> uploadFile(String baseUrl, File file) async {
    final uri = Uri.parse('$baseUrl/upload');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_authHeaders);

    // AES-256 E2E Cleanup Patch (UniShare)
    // If we have a session PIN, encrypt bytes before uploading
    if (sessionPin != null && sessionPin!.isNotEmpty) {
      request.headers['X-Encrypted'] = 'true';
      final bytes = await file.readAsBytes();
      final encrypted = await EncryptionService.encryptBytes(
          Uint8List.fromList(bytes), sessionPin!);
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          encrypted,
          filename: path.basename(file.path),
        ),
      );
    } else {
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path,
          filename: path.basename(file.path),
        ),
      );
    }

    final response = await request.send();

    if (response.statusCode != 200) {
      throw Exception('Upload failed');
    }
  }

  // =========================
  // LOCAL (PHONE) STORAGE
  // =========================

  /// Download folder path (Android: external Downloads; others: app documents).
  static Future<String> getDownloadPath(String fileName) async {
    Directory dir;
    if (Platform.isAndroid) {
      dir = Directory('/storage/emulated/0/Download/UniShare');
    } else {
      final base = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      dir = Directory(path.join(base.path, 'UniShare'));
    }
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return path.join(dir.path, fileName);
  }

  /// History = already downloaded files
  static Future<List<String>> getLocalHistory() async {
    Directory dir;
    if (Platform.isAndroid) {
      dir = Directory('/storage/emulated/0/Download/UniShare');
    } else {
      final base = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      dir = Directory(path.join(base.path, 'UniShare'));
    }
    if (!await dir.exists()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .map((f) => path.basename(f.path))
        .toList();
  }
}
