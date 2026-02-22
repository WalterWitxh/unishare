import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

class HttpClientService {
  static String? authToken;

  static Map<String, String> get _authHeaders {
    if (authToken == null || authToken!.isEmpty) return {};
    return {'X-Auth-Token': authToken!};
  }

  // =========================
  // AUTH
  // =========================

  /// Verifies PIN with server. Returns token on success, null on failure.
  static Future<String?> verifyPin(String baseUrl, String pin) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/verify-pin'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'pin': pin}),
      );
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data['token']?.toString();
    } catch (_) {
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
        filename: file.path.split('/').last,
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

  /// Download folder path
  static Future<String> getDownloadPath(String fileName) async {
    final dir = Directory('/storage/emulated/0/Download/UniShare');

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return '${dir.path}/$fileName';
  }

  /// History = already downloaded files
  static Future<List<String>> getLocalHistory() async {
    final dir = Directory('/storage/emulated/0/Download/UniShare');

    if (!await dir.exists()) return [];

    return dir
        .listSync()
        .whereType<File>()
        .map((f) => f.path.split('/').last)
        .toList();
  }
}
