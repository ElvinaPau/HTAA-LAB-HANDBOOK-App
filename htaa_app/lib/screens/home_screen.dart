import 'package:flutter/material.dart';
import 'package:htaa_app/screens/bookmark_screen.dart';
import 'package:htaa_app/screens/contact_screen.dart';
import 'package:htaa_app/screens/category_screen.dart';
import 'package:htaa_app/screens/fix_form_screen.dart';
import 'package:htaa_app/services/auth_service.dart';
import 'package:htaa_app/services/api_service.dart';
import 'package:htaa_app/services/cache_service.dart';
import 'package:htaa_app/services/data_preload_service.dart';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:htaa_app/services/connectivity_service.dart';
import 'package:htaa_app/widgets/search_with_history.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

// Add WidgetsBindingObserver for lifecycle events
class HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // State variables
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();
  final CacheService _cacheService = CacheService();
  final GlobalKey<SearchWithHistoryState> _searchWithHistoryKey =
      GlobalKey<SearchWithHistoryState>();

  // DataPreloadService for auto-updates
  DataPreloadService? _preloadService;
  bool _isUpdatingInBackground = false;

  List<Map<String, dynamic>> allCategories = [];
  String searchQuery = '';
  bool isLoading = true;
  String? errorMessage;
  bool _isAuthenticating = false;
  bool _isOfflineMode = false;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // Top message state
  String? topMessage;
  Color? topMessageColor;

  // Cache configuration
  static const String _cacheBoxName = 'categoriesBox';
  static const String _categoriesCacheKey = 'categories';

  // Connectivity
  late final StreamSubscription<ConnectivityResult> _connectivitySubscription;

  // Lifecycle
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Add lifecycle observer
    _initializeServices(); // Initialize all services
    fetchCategories();

    // Listen for connectivity changes
    _connectivitySubscription = ConnectivityService().connectivityStream.listen(
      _handleConnectivityChange,
    );
  }

  // Initialize preload service
  Future<void> _initializeServices() async {
    await _initializeAuth();
    _preloadService = await DataPreloadService.create();
  }

  // Handle app lifecycle changes for background updates
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed) {
      // App came to foreground - check for updates silently
      _checkForBackgroundUpdates();
    }
  }

  // Silent background update check
  Future<void> _checkForBackgroundUpdates() async {
    if (_preloadService == null || _isUpdatingInBackground) return;

    try {
      setState(() => _isUpdatingInBackground = true);
      
      final needsUpdate = await _preloadService!.needsUpdate();
      
      if (needsUpdate) {
        print('Background update available - downloading...');
        
        await _preloadService!.updateInBackground();
        
        // Refresh categories after update
        await fetchCategories();
        
        if (mounted) {
          showTopMessage('Data updated', color: Colors.green);
        }
      }
    } catch (e) {
      print('Background update failed: $e');
      // Silently fail - don't interrupt user experience
    } finally {
      if (mounted) {
        setState(() => _isUpdatingInBackground = false);
      }
    }
  }

  // Manual refresh with force update option
  Future<void> _handleManualRefresh() async {
    if (_preloadService == null) {
      await fetchCategories();
      return;
    }

    try {
      showTopMessage('Checking for updates...', color: Colors.blue);
      
      await _preloadService!.forceUpdate(
        onProgress: (message, progress) {
          print('$message (${(progress * 100).toStringAsFixed(0)}%)');
        },
      );

      await fetchCategories();
      
      if (mounted) {
        showTopMessage('Data refreshed', color: Colors.green);
      }
    } catch (e) {
      print('Update failed: $e');
      // Fall back to regular fetch
      await fetchCategories();
    }
  }

  void _handleConnectivityChange(ConnectivityResult result) {
    if (!mounted) return;

    if (result != ConnectivityResult.none && _isOfflineMode) {
      setState(() => _isOfflineMode = false);
      showTopMessage('Back online!', color: Colors.green);
      
      // Check for updates when coming back online
      _checkForBackgroundUpdates();
    } else if (result == ConnectivityResult.none && !_isOfflineMode) {
      setState(() => _isOfflineMode = true);
      showTopMessage('You are offline', color: Colors.red);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Remove observer
    _connectivitySubscription.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initializeAuth() async {
    await _authService.initialize();
    if (mounted) setState(() {});
  }

  // Fetch categories with caching
  Future<void> fetchCategories() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
      _isOfflineMode = false;
    });

    try {
      // Try to fetch from API
      final data = await _apiService.fetchData('categories');

      // Sort by position
      data.sort((a, b) => (a['position'] ?? 0).compareTo(b['position'] ?? 0));

      final categories = [
        ...data.map<Map<String, dynamic>>(
          (item) => {'id': item['id'], 'name': item['name']},
        ),
        {'id': null, 'name': 'FORM'},
      ];

      // Save to cache
      await _cacheService.saveData(
        _cacheBoxName,
        _categoriesCacheKey,
        categories,
      );

      setState(() {
        allCategories = categories;
        isLoading = false;
        _isOfflineMode = false;
      });
    } catch (e) {
      // Try to load from cache
      final cachedData = _cacheService.getData(
        _cacheBoxName,
        _categoriesCacheKey,
        defaultValue: null,
        maxAge: null,
      );

      if (cachedData != null && cachedData is List) {
        setState(() {
          allCategories = List<Map<String, dynamic>>.from(
            cachedData.map((item) => Map<String, dynamic>.from(item)),
          );
          isLoading = false;
          _isOfflineMode = true;
          errorMessage = null;
        });

        // Show top message instead of overlay
        showTopMessage(
          'You are offline. Categories cannot be refreshed.',
          color: Colors.orange,
        );
      } else {
        setState(() {
          errorMessage = _getErrorMessage(e);
          isLoading = false;
          _isOfflineMode = false;
        });
      }
    }
  }

  String _getErrorMessage(dynamic error) {
    final errorStr = error.toString();
    if (errorStr.contains('timeout') || errorStr.contains('Timeout')) {
      return 'Connection timeout. Please check your internet.';
    } else if (errorStr.contains('SocketException') ||
        errorStr.contains('Unable to connect')) {
      return 'No internet connection. Please try again.';
    } else if (errorStr.contains('Server error')) {
      return 'Server error. Please try again later.';
    } else {
      return 'Failed to load categories. Please try again.';
    }
  }

  // Authentication
  Future<void> _handleGoogleSignIn() async {
    setState(() => _isAuthenticating = true);
    final success = await _authService.signInWithGoogle();
    setState(() => _isAuthenticating = false);

    if (success) {
      if (mounted) {
        showTopMessage(
          'Welcome, ${_authService.userName}!',
          color: Colors.green,
        );
      }
    } else {
      if (mounted) {
        showTopMessage('Sign in cancelled or failed', color: Colors.red);
      }
    }
  }

  Future<void> _handleSignOut() async {
    await _authService.signOut();
    setState(() {});
    showTopMessage('Signed out successfully', color: Colors.grey[800]!);
  }

  // Search
  void performSearch() {
    FocusScope.of(context).unfocus();
    setState(() {
      searchQuery = _searchController.text.trim();
    });
  }

  // Top message (non-overlay)
  void showTopMessage(String message, {Color color = Colors.black87}) {
    setState(() {
      topMessage = message;
      topMessageColor = color;
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => topMessage = null);
    });
  }

  // Profile Icon Builder
  Widget _buildProfileIcon() {
    final photoUrl = _authService.userPhotoUrl;
    final userName = _authService.userName;

    if (_authService.isLoggedIn) {
      if (photoUrl != null && photoUrl.isNotEmpty) {
        return CircleAvatar(
          radius: 16,
          backgroundColor: Colors.grey[300],
          child: ClipOval(
            child: Image.network(
              photoUrl,
              width: 32,
              height: 32,
              fit: BoxFit.cover,
              errorBuilder:
                  (context, error, stackTrace) =>
                      _buildInitialsAvatar(userName),
            ),
          ),
        );
      }
      return _buildInitialsAvatar(userName);
    }

    return const Icon(Icons.person, size: 28);
  }

  Widget _buildInitialsAvatar(String name) {
    final initials = _getInitials(name);
    return CircleAvatar(
      radius: 16,
      backgroundColor: Colors.blue[700],
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return 'U';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  // Build
  @override
  Widget build(BuildContext context) {
    final filteredCategories =
        allCategories
            .where(
              (category) => category['name'].toLowerCase().contains(
                searchQuery.toLowerCase(),
              ),
            )
            .toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        shadowColor: Colors.transparent,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "HTAA LAB HANDBOOK",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            // Show both offline and updating indicators
            if (_isOfflineMode) ...[
              const SizedBox(width: 8),
              Icon(Icons.cloud_off, size: 18, color: Colors.orange[700]),
            ],
            if (_isUpdatingInBackground && !_isOfflineMode) ...[
              const SizedBox(width: 8),
              SizedBox(
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
        actions: [
          _isAuthenticating
              ? const Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
              : PopupMenuButton<String>(
                icon: _buildProfileIcon(),
                offset: const Offset(0, 50),
                onSelected: (value) async {
                  if (value == 'login') {
                    await _handleGoogleSignIn();
                  } else if (value == 'logout') {
                    await _handleSignOut();
                  }
                },
                itemBuilder: (context) {
                  final items = <PopupMenuEntry<String>>[];

                  if (!_authService.isLoggedIn) {
                    items.add(
                      const PopupMenuItem<String>(
                        value: 'login',
                        child: Row(
                          children: [
                            Icon(Icons.login, size: 20),
                            SizedBox(width: 12),
                            Text('Sign in with Google'),
                          ],
                        ),
                      ),
                    );
                  } else {
                    items.addAll([
                      PopupMenuItem<String>(
                        enabled: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _authService.userName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.grey[800],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _authService.userEmail,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem<String>(
                        value: 'logout',
                        child: Row(
                          children: [
                            Icon(Icons.logout, size: 20, color: Colors.red),
                            SizedBox(width: 12),
                            Text(
                              'Sign out',
                              style: TextStyle(fontSize: 15, color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ]);
                  }
                  return items;
                },
              ),
          const SizedBox(width: 10),
        ],
      ),
      body: Column(
        children: [
          if (topMessage != null)
            Container(
              width: double.infinity,
              color: topMessageColor,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Text(
                topMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          Expanded(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child:
                    isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : errorMessage != null
                        ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 64,
                                color: Colors.red[300],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 16),
                              ),
                              const SizedBox(height: 24),
                            ],
                          ),
                        )
                        : Column(
                          children: [
                            // Search Bar
                            SizedBox(
                              child: SearchWithHistory(
                                key: _searchWithHistoryKey,
                                hintText: 'Search for categories...',
                                historyKey: 'categorySearchHistory',
                                controller: _searchController,
                                focusNode: _searchFocusNode,
                                onSearch: (query) {
                                  setState(() => searchQuery = query);
                                },
                                onHistoryItemTap: (item) {
                                  final category = allCategories.firstWhere(
                                    (cat) => cat['id'].toString() == item.id,
                                    orElse: () => {},
                                  );

                                  if (category.isNotEmpty) {
                                    final categoryName = category['name'];
                                    final categoryId = category['id'];

                                    if (categoryName == 'FORM') {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder:
                                              (context) =>
                                                  const FixFormScreen(),
                                        ),
                                      );
                                    } else {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder:
                                              (context) => CategoryScreen(
                                                categoryName: categoryName,
                                                categoryId: categoryId,
                                              ),
                                        ),
                                      );
                                    }
                                  }
                                },
                              ),
                            ),
                            const SizedBox(height: 10),
                            // Category List
                            Expanded(
                              child:
                                  filteredCategories.isEmpty
                                      ? const Center(
                                        child: Text('No categories found.'),
                                      )
                                      : RefreshIndicator(
                                        // Use manual refresh with force update
                                        onRefresh: _handleManualRefresh,
                                        child: ListView.builder(
                                          itemCount: filteredCategories.length,
                                          itemBuilder: (context, index) {
                                            final category =
                                                filteredCategories[index];
                                            final categoryName =
                                                category['name'];
                                            final categoryId = category['id'];

                                            return Center(
                                              child: LayoutBuilder(
                                                builder: (
                                                  context,
                                                  constraints,
                                                ) {
                                                  return SizedBox(
                                                    width:
                                                        constraints.maxWidth *
                                                        0.8,
                                                    child: Card(
                                                      color: Colors.white,
                                                      elevation: 3,
                                                      margin:
                                                          const EdgeInsets.symmetric(
                                                            vertical: 8.0,
                                                          ),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              12,
                                                            ),
                                                      ),
                                                      child: InkWell(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              12,
                                                            ),
                                                        onTap: () {
                                                          _searchWithHistoryKey
                                                              .currentState
                                                              ?.addToHistory(
                                                                categoryId
                                                                        ?.toString() ??
                                                                    categoryName,
                                                                categoryName,
                                                              );

                                                          if (categoryName ==
                                                              'FORM') {
                                                            Navigator.push(
                                                              context,
                                                              MaterialPageRoute(
                                                                builder:
                                                                    (context) =>
                                                                        const FixFormScreen(),
                                                              ),
                                                            );
                                                          } else {
                                                            Navigator.push(
                                                              context,
                                                              MaterialPageRoute(
                                                                builder:
                                                                    (
                                                                      context,
                                                                    ) => CategoryScreen(
                                                                      categoryName:
                                                                          categoryName,
                                                                      categoryId:
                                                                          categoryId,
                                                                    ),
                                                              ),
                                                            );
                                                          }
                                                        },
                                                        child: Container(
                                                          height: 80,
                                                          alignment:
                                                              Alignment.center,
                                                          child: Text(
                                                            categoryName,
                                                            textAlign:
                                                                TextAlign
                                                                    .center,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 16,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                            ),
                          ],
                        ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        height: 60,
        color: Colors.white,
        shape: const CircularNotchedRectangle(),
        notchMargin: 6,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                iconSize: 28,
                icon: const Icon(Icons.bookmark),
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const BookmarkScreen(),
                    ),
                  );

                  if (result == true) {
                    await _initializeAuth();
                    setState(() {});
                  }
                },
              ),
              const SizedBox(width: 48),
              IconButton(
                iconSize: 28,
                icon: const Icon(Icons.feedback),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ContactScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: SizedBox(
        width: 60,
        height: 60,
        child: FloatingActionButton(
          onPressed:
              () => FocusScope.of(context).requestFocus(_searchFocusNode),
          tooltip: 'Search',
          backgroundColor: Theme.of(context).primaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
          ),
          child: const Icon(Icons.search, color: Colors.white, size: 28),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}