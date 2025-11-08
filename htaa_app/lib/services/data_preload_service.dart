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

  final String hostIp;

  /// Private internal constructor
  DataPreloadService._internal(this.hostIp);

  /// Async factory constructor for automatic host IP detection
  static Future<DataPreloadService> create() async {
    final hostIp = await _detectHostIp();
    return DataPreloadService._internal(hostIp);
  }

  /// Detect host IP based on platform
  static Future<String> _detectHostIp() async {
    if (kIsWeb) return 'localhost';
    if (Platform.isAndroid) return '10.0.2.2'; // Android emulator → localhost
    if (Platform.isIOS) {
      final info = await DeviceInfoPlugin().iosInfo;
      final isSimulator = !(info.isPhysicalDevice ?? false);
      if (isSimulator) return 'localhost'; // iOS simulator → Mac localhost
      // Real iOS device → replace with your Mac/PC LAN IP
      return '10.167.177.92';
    }
    // Fallback for other platforms
    return '192.168.1.100';
  }

  /// Fix image URLs to use the correct host IP
  String fixImageUrl(String url) {
    if (url.isEmpty) return url;
    return url.replaceAll(RegExp(r'^http://localhost'), 'http://$hostIp');
  }

  /// Download and cache an image locally
  /// Returns the local file path if successful, null otherwise
  Future<String?> _downloadAndCacheImage(String imageUrl) async {
    try {
      // Skip if URL is empty
      if (imageUrl.isEmpty) return null;

      // Convert relative paths to absolute URLs
      String absoluteUrl = imageUrl;
      if (!imageUrl.startsWith('http')) {
        // It's a relative path, prepend the base URL
        absoluteUrl = 'http://$hostIp:5001$imageUrl';
        print('📍 Converting relative path to: $absoluteUrl');
      }

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

      // Create directory if it doesn't exist
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }

      final filePath = '${imagesDir.path}/$cachedFileName';
      final file = File(filePath);

      // Check if already cached
      if (await file.exists()) {
        print('✓ Image already cached: $cachedFileName');
        return filePath;
      }

      // Download image with timeout
      print('⬇️ Downloading image: $absoluteUrl');
      final response = await http
          .get(Uri.parse(absoluteUrl))
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('Image download timeout');
            },
          );

      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        print(
          '✓ Image cached successfully: $cachedFileName (${response.bodyBytes.length} bytes)',
        );
        return filePath;
      } else {
        print('⚠️ Failed to download image: HTTP ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Error caching image $imageUrl: $e');
      return null;
    }
  }

  /// Preload all data with optional progress callback
  Future<void> preloadAllData({ProgressCallback? onProgress}) async {
    try {
      onProgress?.call('🔄 Fetching categories...', 0.05);
      final categories = await _apiService.fetchCategories();
      await _cacheService.saveData(
        _categoriesBox,
        'all_categories',
        categories,
      );

      // Calculate total tasks for progress tracking
      int totalTasks = 0;
      int imageCount = 0;

      for (final category in categories) {
        totalTasks += 1; // each category
        final tests = await _apiService.fetchTestsByCategory(category['id']);
        totalTasks += tests.length; // each test detail
      }

      int completedTasks = 0;

      for (final category in categories) {
        final categoryId = category['id'];
        onProgress?.call(
          '📦 Caching tests for category $categoryId...',
          completedTasks / totalTasks,
        );

        final tests = await _apiService.fetchTestsByCategory(categoryId);
        await _cacheService.saveData(_testsBox, 'tests_$categoryId', tests);
        completedTasks++;

        for (final test in tests) {
          final testId = test['id'];
          onProgress?.call(
            '🧪 Caching details for test $testId...',
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
                    // Look for image in extraData
                    dynamic imageData = extraData['image'];
                    String? imageUrl;

                    // Extract the URL from different formats
                    if (imageData is String && imageData.isNotEmpty) {
                      imageUrl = imageData;
                    } else if (imageData is Map && imageData['url'] != null) {
                      imageUrl = imageData['url'].toString();
                    }

                    // If we found an image URL/path, process it
                    if (imageUrl != null && imageUrl.isNotEmpty) {
                      print('🖼️ Processing image for test $testId: $imageUrl');

                      // IMPORTANT: Skip if it's already a local file path (from previous cache)
                      // Check if it's an absolute path (starts with platform-specific root)
                      final isAlreadyLocalFile =
                          imageUrl.startsWith('/var/') ||
                          imageUrl.startsWith('/data/') ||
                          imageUrl.contains('Documents/cached_images/');

                      if (isAlreadyLocalFile) {
                        print('✓ Already cached locally: $imageUrl');
                        // Keep the existing local path
                        continue;
                      }

                      // Convert relative paths to absolute URLs for downloading
                      String downloadUrl = imageUrl;
                      if (imageUrl.startsWith('/imgUploads') ||
                          imageUrl.startsWith('imgUploads') ||
                          imageUrl.startsWith('/uploads') ||
                          (!imageUrl.startsWith('http'))) {
                        // It's a relative path, prepend base URL
                        downloadUrl =
                            'http://$hostIp:5001${imageUrl.startsWith('/') ? imageUrl : '/$imageUrl'}';
                        print('📍 Converting relative path to: $downloadUrl');
                      }

                      // Download and cache the image
                      final localPath = await _downloadAndCacheImage(
                        downloadUrl,
                      );

                      if (localPath != null) {
                        // Update extraData with local file path
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
                        print('✅ Image cached for test $testId: $localPath');
                      } else {
                        // Keep network URL as fallback
                        final fixedUrl = downloadUrl;

                        if (imageData is String) {
                          extraData['image'] = fixedUrl;
                        } else if (imageData is Map) {
                          extraData['image'] = {
                            'url': fixedUrl,
                            'isLocalCache': false,
                          };
                        }
                        print(
                          '⚠️ Using network URL fallback for test $testId: $fixedUrl',
                        );
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
            print('⚠️ Failed to fetch details for test $testId: $e');
          }
          completedTasks++;
        }
      }

      onProgress?.call('✅ All data preloaded successfully', 1.0);
      print('✅ All data preloaded successfully.');
      print('📊 Total images cached: $imageCount');
    } catch (e) {
      print('❌ Preload error: $e');
      rethrow;
    }
  }

  /// Clear all cached images (useful for debugging or freeing space)
  Future<void> clearImageCache() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${directory.path}/cached_images');

      if (await imagesDir.exists()) {
        await imagesDir.delete(recursive: true);
        print('✅ Image cache cleared');
      }
    } catch (e) {
      print('❌ Error clearing image cache: $e');
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
      print('❌ Error getting cache stats: $e');
      return {'imageCount': 0, 'totalSize': 0, 'error': e.toString()};
    }
  }
}
