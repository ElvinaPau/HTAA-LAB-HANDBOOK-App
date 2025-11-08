import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '/api_config.dart';

/// Handles online data fetching with improved error handling and timeout
class ApiService {
  final Duration timeout = const Duration(seconds: 10);

  Future<List<dynamic>> fetchData(String endpoint) async {
    try {
      final url = Uri.parse('${getBaseUrl()}/api/$endpoint');
      final response = await http
          .get(url)
          .timeout(
            timeout,
            onTimeout: () {
              throw TimeoutException(
                'Request timed out after ${timeout.inSeconds} seconds',
              );
            },
          );

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is List) {
          return decoded;
        } else {
          throw Exception(
            'Expected a list but received: ${decoded.runtimeType}',
          );
        }
      } else if (response.statusCode == 404) {
        throw Exception('Endpoint not found: $endpoint');
      } else if (response.statusCode == 500) {
        throw Exception('Server error. Please try again later.');
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('Authentication required or forbidden');
      } else {
        throw Exception('Server returned status code: ${response.statusCode}');
      }
    } on TimeoutException catch (e) {
      throw Exception(
        'Request timed out. Please check your connection and try again.',
      );
    } on http.ClientException catch (e) {
      throw Exception(
        'Network error: ${e.message}. Please check your internet connection.',
      );
    } on FormatException catch (e) {
      throw Exception('Invalid data format received from server');
    } catch (e) {
      if (e.toString().contains('SocketException')) {
        throw Exception(
          'Unable to connect to server. Please check your internet connection.',
        );
      }
      rethrow;
    }
  }

  /// Optional: Add a method to check server health
  Future<bool> checkConnection() async {
    try {
      final url = Uri.parse('${getBaseUrl()}/api/health');
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
