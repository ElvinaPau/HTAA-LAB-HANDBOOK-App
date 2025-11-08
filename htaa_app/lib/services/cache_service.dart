import 'package:hive_flutter/hive_flutter.dart';

/// Handles offline storage with cache expiration support
class CacheService {
  /// Save data to Hive with timestamp for expiration tracking
  Future<void> saveData(String boxName, String key, dynamic data) async {
    try {
      final box = Hive.box(boxName);
      await box.put(key, {
        'data': data,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Failed to save data to cache: $e');
    }
  }

  /// Retrieve data from Hive with optional expiration check
  ///
  /// [boxName]: The name of the Hive box
  /// [key]: The key to retrieve
  /// [defaultValue]: Value to return if key doesn't exist or is expired
  /// [maxAge]: Maximum age of cached data. If null, no expiration check
  dynamic getData(
    String boxName,
    String key, {
    dynamic defaultValue,
    Duration? maxAge,
  }) {
    try {
      final box = Hive.box(boxName);
      final cached = box.get(key);

      if (cached == null) return defaultValue;

      if (cached is! Map) return cached;

      if (maxAge != null && cached['timestamp'] != null) {
        try {
          final timestamp = DateTime.parse(cached['timestamp']);
          final age = DateTime.now().difference(timestamp);

          if (age > maxAge) {
            return defaultValue;
          }
        } catch (e) {
          return cached['data'] ?? defaultValue;
        }
      }

      return cached['data'] ?? defaultValue;
    } catch (e) {
      return defaultValue;
    }
  }

  /// Delete a specific key from cache
  Future<void> deleteData(String boxName, String key) async {
    try {
      final box = Hive.box(boxName);
      await box.delete(key);
    } catch (e) {
      throw Exception('Failed to delete data from cache: $e');
    }
  }

  /// Clear all data from a box
  Future<void> clearBox(String boxName) async {
    try {
      final box = Hive.box(boxName);
      await box.clear();
    } catch (e) {
      throw Exception('Failed to clear cache box: $e');
    }
  }

  /// Check if a key exists in cache and is not expired
  bool isValid(String boxName, String key, {Duration? maxAge}) {
    try {
      final box = Hive.box(boxName);
      final cached = box.get(key);

      if (cached == null) return false;
      if (cached is! Map) return true; // Old format, consider valid

      if (maxAge != null && cached['timestamp'] != null) {
        try {
          final timestamp = DateTime.parse(cached['timestamp']);
          final age = DateTime.now().difference(timestamp);
          return age <= maxAge;
        } catch (e) {
          return false;
        }
      }

      return cached['data'] != null;
    } catch (e) {
      return false;
    }
  }

  /// Get the age of cached data
  Duration? getCacheAge(String boxName, String key) {
    try {
      final box = Hive.box(boxName);
      final cached = box.get(key);

      if (cached == null || cached is! Map || cached['timestamp'] == null) {
        return null;
      }

      final timestamp = DateTime.parse(cached['timestamp']);
      return DateTime.now().difference(timestamp);
    } catch (e) {
      return null;
    }
  }
}
