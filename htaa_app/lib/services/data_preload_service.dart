import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
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
  static const String _metadataBox = 'metadataBox';

  // How often to check for updates
  static const Duration _updateCheckInterval = Duration(hours: 24);

  /// Private internal constructor
  DataPreloadService._internal();

  /// Async factory constructor for automatic host IP detection
  static Future<DataPreloadService> create() async {
    return DataPreloadService._internal();
  }

  /// Get the correct base URL depending on platform
  String getBaseUrl() {
    return 'https://pathology-admin-dashboard-v2.onrender.com';
  }

  /// Test server connectivity with retry logic for cold starts
  Future<bool> testServerConnection() async {
    String baseUrl = getBaseUrl();
    final isProduction = baseUrl.contains('render.com');
    final timeout = isProduction ? 90 : 10;
    final maxRetries = isProduction ? 3 : 1;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('Testing connection to: $baseUrl (attempt $attempt/$maxRetries)');

        if (attempt > 1 && isProduction) {
          print('Render server may be waking up from sleep, please wait...');
        }

        final response = await http
            .get(Uri.parse('$baseUrl/api/categories'))
            .timeout(Duration(seconds: timeout));

        if (response.statusCode == 200) {
          print('Server connection successful');
          return true;
        } else {
          print('Server returned status: ${response.statusCode}');
          if (attempt < maxRetries) {
            await Future.delayed(Duration(seconds: 5));
            continue;
          }
          return false;
        }
      } catch (e) {
        print('Server connection failed (attempt $attempt): $e');
        if (attempt < maxRetries) {
          print('Retrying in 5 seconds...');
          await Future.delayed(Duration(seconds: 5));
          continue;
        }

        if (isProduction) {
          print(
            'Render free tier server is taking longer than expected to wake up.',
          );
          print('This can happen after 15 minutes of inactivity.');
          print('Please wait a moment and try again.');
        }
        return false;
      }
    }

    return false;
  }

  /// Check if data needs to be updated
  Future<bool> needsUpdate() async {
    try {
      // Check when last update was performed
      final lastUpdateTime = _cacheService.getData(
        _metadataBox,
        'last_update_time',
        defaultValue: null,
      );

      // Never updated before
      if (lastUpdateTime == null) {
        print('No previous update found — update needed');
        return true;
      }

      // Check if enough time has passed
      final lastUpdate = DateTime.parse(lastUpdateTime);
      final timeSinceUpdate = DateTime.now().difference(lastUpdate);

      print('Last update: ${_formatDuration(timeSinceUpdate)} ago');

      if (timeSinceUpdate > _updateCheckInterval) {
        print('Update interval exceeded — update needed');
        return true;
      }

      print('Cache is up to date');
      return false;
    } catch (e) {
      print('Error checking for updates: $e');
      return false; // On error, don't force update
    }
  }

  /// ✨ NEW: Save update metadata after successful preload
  Future<void> saveUpdateMetadata() async {
    try {
      await _cacheService.saveData(
        _metadataBox,
        'last_update_time',
        DateTime.now().toIso8601String(),
      );
      print('Update timestamp saved');
    } catch (e) {
      print('Failed to save update metadata: $e');
    }
  }

  /// Get last update time
  DateTime? getLastUpdateTime() {
    try {
      final timestamp = _cacheService.getData(
        _metadataBox,
        'last_update_time',
        defaultValue: null,
      );
      if (timestamp == null) return null;
      return DateTime.parse(timestamp);
    } catch (e) {
      return null;
    }
  }

  /// Force update check and download
  Future<void> forceUpdate({ProgressCallback? onProgress}) async {
    try {
      onProgress?.call('Checking for updates...', 0.01);

      final isOnline = await testServerConnection();
      if (!isOnline) {
        throw Exception('No internet connection');
      }

      onProgress?.call('Downloading updates...', 0.05);
      await preloadAllData(onProgress: onProgress);

      await saveUpdateMetadata();

      print('Force update completed');
    } catch (e) {
      print('Force update failed: $e');
      rethrow;
    }
  }

  /// Background update - silently updates without blocking UI
  Future<void> updateInBackground() async {
    try {
      final shouldUpdate = await needsUpdate();
      if (!shouldUpdate) return;

      print('Starting background update...');

      final isOnline = await testServerConnection();
      if (!isOnline) {
        print('No internet — skipping background update');
        return;
      }

      await preloadAllData();
      await saveUpdateMetadata();

      print('Background update completed');
    } catch (e) {
      print('Background update failed: $e');
      // Silently fail - continue using cached data
    }
  }

  /// Normalize any image URL to absolute URL
  String normalizeImageUrl(String imageUrl) {
    final baseUrl = getBaseUrl();

    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      return imageUrl;
    }

    if (imageUrl.startsWith('/')) {
      return '$baseUrl$imageUrl';
    }

    return '$baseUrl/$imageUrl';
  }

  /// Download and cache an image locally
  Future<String?> _downloadAndCacheImage(String absoluteUrl) async {
    try {
      if (absoluteUrl.isEmpty) return null;

      final urlHash = md5.convert(utf8.encode(absoluteUrl)).toString();

      final uri = Uri.parse(absoluteUrl);
      final pathSegments = uri.path.split('/');
      final fileName = pathSegments.isNotEmpty ? pathSegments.last : '';
      final extension =
          fileName.contains('.')
              ? fileName.split('.').last.split('?').first
              : 'jpg';

      final cachedFileName = '$urlHash.$extension';
      final directory = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${directory.path}/cached_images');

      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }

      final filePath = '${imagesDir.path}/$cachedFileName';
      final file = File(filePath);

      if (await file.exists()) {
        print('Image already cached: $cachedFileName');
        return filePath;
      }

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
      print('Error caching image $absoluteUrl: $e');
      return null;
    }
  }

  /// Preload all data with optional progress callback
  Future<void> preloadAllData({ProgressCallback? onProgress}) async {
    try {
      onProgress?.call('Connecting to server...', 0.02);
      final isServerOnline = await testServerConnection();
      if (!isServerOnline) {
        throw Exception(
          'Cannot connect to server at ${getBaseUrl()}. Please check your internet connection and try again.',
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

  /// ✨ ENHANCED: Get cache statistics with update info
  Future<Map<String, dynamic>> getCacheStats() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${directory.path}/cached_images');

      if (!await imagesDir.exists()) {
        return {
          'imageCount': 0,
          'totalSize': 0,
          'totalSizeMB': '0.00',
          'lastUpdate': null,
          'lastUpdateAgo': 'Never',
        };
      }

      final files = imagesDir.listSync();
      int totalSize = 0;

      for (var file in files) {
        if (file is File) {
          totalSize += await file.length();
        }
      }

      final lastUpdate = getLastUpdateTime();

      return {
        'imageCount': files.length,
        'totalSize': totalSize,
        'totalSizeMB': (totalSize / (1024 * 1024)).toStringAsFixed(2),
        'lastUpdate': lastUpdate?.toIso8601String(),
        'lastUpdateAgo':
            lastUpdate != null
                ? _formatDuration(DateTime.now().difference(lastUpdate))
                : 'Never',
      };
    } catch (e) {
      print('Error getting cache stats: $e');
      return {
        'imageCount': 0,
        'totalSize': 0,
        'totalSizeMB': '0.00',
        'error': e.toString(),
      };
    }
  }

  /// Format duration in human-readable format
  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays} day${duration.inDays > 1 ? 's' : ''}';
    } else if (duration.inHours > 0) {
      return '${duration.inHours} hour${duration.inHours > 1 ? 's' : ''}';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes} minute${duration.inMinutes > 1 ? 's' : ''}';
    } else {
      return 'Just now';
    }
  }
}
