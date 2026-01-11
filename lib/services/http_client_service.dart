import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';

class HttpClientService {
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
}
