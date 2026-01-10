import 'dart:io';
import 'package:http/http.dart' as http;

class HttpClientService {
  /// Get list of files from desktop server
  static Future<List<String>> getFiles(String baseUrl) async {
    final res = await http.get(Uri.parse('$baseUrl/files'));

    if (res.statusCode != 200) {
      throw Exception('Failed to fetch file list');
    }

    return res.body
        .replaceAll('[', '')
        .replaceAll(']', '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// Download file from desktop server
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
}
