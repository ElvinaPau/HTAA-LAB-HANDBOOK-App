import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../api_config.dart';
import 'auth_service.dart';
import 'connectivity_service.dart';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class BookmarkService {
  static const String _boxName = 'bookmarksBox';
  static const String _bookmarksKey = 'bookmarked_tests';
  static const String _pendingAdditionsBox = 'pendingAdditionsBox';
  static const String _pendingDeletionsBox = 'pendingDeletionsBox';
  static const String _lastSyncKey = 'last_sync_timestamp';

  static final BookmarkService _instance = BookmarkService._internal();
  factory BookmarkService() => _instance;
  BookmarkService._internal() {
    _initConnectivityListener();
  }

  Box? _box;
  Box? _pendingAdditions;
  Box? _pendingDeletions;
  final AuthService _authService = AuthService();
  late final StreamSubscription<ConnectivityResult> _connectivitySubscription;

  Future<void> initialize() async {
    if (_box == null || !_box!.isOpen) _box = await Hive.openBox(_boxName);
    if (_pendingAdditions == null || !_pendingAdditions!.isOpen) {
      _pendingAdditions = await Hive.openBox(_pendingAdditionsBox);
    }
    if (_pendingDeletions == null || !_pendingDeletions!.isOpen) {
      _pendingDeletions = await Hive.openBox(_pendingDeletionsBox);
    }
  }

  void _initConnectivityListener() {
    _connectivitySubscription = ConnectivityService().connectivityStream.listen(
      (result) {
        if (result != ConnectivityResult.none) {
          print('Connection restored, syncing pending actions...');
          syncPendingActions();
        }
      },
    );
  }

  Future<void> dispose() async {
    await _connectivitySubscription.cancel();
  }

  /// GET BOOKMARKS
  Future<List<Map<String, dynamic>>> getBookmarks() async {
    await initialize();
    if (_authService.isLoggedIn) {
      return await _getCloudBookmarks();
    } else {
      return await _getLocalBookmarks();
    }
  }

  Future<List<Map<String, dynamic>>> _getLocalBookmarks() async {
    try {
      final dynamic bookmarksData = _box?.get(_bookmarksKey);
      if (bookmarksData == null) return [];
      if (bookmarksData is List) {
        return bookmarksData.map((item) {
          if (item is Map) return Map<String, dynamic>.from(item);
          return <String, dynamic>{};
        }).toList();
      }
      return [];
    } catch (e) {
      print('Error reading local bookmarks: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _getCloudBookmarks() async {
    try {
      final googleId = _authService.googleId;
      if (googleId == null) {
        print('No Google ID, returning local bookmarks');
        return await _getLocalBookmarks();
      }

      // Check if online
      if (!await ConnectivityService().isOnline()) {
        print('Offline, returning local bookmarks');
        return await _getLocalBookmarks();
      }

      final url = '${getBaseUrl()}/api/bookmarks/user/$googleId';
      final response = await http
          .get(Uri.parse(url))
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException('Failed to fetch bookmarks');
            },
          );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final bookmarks =
            data.map((item) => Map<String, dynamic>.from(item)).toList();

        // Cache cloud bookmarks locally
        await _box?.put(_bookmarksKey, bookmarks);
        await _box?.put(_lastSyncKey, DateTime.now().toIso8601String());

        print('Cloud bookmarks synced: ${bookmarks.length} items');
        return bookmarks;
      } else {
        print('Failed to fetch cloud bookmarks: ${response.statusCode}');
        return await _getLocalBookmarks();
      }
    } catch (e) {
      print('Error fetching cloud bookmarks: $e');
      return await _getLocalBookmarks();
    }
  }

  /// ADD BOOKMARK
  Future<bool> addBookmark(Map<String, dynamic> testData) async {
    await initialize();

    final testId = testData['test_id'] ?? testData['id'];
    final testName = testData['test_name'] ?? testData['name'];
    final categoryName = testData['category_name'];
    final categoryId = testData['category_id'];

    // Save locally first (always works)
    final addedLocally = await _addLocalBookmark(testData);
    if (!addedLocally) {
      print('Failed to add bookmark locally');
      return false;
    }

    print('Bookmark added locally: $testName');

    // If signed in, try to sync to cloud or queue for later
    if (_authService.isLoggedIn) {
      final isOnline = await ConnectivityService().isOnline();

      if (isOnline) {
        // Try to add to cloud immediately
        final success = await _addCloudBookmark(
          testId,
          testName,
          categoryName,
          categoryId,
        );

        if (success) {
          print('Bookmark synced to cloud: $testName');
          // Remove from pending if it was there
          await _pendingAdditions?.delete(testId);
        } else {
          print('Failed to sync to cloud, queuing for later: $testName');
          await _pendingAdditions?.put(testId, testData);
        }
      } else {
        // Offline - queue for later sync
        print('Offline - queuing bookmark for sync: $testName');
        await _pendingAdditions?.put(testId, testData);
      }
    }

    return true;
  }

  Future<bool> _addLocalBookmark(Map<String, dynamic> testData) async {
    final bookmarks = await _getLocalBookmarks();
    final testId = testData['test_id'] ?? testData['id'];

    // Check if already bookmarked
    if (bookmarks.any((b) => b['test_id'] == testId)) {
      print('Bookmark already exists locally: $testId');
      return false;
    }

    final bookmark = {
      'test_id': testId,
      'test_name': testData['test_name'] ?? testData['name'],
      'category_name': testData['category_name'],
      'category_id': testData['category_id'],
      'bookmarked_at': DateTime.now().toIso8601String(),
    };
    bookmarks.add(bookmark);

    try {
      await _box?.put(_bookmarksKey, bookmarks);
      return true;
    } catch (e) {
      print('Error saving local bookmark: $e');
      return false;
    }
  }

  Future<bool> _addCloudBookmark(
    int testId,
    String testName,
    String? categoryName,
    int? categoryId,
  ) async {
    try {
      final googleId = _authService.googleId;
      if (googleId == null) {
        print('No Google ID for cloud sync');
        return false;
      }

      final url = '${getBaseUrl()}/api/bookmarks';
      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'google_id': googleId,
              'test_id': testId,
              'test_name': testName,
              'category_name': categoryName,
              'category_id': categoryId,
            }),
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException('Cloud sync timeout');
            },
          );

      if (response.statusCode == 201) {
        return true;
      } else if (response.statusCode == 409) {
        print('Bookmark already exists in cloud: $testId');
        return true; // Already exists, consider it a success
      } else {
        print('Failed to add cloud bookmark: ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error adding cloud bookmark: $e');
      return false;
    }
  }

  /// REMOVE BOOKMARK
  Future<bool> removeBookmark(int testId) async {
    await initialize();

    // Remove locally first
    final removedLocally = await _removeLocalBookmark(testId);
    if (!removedLocally) {
      print('Bookmark not found locally: $testId');
      return false;
    }

    print('Bookmark removed locally: $testId');

    // If signed in, try to sync deletion to cloud or queue for later
    if (_authService.isLoggedIn) {
      final isOnline = await ConnectivityService().isOnline();

      if (isOnline) {
        // Try to remove from cloud immediately
        final success = await _removeCloudBookmark(testId);

        if (success) {
          print('Bookmark deletion synced to cloud: $testId');
          // Remove from pending if it was there
          await _pendingDeletions?.delete(testId);
          // Also remove from pending additions if it was there
          await _pendingAdditions?.delete(testId);
        } else {
          print('Failed to sync deletion to cloud, queuing: $testId');
          await _pendingDeletions?.put(testId, true);
        }
      } else {
        // Offline - queue for later sync
        print('Offline - queuing deletion for sync: $testId');
        await _pendingDeletions?.put(testId, true);
        // Remove from pending additions if user added then removed offline
        await _pendingAdditions?.delete(testId);
      }
    }

    return true;
  }

  Future<bool> _removeLocalBookmark(int testId) async {
    final bookmarks = await _getLocalBookmarks();
    final initialLength = bookmarks.length;

    bookmarks.removeWhere((bookmark) => bookmark['test_id'] == testId);

    if (bookmarks.length == initialLength) {
      return false; // Bookmark wasn't found
    }

    try {
      await _box?.put(_bookmarksKey, bookmarks);
      return true;
    } catch (e) {
      print('Error removing local bookmark: $e');
      return false;
    }
  }

  Future<bool> _removeCloudBookmark(int testId) async {
    try {
      final googleId = _authService.googleId;
      if (googleId == null) return false;

      final url = '${getBaseUrl()}/api/bookmarks/$googleId/$testId';
      final response = await http
          .delete(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      // Success: deleted, already deleted, or never existed
      return response.statusCode == 200 ||
          response.statusCode == 204 ||
          response.statusCode == 404;
    } catch (e) {
      print('Error removing cloud bookmark: $e');
      return false;
    }
  }

  /// TOGGLE BOOKMARK
  Future<bool> toggleBookmark(Map<String, dynamic> testData) async {
    final testId = testData['test_id'] ?? testData['id'];
    final bookmarked = await isBookmarked(testId);

    if (bookmarked) {
      await removeBookmark(testId);
      return false;
    } else {
      await addBookmark(testData);
      return true;
    }
  }

  Future<bool> isBookmarked(int testId) async {
    final bookmarks = await getBookmarks();
    return bookmarks.any((b) => b['test_id'] == testId);
  }

  /// CLEAR ALL
  Future<bool> clearAllBookmarks() async {
    await initialize();

    // Get all current bookmarks IDs BEFORE clearing
    final currentBookmarks = await getBookmarks();
    final allIds = currentBookmarks.map((b) => b['test_id'] as int).toList();

    // Clear local storage immediately
    await _box?.delete(_bookmarksKey);

    // Clear pending additions (no need to sync additions that were cleared)
    await _pendingAdditions?.clear();

    print('Local bookmarks cleared');

    // If signed in, handle cloud sync
    if (_authService.isLoggedIn) {
      final googleId = _authService.googleId;

      if (googleId != null) {
        final isOnline = await ConnectivityService().isOnline();

        if (isOnline && allIds.isNotEmpty) {
          try {
            // Use sync endpoint to handle batch deletions
            final url = '${getBaseUrl()}/api/bookmarks/sync';
            final response = await http
                .post(
                  Uri.parse(url),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    "google_id": googleId,
                    "additions": [],
                    "deletions": allIds,
                  }),
                )
                .timeout(const Duration(seconds: 10));

            if (response.statusCode == 200 || response.statusCode == 404) {
              final data = json.decode(response.body);
              final deletedCount = data['deletedCount'] ?? 0;
              print('Cloud bookmarks cleared ($deletedCount items)');
              await _getCloudBookmarks();
              return true;
            } else {
              // Queue deletions if sync fails
              for (var id in allIds) {
                await _pendingDeletions?.put(id, true);
              }
              print(
                'Cloud sync failed (${response.statusCode}), queued ${allIds.length} deletions for later',
              );
            }
          } catch (e) {
            // Offline or network error - queue for later sync
            for (var id in allIds) {
              await _pendingDeletions?.put(id, true);
            }
            print(
              'Error during cloud sync: $e. Queued ${allIds.length} deletions for later',
            );
          }
        } else if (allIds.isNotEmpty) {
          // Offline - queue deletions
          for (var id in allIds) {
            await _pendingDeletions?.put(id, true);
          }
          print('Offline - queued ${allIds.length} deletions for later sync');
        }
      }
    }

    return true;
  }

  /// SYNC PENDING ACTIONS
  Future<void> syncPendingActions() async {
    if (!_authService.isLoggedIn) {
      print('Not signed in, skipping sync');
      return;
    }

    if (!await ConnectivityService().isOnline()) {
      print('Offline, cannot sync');
      return;
    }

    await initialize();

    print('Starting sync of pending actions...');

    int addedCount = 0;
    int deletedCount = 0;
    int failedCount = 0;

    // Sync deletions first (in case user deleted something they added offline)
    final deletions = _pendingDeletions?.toMap() ?? {};
    print('Syncing ${deletions.length} pending deletions...');

    for (var entry in deletions.entries) {
      try {
        final testId = entry.key as int;
        final success = await _removeCloudBookmark(testId);

        if (success) {
          await _pendingDeletions?.delete(entry.key);
          deletedCount++;
          print('  Synced deletion: $testId');
        } else {
          failedCount++;
          print('  Failed to sync deletion: $testId');
        }
      } catch (e) {
        failedCount++;
        print('  Error syncing deletion: $e');
      }
    }

    // Sync additions
    final additions = _pendingAdditions?.toMap() ?? {};
    print('Syncing ${additions.length} pending additions...');

    for (var entry in additions.entries) {
      try {
        final testData = Map<String, dynamic>.from(entry.value);

        // Extract testId - handle both 'test_id' and 'id' fields, and from key
        final testId =
            testData['test_id'] as int? ??
            testData['id'] as int? ??
            (entry.key is int ? entry.key as int : null);

        if (testId == null) {
          print('  Skipping addition: missing test_id in data: $testData');
          await _pendingAdditions?.delete(entry.key);
          failedCount++;
          continue;
        }

        final testName =
            testData['test_name'] as String? ??
            testData['name'] as String? ??
            'Unknown Test';

        final success = await _addCloudBookmark(
          testId,
          testName,
          testData['category_name'] as String?,
          testData['category_id'] as int?,
        );

        if (success) {
          await _pendingAdditions?.delete(entry.key);
          addedCount++;
          print('  Synced addition: $testName (ID: $testId)');
        } else {
          failedCount++;
          print('  Failed to sync addition: $testName (ID: $testId)');
        }
      } catch (e) {
        failedCount++;
        print('  Error syncing addition: $e');
        print('  Entry key: ${entry.key}, Entry value: ${entry.value}');
      }
    }

    // Refresh bookmarks from cloud after sync
    if (addedCount > 0 || deletedCount > 0) {
      await _getCloudBookmarks();
    }

    print(
      'Sync complete: $addedCount added, $deletedCount deleted, $failedCount failed',
    );
  }

  /// UTILITY METHODS

  Future<int> getBookmarkCount() async {
    final bookmarks = await getBookmarks();
    return bookmarks.length;
  }

  Future<int> getPendingActionsCount() async {
    await initialize();
    final additionsCount = _pendingAdditions?.length ?? 0;
    final deletionsCount = _pendingDeletions?.length ?? 0;
    return additionsCount + deletionsCount;
  }

  Future<Map<String, int>> getPendingSyncInfo() async {
    await initialize();
    return {
      'additions': _pendingAdditions?.length ?? 0,
      'deletions': _pendingDeletions?.length ?? 0,
    };
  }

  Future<String?> getLastSyncTime() async {
    await initialize();
    return _box?.get(_lastSyncKey);
  }

  /// Force sync - useful for manual sync triggers
  Future<bool> forceSyncNow() async {
    if (!_authService.isLoggedIn) {
      print('Cannot force sync: not signed in');
      return false;
    }

    if (!await ConnectivityService().isOnline()) {
      print('Cannot force sync: offline');
      return false;
    }

    await syncPendingActions();
    return true;
  }
}
