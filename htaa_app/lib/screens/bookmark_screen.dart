import 'package:flutter/material.dart';
import 'package:htaa_app/services/bookmark_service.dart';
import 'package:htaa_app/services/cache_service.dart';
import 'package:htaa_app/screens/test_info_screen.dart';

class BookmarkScreen extends StatefulWidget {
  const BookmarkScreen({super.key});

  @override
  State<BookmarkScreen> createState() => _BookmarkScreenState();
}

class _BookmarkScreenState extends State<BookmarkScreen> {
  final BookmarkService _bookmarkService = BookmarkService();
  final CacheService _cacheService = CacheService();
  List<Map<String, dynamic>> _bookmarks = [];
  bool _isLoading = true;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    setState(() => _isLoading = true);
    final bookmarks = await _bookmarkService.getBookmarks();
    setState(() {
      _bookmarks = bookmarks;
      _isLoading = false;
    });
  }

  /// Merge bookmark data with cached test details (includes local image paths)
  Map<String, dynamic> _getMergedTestData(Map<String, dynamic> bookmark) {
    final testId = bookmark['test_id'];

    // Try to get cached test details (which has local image paths)
    var cachedData = _cacheService.getData(
      'testDetailsBox',
      'test_details_$testId',
      defaultValue: null,
      maxAge: null,
    );

    // If we have cached data, merge it with bookmark data
    if (cachedData != null && cachedData is Map) {
      final merged = Map<String, dynamic>.from(cachedData);

      // Fix any relative image paths in the cached data
      _fixImagePathsInData(merged);

      // Preserve bookmark-specific fields
      merged['category_name'] = bookmark['category_name'];
      merged['category_id'] = bookmark['category_id'];

      print('✅ Using cached data with fixed image paths for test $testId');
      return merged;
    }

    // Fallback to bookmark data
    print('⚠️ No cache found, using bookmark data for test $testId');
    _fixImagePathsInData(bookmark);
    return bookmark;
  }

  /// Fix relative image paths by converting them to network URLs
  void _fixImagePathsInData(Map<String, dynamic> data) {
    final infos = data['infos'];
    if (infos == null || infos is! List) return;

    for (var info in infos) {
      if (info is Map && info.containsKey('extraData')) {
        final extraData = info['extraData'];
        if (extraData is Map && extraData.containsKey('image')) {
          dynamic imageData = extraData['image'];
          String? imagePath;

          // Extract current image path
          if (imageData is String) {
            imagePath = imageData;
          } else if (imageData is Map && imageData['url'] != null) {
            imagePath = imageData['url'].toString();
          }

          // Check if it's a relative path that needs fixing
          if (imagePath != null &&
              imagePath.startsWith('/') &&
              !imagePath.contains('cached_images') &&
              !imagePath.startsWith('/var/') &&
              !imagePath.startsWith('/data/') &&
              !imagePath.startsWith('/private/')) {
            // It's a relative path like /imgUploads/..., needs network URL
            final networkUrl =
                'http://10.167.177.92:5001$imagePath'; // Use your IP
            print(
              '🔧 Fixed relative path in bookmark: $imagePath → $networkUrl',
            );

            if (imageData is String) {
              extraData['image'] = networkUrl;
            } else if (imageData is Map) {
              extraData['image']['url'] = networkUrl;
            }
          }
        }
      }
    }
  }

  Future<void> _removeBookmark(int testId, String testName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Remove Bookmark'),
            content: Text('Remove "$testName" from bookmarks?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Remove',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      await _bookmarkService.removeBookmark(testId);
      _hasChanges = true;
      _loadBookmarks();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bookmark removed'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _clearAllBookmarks() async {
    if (_bookmarks.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Clear All Bookmarks'),
            content: Text('Remove all ${_bookmarks.length} bookmarks?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Clear All',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      await _bookmarkService.clearAllBookmarks();
      _hasChanges = true;
      _loadBookmarks();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All bookmarks cleared'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {
        if (didPop && _hasChanges) {
          // Changes are tracked via _hasChanges flag
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Bookmarked Tests',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => Navigator.pop(context, _hasChanges),
          ),
          actions: [
            if (_bookmarks.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_sweep),
                tooltip: 'Clear all bookmarks',
                onPressed: _clearAllBookmarks,
              ),
          ],
        ),
        body:
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _bookmarks.isEmpty
                ? _buildEmptyState()
                : _buildBookmarkList(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Align(
        alignment: Alignment(0, -0.2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_border, size: 40, color: Colors.grey[400]),
            const SizedBox(height: 6),
            Text(
              'No Bookmarks Yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Bookmark tests to access them quickly',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookmarkList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _bookmarks.length,
      itemBuilder: (context, index) {
        final bookmark = _bookmarks[index];
        final testName = bookmark['test_name'] ?? 'Unknown Test';
        final categoryName = bookmark['category_name'] ?? 'Unknown Category';
        final testId = bookmark['test_id'];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              // Get merged data (cached data with local images + bookmark info)
              final mergedData = _getMergedTestData(bookmark);

              // Navigate to TestInfoScreen with merged data
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TestInfoScreen(tests: mergedData),
                ),
              );
              // Refresh bookmarks when returning
              _loadBookmarks();
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          testName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          categoryName,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.bookmark, color: Colors.blue),
                    onPressed: () => _removeBookmark(testId, testName),
                    tooltip: 'Remove bookmark',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
