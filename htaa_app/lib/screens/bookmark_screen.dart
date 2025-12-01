import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:htaa_app/services/bookmark_service.dart';
import 'package:htaa_app/services/cache_service.dart';
import 'package:htaa_app/services/auth_service.dart';
import 'package:htaa_app/screens/test_info_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:htaa_app/services/connectivity_service.dart';
import 'dart:async';

class BookmarkScreen extends StatefulWidget {
  const BookmarkScreen({super.key});

  @override
  State<BookmarkScreen> createState() => _BookmarkScreenState();
}

class _BookmarkScreenState extends State<BookmarkScreen> {
  final BookmarkService _bookmarkService = BookmarkService();
  final CacheService _cacheService = CacheService();
  final AuthService _authService = AuthService();

  List<Map<String, dynamic>> _bookmarks = [];
  bool _isLoading = true;
  bool _hasChanges = false;
  bool _showSignInBanner = true;
  bool _isOfflineMode = false;
  bool _isSyncing = false;

  // Pending sync info
  int _pendingAdditions = 0;
  int _pendingDeletions = 0;

  // Top message state
  String? topMessage;
  Color? topMessageColor;

  // Connectivity
  late final StreamSubscription<ConnectivityResult> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _checkInitialConnectivity();
    _loadBookmarks();
    _loadPendingSyncInfo();

