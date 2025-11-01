import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class BookmarkService {
  static const String _bookmarksKey = 'bookmarked_tests';
  
  // Singleton pattern
  static final BookmarkService _instance = BookmarkService._internal();
  factory BookmarkService() => _instance;
  BookmarkService._internal();

  SharedPreferences? _prefs;

  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Get all bookmarked tests
  Future<List<Map<String, dynamic>>> getBookmarks() async {
    await initialize();
    final String? bookmarksJson = _prefs?.getString(_bookmarksKey);
    if (bookmarksJson == null) return [];
    
    try {
      final List<dynamic> decoded = json.decode(bookmarksJson);
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  /// Check if a test is bookmarked
  Future<bool> isBookmarked(int testId) async {
    final bookmarks = await getBookmarks();
    return bookmarks.any((bookmark) => bookmark['test_id'] == testId);
  }

  /// Add a bookmark
  Future<bool> addBookmark(Map<String, dynamic> testData) async {
    await initialize();
    
    final bookmarks = await getBookmarks();
    
    // Check if already bookmarked
    final testId = testData['test_id'] ?? testData['id'];
    if (bookmarks.any((b) => b['test_id'] == testId)) {
      return false; // Already bookmarked
    }

    // Add bookmark with timestamp
    final bookmark = {
      'test_id': testId,
      'test_name': testData['test_name'] ?? testData['name'],
      'category_name': testData['category_name'],
      'category_id': testData['category_id'],
      'bookmarked_at': DateTime.now().toIso8601String(),
      'infos': testData['infos'], // Store the full test info data
    };

    bookmarks.add(bookmark);
    
    final String encoded = json.encode(bookmarks);
    return await _prefs?.setString(_bookmarksKey, encoded) ?? false;
  }

  /// Remove a bookmark
  Future<bool> removeBookmark(int testId) async {
    await initialize();
    
    final bookmarks = await getBookmarks();
    bookmarks.removeWhere((bookmark) => bookmark['test_id'] == testId);
    
    final String encoded = json.encode(bookmarks);
    return await _prefs?.setString(_bookmarksKey, encoded) ?? false;
  }

  /// Toggle bookmark (add if not exists, remove if exists)
  Future<bool> toggleBookmark(Map<String, dynamic> testData) async {
    final testId = testData['test_id'] ?? testData['id'];
    final isCurrentlyBookmarked = await isBookmarked(testId);
    
    if (isCurrentlyBookmarked) {
      await removeBookmark(testId);
      return false; // Now not bookmarked
    } else {
      await addBookmark(testData);
      return true; // Now bookmarked
    }
  }

  /// Clear all bookmarks
  Future<bool> clearAllBookmarks() async {
    await initialize();
    return await _prefs?.remove(_bookmarksKey) ?? false;
  }

  /// Get bookmark count
  Future<int> getBookmarkCount() async {
    final bookmarks = await getBookmarks();
    return bookmarks.length;
  }
}