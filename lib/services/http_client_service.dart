import 'package:http/http.dart' as http;

class HttpClientService {
  /// Test if the desktop server is reachable
  static Future<bool> testConnection(String baseUrl) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/ping'))
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200 && response.body == 'OK';
    } catch (_) {
      return false;
    }
  }
}
