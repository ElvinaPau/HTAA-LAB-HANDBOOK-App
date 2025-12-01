import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:htaa_app/services/api_service.dart';
import 'package:htaa_app/services/cache_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'dart:convert';

typedef ProgressCallback = void Function(String message, double progress);

class DataPreloadService {
  final ApiService _apiService = ApiService();
  final CacheService _cacheService = CacheService();

  static const String _categoriesBox = 'categoriesBox';
  static const String _testsBox = 'testsBox';
  static const String _testDetailsBox = 'testDetailsBox';

  /// Private internal constructor
  DataPreloadService._internal();

  /// Async factory constructor for automatic host IP detection
  static Future<DataPreloadService> create() async {
    return DataPreloadService._internal();
  }

  /// Get the correct base URL depending on platform
  String getBaseUrl() {
    if (kIsWeb) return 'http://localhost:5001';
    if (Platform.isAndroid) return 'http://10.0.2.2:5001';
    if (Platform.isIOS) {
      if (Platform.environment.containsKey('SIMULATOR_DEVICE_NAME')) {
        return 'http://localhost:5001'; // iOS Simulator
      } else {
        return 'http://192.168.0.172:5001'; // Physical device – change to your LAN IP
      }
    }
    return 'http://localhost:5001'; // Desktop fallback
  }

  /// Test server connectivity
  Future<bool> testServerConnection() async {
    try {
      final baseUrl = getBaseUrl();
      print('Testing connection to: $baseUrl');

      final response = await http
          .get(Uri.parse('$baseUrl/api/categories'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        print('Server connection successful');
        return true;
      } else {
        print('Server returned status: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('Server connection failed: $e');
      print('Make sure your Flask server is running on ${getBaseUrl()}');
      return false;
    }
  }

  /// Normalize any image URL to absolute URL
  String normalizeImageUrl(String imageUrl) {
    final baseUrl = getBaseUrl();

    // If it's already a full URL, check if it uses localhost and replace it
    if (imageUrl.startsWith('http://localhost:') ||
        imageUrl.startsWith('http://127.0.0.1:') ||
        imageUrl.startsWith('https://localhost:') ||
        imageUrl.startsWith('https://127.0.0.1:')) {
      // Extract the path after the port number
      final uri = Uri.parse(imageUrl);
      final path = uri.path;
      print('Converting localhost URL to: $baseUrl$path');
      return '$baseUrl$path';
    }

    // If it's already a full URL with correct base, return as-is
    if (imageUrl.startsWith(baseUrl)) {
      return imageUrl;
    }

    // If it's a relative path, prepend base URL
    return '$baseUrl${imageUrl.startsWith('/') ? imageUrl : '/$imageUrl'}';
  }

  /// Download and cache an image locally
  /// Returns the local file path if successful, null otherwise
  Future<String?> _downloadAndCacheImage(String imageUrl) async {
    try {
      if (imageUrl.isEmpty) return null;

      final absoluteUrl = normalizeImageUrl(imageUrl);

      // Generate unique filename from URL using MD5 hash
      final urlHash = md5.convert(utf8.encode(absoluteUrl)).toString();

      // Extract file extension from URL
      final uri = Uri.parse(absoluteUrl);
      final pathSegments = uri.path.split('/');
      final fileName = pathSegments.isNotEmpty ? pathSegments.last : '';
      final extension =
          fileName.contains('.')
              ? fileName.split('.').last.split('?').first
              : 'jpg';

      final cachedFileName = '$urlHash.$extension';

      // Get app's document directory
      final directory = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${directory.path}/cached_images');

      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }

      final filePath = '${imagesDir.path}/$cachedFileName';
      final file = File(filePath);

      // Already cached?
      if (await file.exists()) {
        print('Image already cached: $cachedFileName');
        return filePath;
      }

      // Download with timeout
      print('Downloading: $absoluteUrl');
      final response = await http
          .get(Uri.parse(absoluteUrl))
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception('Image download timeout'),
          );

      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        final sizeKB = (response.bodyBytes.length / 1024).toStringAsFixed(1);
        print('Downloaded $cachedFileName ($sizeKB KB)');
        return filePath;
      } else {
        print(
          'Failed to download image: HTTP ${response.statusCode} - $absoluteUrl',
        );
        return null;
      }
    } catch (e) {
      print('Error caching image $imageUrl: $e');
      return null;
    }
  }