    // Listen for connectivity changes
    _connectivitySubscription = ConnectivityService().connectivityStream.listen(
      _handleConnectivityChange,
    );
  }

  Future<void> _checkInitialConnectivity() async {
    final isOnline = await ConnectivityService().isOnline();
    if (mounted) {
      setState(() => _isOfflineMode = !isOnline);
    }
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }

  void _handleConnectivityChange(ConnectivityResult result) async {
    if (!mounted) return;

    final wasOffline = _isOfflineMode;
    final isNowOffline = result == ConnectivityResult.none;

    // Update offline status
    if (isNowOffline != wasOffline) {
      setState(() => _isOfflineMode = isNowOffline);
    }

    // Coming back online
    if (!isNowOffline && wasOffline) {
      _showTopMessage('Back online! Syncing...', color: Colors.green);

      // Auto-sync when coming back online
      if (_authService.isLoggedIn) {
        await _syncPendingActions();
      } else {
        // Even if not signed in, refresh bookmarks to show we're online
        await _loadBookmarks();
      }
    }
    // Going offline
    else if (isNowOffline && !wasOffline) {
      _showTopMessage('You are offline', color: Colors.red);
    }
  }

  Future<void> _loadBookmarks() async {
    setState(() => _isLoading = true);

    try {
      // Check connectivity first
      final isOnline = await ConnectivityService().isOnline();

      final bookmarks = await _bookmarkService.getBookmarks();

      if (mounted) {
        setState(() {
          _bookmarks = bookmarks;
          _isLoading = false;
          // Don't override _isOfflineMode if we're actually offline
          // Only set to false if we successfully loaded AND we're online
          if (isOnline) {
            _isOfflineMode = false;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        // Check if error is due to being offline
        final isOnline = await ConnectivityService().isOnline();
        setState(() {
          _isLoading = false;
          _isOfflineMode = !isOnline;
        });

        if (!isOnline) {
          _showTopMessage(
            'Offline - showing cached bookmarks',
            color: Colors.orange,
          );
        } else {
          _showTopMessage('Failed to load bookmarks', color: Colors.red);
        }
      }
    }

    await _loadPendingSyncInfo();
  }

  Future<void> _loadPendingSyncInfo() async {
    if (!_authService.isLoggedIn) return;

    final syncInfo = await _bookmarkService.getPendingSyncInfo();
    if (mounted) {
      setState(() {
        _pendingAdditions = syncInfo['additions'] ?? 0;
        _pendingDeletions = syncInfo['deletions'] ?? 0;
      });
    }
  }

  Future<void> _syncPendingActions() async {
    if (_isSyncing) return;

    setState(() => _isSyncing = true);

    try {
      // Store count before sync
      final totalBeforeSync = _pendingAdditions + _pendingDeletions;

      await _bookmarkService.syncPendingActions();

      // Reload bookmarks from cloud after successful sync
      await _loadBookmarks();

      if (mounted) {
        if (totalBeforeSync > 0) {
          _showTopMessage(
            'Synced $totalBeforeSync change${totalBeforeSync == 1 ? '' : 's'}',
            color: Colors.green,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _showTopMessage('Sync failed', color: Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
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
            final networkUrl = 'http://10.167.177.92:5001$imagePath';
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
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder:
          (context) => CupertinoAlertDialog(
            title: const Text(
              'Remove Bookmark',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            content: Text('Remove "$testName" from bookmarks?'),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
                isDefaultAction: true, // bold blue text like iOS
              ),
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove'),
                isDestructiveAction: true, // red text
              ),
            ],
          ),
    );
    if (confirmed == true) {
      final success = await _bookmarkService.removeBookmark(testId);

      if (success) {
        _hasChanges = true;

        // Update local list without fetching from server
        if (mounted) {
          setState(() {
            _bookmarks.removeWhere((b) => b['test_id'] == testId);
          });
        }

        if (mounted) {
          if (_isOfflineMode && _authService.isLoggedIn) {
          } else {
            _showTopMessage('Bookmark removed', color: Colors.grey[800]!);
          }
        }

        // Reload pending sync info to update the banner
        await _loadPendingSyncInfo();
      }
    }
  }

  Future<void> _clearAllBookmarks() async {
    if (_bookmarks.isEmpty) return;

    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder:
          (context) => CupertinoAlertDialog(
            title: const Text(
              'Clear All Bookmarks',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            content: Text('Remove all ${_bookmarks.length} bookmark(s)?'),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
                isDefaultAction: true, // blue text like iOS
              ),
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Clear All'),
                isDestructiveAction: true, // red text
              ),
            ],
          ),
    );

    if (confirmed == true) {
      await _bookmarkService.clearAllBookmarks();
      _hasChanges = true;

      // Update local list immediately without fetching from server
      if (mounted) {
        setState(() {
          _bookmarks.clear();
        });
      }

      if (mounted) {
        if (_isOfflineMode && _authService.isLoggedIn) {
        } else {
          _showTopMessage('All bookmarks cleared', color: Colors.grey[800]!);
        }
      }

      // Reload pending sync info to update the banner
      await _loadPendingSyncInfo();
    }
  }

  Future<void> _handleSignIn() async {
    setState(() => _showTopMessage('Signing in...', color: Colors.green));

    final success = await _authService.signInWithGoogle();

    if (!mounted) return;

    if (success) {
      await _loadBookmarks();
      setState(() {});
      _showTopMessage(
        'Welcome, ${_authService.userName}!',
        color: Colors.green,
      );
      setState(() => _showSignInBanner = false);
    } else {
      _showTopMessage('Sign in cancelled or failed', color: Colors.red);
    }
  }

  void _showTopMessage(String message, {Color color = Colors.black87}) {
    setState(() {
      topMessage = message;
      topMessageColor = color;
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => topMessage = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isSignedIn = _authService.isLoggedIn;
    final hasPendingSync = _pendingAdditions > 0 || _pendingDeletions > 0;

    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {
        if (didPop && _hasChanges) {
          // Changes are tracked via _hasChanges flag
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Bookmarked Tests',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              if (_isOfflineMode) ...[
                const SizedBox(width: 8),
                Icon(Icons.cloud_off, size: 18, color: Colors.orange[700]),
              ],
              if (_isSyncing) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                ),
              ],
            ],
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
        body: Column(
          children: [
            // Top message banner
            if (topMessage != null)
              Container(
                width: double.infinity,
                color: topMessageColor,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                child: Text(
                  topMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),

            // Pending sync banner
            if (isSignedIn && hasPendingSync && !_isSyncing)
              _buildPendingSyncBanner(),

            // Sign-in notice banner
            if (!isSignedIn && _showSignInBanner && _bookmarks.isNotEmpty)
              _buildSignInBanner(),

            // Main content with pull-to-refresh
            Expanded(
              child:
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _bookmarks.isEmpty
                      ? _buildEmptyState(isSignedIn)
                      : RefreshIndicator(
                        onRefresh: _loadBookmarks,
                        child: _buildBookmarkList(),
                      ),
            ),
          ],
        ),
      ),
    );
  }

  /// Pending sync info banner
  Widget _buildPendingSyncBanner() {
    final totalPending = _pendingAdditions + _pendingDeletions;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: Colors.orange),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          // Only allow tapping when online and not already syncing
          onTap: !_isOfflineMode && !_isSyncing ? _syncPendingActions : null,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Icon(
                  _isOfflineMode ? Icons.cloud_off : Icons.cloud_queue,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isOfflineMode
                        ? '$totalPending change${totalPending == 1 ? '' : 's'} will sync when online'
                        : '$totalPending change${totalPending == 1 ? '' : 's'} pending sync',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (_isSyncing)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else if (!_isOfflineMode)
                  Row(
                    children: [
                      Text(
                        'Tap to sync',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.sync, color: Colors.white, size: 16),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Beautiful gradient banner encouraging sign-in
  Widget _buildSignInBanner() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[700]!, Colors.blue[500]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _handleSignIn,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.cloud_sync,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sync Across Devices?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Sign in to access your bookmarks on all devices',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Empty state with optional sign-in tip
  Widget _buildEmptyState(bool isSignedIn) {
    return RefreshIndicator(
      onRefresh: _loadBookmarks,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bookmark_border,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
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
                    textAlign: TextAlign.center,
                  ),
                  if (!isSignedIn) ...[
                    const SizedBox(height: 24),
                    InkWell(
                      onTap: _handleSignIn,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.blue[700],
                              size: 32,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tip: Sign in to sync bookmarks',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.blue[900],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Access your bookmarks on all your devices',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.blue[700],
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Tap to sign in',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue[900],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.arrow_forward,
                                  size: 14,
                                  color: Colors.blue[600],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
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
              final mergedData = _getMergedTestData(bookmark);
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TestInfoScreen(tests: mergedData),
                ),
              );
              _loadBookmarks();
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.science_outlined,
                      color: Theme.of(context).primaryColor,
                      size: 24,
                    ),
                  ),
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
                    icon: Icon(
                      Icons.bookmark,
                      color: Theme.of(context).primaryColor,
                    ),
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
