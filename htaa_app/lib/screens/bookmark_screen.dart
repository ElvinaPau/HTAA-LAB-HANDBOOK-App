import 'package:flutter/material.dart';
import 'package:htaa_app/services/bookmark_service.dart';
import 'package:htaa_app/screens/test_info_screen.dart';

class BookmarkScreen extends StatefulWidget {
  const BookmarkScreen({super.key});

  @override
  State<BookmarkScreen> createState() => _BookmarkScreenState();
}

class _BookmarkScreenState extends State<BookmarkScreen> {
  final BookmarkService _bookmarkService = BookmarkService();
  List<Map<String, dynamic>> _bookmarks = [];
  bool _isLoading = true;
  bool _hasChanges = false; // Track if any bookmarks were modified

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
      _hasChanges = true; // Mark that changes were made
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
      _hasChanges = true; // Mark that changes were made
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
      // Use PopScope to intercept back button
      canPop: true,
      onPopInvoked: (didPop) {
        if (didPop && _hasChanges) {
          // Return true to indicate changes were made
          // This won't work with onPopInvoked, need to handle differently
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
            onPressed:
                () =>
                    Navigator.pop(context, _hasChanges), // Return change status
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
              // Navigate to TestInfoScreen
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TestInfoScreen(tests: bookmark),
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
