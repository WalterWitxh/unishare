import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class HttpClientService {
  static String? authToken;

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

    final file = File(savePath);
    await file.writeAsBytes(res.bodyBytes);
  }

  // =========================
  // PHONE → PC
  // =========================

  static Future<void> uploadFile(String baseUrl, File file) async {
    final uri = Uri.parse('$baseUrl/upload');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_authHeaders);

    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: path.basename(file.path),
      ),
    );

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
