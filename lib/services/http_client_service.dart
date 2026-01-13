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
  // PHONE → PC  (NEW)
  // =========================

  static Future<void> uploadFile(String baseUrl, File file) async {
    final uri = Uri.parse('$baseUrl/upload');

    final request = http.MultipartRequest('POST', uri);

    request.files.add(
      await http.MultipartFile.fromPath(
        'file', // field name
        file.path,
        filename: file.path.split('/').last,
      ),
    );

    final response = await request.send();

    if (response.statusCode != 200) {
      throw Exception('Upload failed (${response.statusCode})');
    }
  }

 // =========================
// PHONE → PC (Incoming queue)
// =========================

static Future<List<String>> getIncomingFiles(String baseUrl) async {
  final res = await http.get(Uri.parse('$baseUrl/incoming'));

  if (res.statusCode != 200) {
    throw Exception('Failed to fetch incoming files');
  }

  final data = jsonDecode(res.body) as List;
  return data.map((e) => e.toString()).toList();
}

static Future<void> downloadIncoming(
  String baseUrl,
  String fileName,
  String savePath,
) async {
  final res = await http.get(Uri.parse('$baseUrl/incoming/$fileName'));

  if (res.statusCode != 200) {
    throw Exception('Download failed');
  }

  final file = File(savePath);
  await file.writeAsBytes(res.bodyBytes);
}


}
