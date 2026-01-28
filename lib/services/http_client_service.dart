import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

class HttpClientService {
  // =========================
  // PC → PHONE
  // =========================

  static Future<List<String>> getFiles(String baseUrl) async {
    final res = await http.get(Uri.parse('$baseUrl/files'));

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
    final res = await http.get(Uri.parse('$baseUrl/files/$fileName'));

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
