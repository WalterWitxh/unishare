import 'package:http/http.dart' as http;

class ConnectionService {
  /// Checks whether the desktop server is reachable
  static Future<bool> testConnection(String baseUrl) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/ping'))
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