  /// Preload all data with optional progress callback
  Future<void> preloadAllData({ProgressCallback? onProgress}) async {
    try {
      // Test server connection first
      final isServerOnline = await testServerConnection();
      if (!isServerOnline) {
        throw Exception(
          'Cannot connect to server at ${getBaseUrl()}. Please ensure the Flask server is running.',
        );
      }

      onProgress?.call('Fetching categories...', 0.05);
      final categories = await _apiService.fetchCategories();
      await _cacheService.saveData(
        _categoriesBox,
        'all_categories',
        categories,
      );

      int totalTasks = 0;
      int imageCount = 0;
      int imageFailures = 0;

      for (final category in categories) {
        totalTasks += 1;
        final tests = await _apiService.fetchTestsByCategory(category['id']);
        totalTasks += tests.length;
      }

      int completedTasks = 0;

      for (final category in categories) {
        final categoryId = category['id'];
        onProgress?.call(
          'Caching tests for category $categoryId...',
          completedTasks / totalTasks,
        );

        final tests = await _apiService.fetchTestsByCategory(categoryId);
        await _cacheService.saveData(_testsBox, 'tests_$categoryId', tests);
        completedTasks++;

        for (final test in tests) {
          final testId = test['id'];
          onProgress?.call(
            'Caching details for test $testId...',
            completedTasks / totalTasks,
          );

          try {
            final details = await _apiService.fetchTestDetails(testId);

            // Process and cache images
            if (details.containsKey('infos') && details['infos'] is List) {
              for (var info in details['infos']) {
                if (info is Map && info.containsKey('extraData')) {
                  final extraData = info['extraData'];

                  if (extraData is Map) {
                    dynamic imageData = extraData['image'];
                    String? imageUrl;

                    if (imageData is String && imageData.isNotEmpty) {
                      imageUrl = imageData;
                    } else if (imageData is Map && imageData['url'] != null) {
                      imageUrl = imageData['url'].toString();
                    }

                    if (imageUrl != null && imageUrl.isNotEmpty) {
                      final isAlreadyLocalFile = imageUrl.contains(
                        'cached_images/',
                      );
                      if (isAlreadyLocalFile) continue;

                      final downloadUrl = normalizeImageUrl(imageUrl);
                      final localPath = await _downloadAndCacheImage(
                        downloadUrl,
                      );

                      if (localPath != null) {
                        if (imageData is String) {
                          extraData['image'] = localPath;
                        } else if (imageData is Map) {
                          extraData['image'] = {
                            'url': localPath,
                            'originalUrl': imageUrl,
                            'isLocalCache': true,
                          };
                        }
                        imageCount++;
                      } else {
                        imageFailures++;
                        if (imageData is String) {
                          extraData['image'] = downloadUrl;
                        } else if (imageData is Map) {
                          extraData['image'] = {
                            'url': downloadUrl,
                            'isLocalCache': false,
                          };
                        }
                      }
                    }
                  }
                }
              }
            }

            await _cacheService.saveData(
              _testDetailsBox,
              'test_details_$testId',
              details,
            );
          } catch (e) {
            print('Failed to fetch details for test $testId: $e');
          }

          completedTasks++;
        }
      }

      onProgress?.call('All data preloaded successfully', 1.0);
      print('All data preloaded successfully.');
      print('Images cached: $imageCount');
      if (imageFailures > 0) {
        print('Image download failures: $imageFailures');
      }
    } catch (e) {
      print('Preload error: $e');
      rethrow;
    }
  }

  /// Clear all cached images
  Future<void> clearImageCache() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${directory.path}/cached_images');

      if (await imagesDir.exists()) {
        await imagesDir.delete(recursive: true);
        print('Image cache cleared');
      }
    } catch (e) {
      print('Error clearing image cache: $e');
    }
  }

  /// Get cache statistics
  Future<Map<String, dynamic>> getCacheStats() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${directory.path}/cached_images');

      if (!await imagesDir.exists()) {
        return {'imageCount': 0, 'totalSize': 0};
      }

      final files = imagesDir.listSync();
      int totalSize = 0;

      for (var file in files) {
        if (file is File) {
          totalSize += await file.length();
        }
      }

      return {
        'imageCount': files.length,
        'totalSize': totalSize,
        'totalSizeMB': (totalSize / (1024 * 1024)).toStringAsFixed(2),
      };
    } catch (e) {
      print('Error getting cache stats: $e');
      return {'imageCount': 0, 'totalSize': 0, 'error': e.toString()};
    }
  }
}
