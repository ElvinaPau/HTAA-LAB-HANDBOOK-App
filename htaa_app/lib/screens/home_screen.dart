import 'package:flutter/material.dart';
import 'package:htaa_app/screens/bookmark_screen.dart';
import 'package:htaa_app/screens/contact_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '/api_config.dart';
import 'package:htaa_app/screens/category_screen.dart';
import 'package:htaa_app/screens/fix_form_screen.dart';
import 'package:htaa_app/services/auth_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  // ===== State variables =====
  final AuthService _authService = AuthService();

  List<Map<String, dynamic>> allCategories = [];
  String searchQuery = '';
  bool isLoading = true;
  String? errorMessage;
  bool _isAuthenticating = false;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // ===== Lifecycle =====
  @override
  void initState() {
    super.initState();
    _initializeAuth();
    fetchCategories();
  }

  Future<void> _initializeAuth() async {
    await _authService.initialize();
    if (mounted) setState(() {});
  }

  // ===== Fetch categories =====
  Future<void> fetchCategories() async {
    final url = '${getBaseUrl()}/api/categories';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        data.sort((a, b) => (a['position'] ?? 0).compareTo(b['position'] ?? 0));

        setState(() {
          allCategories = [
            ...data.map<Map<String, dynamic>>(
              (item) => {'id': item['id'], 'name': item['name']},
            ),
            {'id': null, 'name': 'FORM'},
          ];
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = 'Failed to load categories';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error: $e';
        isLoading = false;
      });
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

  // Helper to build avatar with initials
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

  // Get initials from name
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
        title: const Text(
          "HTAA LAB HANDBOOK",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
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
                  if (!_authService.isLoggedIn) {
                    return [
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
                    ];
                  } else {
                    return [
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
                    ];
                  }
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
                  ? Center(child: Text(errorMessage!))
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
                                : ListView.builder(
                                  itemCount: filteredCategories.length,
                                  itemBuilder: (context, index) {
                                    final category = filteredCategories[index];
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
                                                    textAlign: TextAlign.center,
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
                    ],
                  ),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        height: 60, // Reduced height from default (~80) to 60
        color: Colors.white,
        shape: const CircularNotchedRectangle(),
        notchMargin: 6, // Reduced notch margin from 8 to 6
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16.0,
          ), // Add horizontal padding for better spacing
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                iconSize: 28, // Reduced from 35 to 28
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
              const SizedBox(width: 48), // Space for the FAB
              IconButton(
                iconSize: 28, // Reduced from 35 to 28
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
        width: 60, // Reduced from 70 to 60
        height: 60, // Reduced from 70 to 60
        child: FloatingActionButton(
          onPressed:
              () => FocusScope.of(context).requestFocus(_searchFocusNode),
          tooltip: 'Search',
          backgroundColor: Theme.of(context).primaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
          ),
          child: const Icon(
            Icons.search,
            color: Colors.white,
            size: 28,
          ), // Reduced from 35 to 28
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}
