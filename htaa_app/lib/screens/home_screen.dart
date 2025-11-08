import 'package:flutter/material.dart';
import 'package:htaa_app/screens/bookmark_screen.dart';
import 'package:htaa_app/screens/contact_screen.dart';
import 'package:htaa_app/screens/category_screen.dart';
import 'package:htaa_app/screens/fix_form_screen.dart';
import 'package:htaa_app/services/auth_service.dart';
import 'package:htaa_app/services/api_service.dart';
import 'package:htaa_app/services/cache_service.dart';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:htaa_app/services/connectivity_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  // ===== State variables =====
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();
  final CacheService _cacheService = CacheService();

  List<Map<String, dynamic>> allCategories = [];
  String searchQuery = '';
  bool isLoading = true;
  String? errorMessage;
  bool _isAuthenticating = false;
  bool _isOfflineMode = false;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // Cache configuration
  static const String _cacheBoxName = 'categoriesBox';
  static const String _categoriesCacheKey = 'categories';

  // ===== Connectivity =====
  late final StreamSubscription<ConnectivityResult> _connectivitySubscription;

  // ===== Lifecycle =====
  @override
  void initState() {
    super.initState();
    _initializeAuth();
    fetchCategories();

    // Listen for connectivity changes
    _connectivitySubscription = ConnectivityService().connectivityStream.listen(
      _handleConnectivityChange,
    );
  }

  void _handleConnectivityChange(ConnectivityResult result) {
    if (!mounted) return;

    if (result != ConnectivityResult.none && _isOfflineMode) {
      setState(() => _isOfflineMode = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Back online!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } else if (result == ConnectivityResult.none && !_isOfflineMode) {
      setState(() => _isOfflineMode = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are offline'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initializeAuth() async {
    await _authService.initialize();
    if (mounted) setState(() {});
  }

  // ===== Fetch categories with caching =====
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
        // Show offline mode snackbar
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.cloud_off, color: Colors.white, size: 20),
                  const SizedBox(width: 25),
                  Expanded(
                    child: Text(
                      'Using cached data.\n${_getCacheAgeMessage()}',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.orange[700],
              duration: const Duration(seconds: 3),
              action: SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: fetchCategories,
              ),
            ),
          );
        }
      } else {
        setState(() {
          errorMessage = _getErrorMessage(e);
          isLoading = false;
          _isOfflineMode = false;
        });
      }
    }
  }

  String _getCacheAgeMessage() {
    final age = _cacheService.getCacheAge(_cacheBoxName, _categoriesCacheKey);
    if (age == null) return '';

    if (age.inMinutes < 60) {
      return 'Updated ${age.inMinutes} min ago';
    } else if (age.inHours < 24) {
      return 'Updated ${age.inHours} hrs ago';
    } else {
      return 'Updated ${age.inDays} days ago';
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

  // ===== Authentication =====
  Future<void> _handleGoogleSignIn() async {
    setState(() => _isAuthenticating = true);

    final success = await _authService.signInWithGoogle();

    setState(() => _isAuthenticating = false);

    if (success) {
      if (mounted) {
        setState(() {});

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Welcome, ${_authService.userName}!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sign in cancelled or failed'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _handleSignOut() async {
    await _authService.signOut();
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Signed out successfully'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // ===== Search =====
  void performSearch() {
    FocusScope.of(context).unfocus();
    setState(() {
      searchQuery = _searchController.text.trim();
    });
  }

  // ===== Profile Icon Builder =====
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
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 2),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return _buildInitialsAvatar(userName);
              },
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

  // ===== Build =====
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
        surfaceTintColor: Colors.white,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "HTAA LAB HANDBOOK",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            if (_isOfflineMode) ...[
              const SizedBox(width: 8),
              Icon(Icons.cloud_off, size: 18, color: Colors.orange[700]),
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
                  } else if (value == 'refresh') {
                    await fetchCategories();
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
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
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
                            Icon(Icons.logout, size: 20),
                            SizedBox(width: 12),
                            Text('Sign out'),
                          ],
                        ),
                      ),
                    ]);
                  }

                  // Add refresh option if offline
                  if (_isOfflineMode) {
                    items.addAll([
                      const PopupMenuDivider(),
                      const PopupMenuItem<String>(
                        value: 'refresh',
                        child: Row(
                          children: [
                            Icon(Icons.refresh, size: 20),
                            SizedBox(width: 12),
                            Text('Refresh data'),
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
      body: GestureDetector(
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
                        ElevatedButton.icon(
                          onPressed: fetchCategories,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                  : Column(
                    children: [
                      // Search Bar
                      SizedBox(
                        height: 50,
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          decoration: InputDecoration(
                            hintText: 'Search for categories...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon:
                                searchQuery.isNotEmpty
                                    ? IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        setState(() {
                                          searchQuery = '';
                                          _searchController.clear();
                                        });
                                      },
                                    )
                                    : null,
                            filled: true,
                            fillColor: Colors.grey[100],
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(25.0),
                              borderSide: const BorderSide(
                                color: Colors.grey,
                                width: 1.5,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(25.0),
                              borderSide: const BorderSide(
                                color: Colors.blue,
                                width: 2.0,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12.0,
                              horizontal: 20.0,
                            ),
                          ),
                          onChanged: (query) {
                            setState(() => searchQuery = query);
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
                                  onRefresh: fetchCategories,
                                  child: ListView.builder(
                                    itemCount: filteredCategories.length,
                                    itemBuilder: (context, index) {
                                      final category =
                                          filteredCategories[index];
                                      final categoryName = category['name'];
                                      final categoryId = category['id'];

                                      return Center(
                                        child: LayoutBuilder(
                                          builder: (context, constraints) {
                                            return SizedBox(
                                              width: constraints.maxWidth * 0.6,
                                              child: Card(
                                                color: Colors.white,
                                                elevation: 3,
                                                margin:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 8.0,
                                                    ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: InkWell(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  onTap: () {
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
                                                    alignment: Alignment.center,
                                                    child: Text(
                                                      categoryName,
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w600,
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
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const BookmarkScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(width: 48),
              IconButton(
                iconSize: 28,
                icon: const Icon(Icons.phone),
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
