import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '/api_config.dart';
import 'test_info_screen.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:htaa_app/services/cache_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:htaa_app/services/connectivity_service.dart';
import 'package:htaa_app/services/data_preload_service.dart';
import 'package:htaa_app/widgets/search_with_history.dart';

class CategoryScreen extends StatefulWidget {
  final String categoryName;
  final int? categoryId;

  const CategoryScreen({
    super.key,
    required this.categoryName,
    this.categoryId,
  });

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  final CacheService _cacheService = CacheService();
  late final DataPreloadService _preloadService;
  final GlobalKey<SearchWithHistoryState> _searchWithHistoryKey =
      GlobalKey<SearchWithHistoryState>();

  List<Map<String, dynamic>> tests = [];
  List<Map<String, dynamic>> filteredTests = [];
  bool isLoading = true;
  String? errorMessage;
  String searchQuery = '';
  bool _isOfflineMode = false;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Top message state
  String? topMessage;
  Color? topMessageColor;

  // Cache configuration
  static const String _cacheBoxName = 'testsBox';
  String get _testsCacheKey =>
      'tests_${widget.categoryId ?? widget.categoryName}';

  // Connectivity
  late final StreamSubscription<ConnectivityResult> _connectivitySubscription;

  // Alphabet for quick scroll
  final List<String> alphabet = List.generate(
    26,
    (i) => String.fromCharCode(65 + i),
  );

  // Keys for dynamic scroll
  final Map<int, GlobalKey> _itemKeys = {};

  @override
  void initState() {
    super.initState();
    _initPreloadService();

    _connectivitySubscription = ConnectivityService().connectivityStream.listen(
      _handleConnectivityChange,
    );
  }

  Future<void> _initPreloadService() async {
    _preloadService = await DataPreloadService.create();
    await _fetchTests();
  }

  void _handleConnectivityChange(ConnectivityResult result) {
    if (!mounted) return;

    if (result != ConnectivityResult.none && _isOfflineMode) {
      setState(() => _isOfflineMode = false);
      showTopMessage('Back online!', color: Colors.green);
      // Trigger background update when back online
      _preloadService.updateInBackground();
    } else if (result == ConnectivityResult.none && !_isOfflineMode) {
      setState(() => _isOfflineMode = true);
      showTopMessage('You are offline', color: Colors.red);
    }
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void showTopMessage(String message, {Color color = Colors.blue}) {
    setState(() {
      topMessage = message;
      topMessageColor = color;
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => topMessage = null);
    });
  }

  String _buildApiUrl() {
    final baseUrl = getBaseUrl();
    if (widget.categoryId != null) {
      return '$baseUrl/api/tests?category_id=${widget.categoryId}';
    } else {
      return '$baseUrl/api/tests?category=${Uri.encodeComponent(widget.categoryName)}';
    }
  }

  Future<void> _fetchTests({bool forceRefresh = false}) async {
    if (!mounted) return;

    // Only show loading spinner on initial load or when no cache exists
    if (tests.isEmpty) {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
    }

    try {
      // First, try to load from cache (preloaded data)
      final cachedData = _cacheService.getData(
        _cacheBoxName,
        _testsCacheKey,
        defaultValue: null,
        maxAge: const Duration(hours: 24),
      );

      if (cachedData != null && cachedData is List && !forceRefresh) {
        // Load from cache immediately
        final mappedData =
            cachedData
                .map<Map<String, dynamic>>(
                  (item) => Map<String, dynamic>.from(item),
                )
                .where((test) => test['status'] != 'deleted')
                .toList();

        setState(() {
          tests = mappedData;
          filteredTests = mappedData;
          isLoading = false;
        });

        // Then try to update in background if online
        final connectivityResult = await Connectivity().checkConnectivity();
        if (connectivityResult != ConnectivityResult.none) {
          _updateTestsInBackground();
        } else {
          setState(() => _isOfflineMode = true);
        }
      } else {
        // No cache or force refresh - fetch from network
        await _fetchFromNetwork();
      }
    } catch (e) {
      print('Error loading tests: $e');
      await _handleError();
    }
  }

  Future<void> _fetchFromNetwork() async {
    try {
      final response = await http
          .get(
            Uri.parse(_buildApiUrl()),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception('Request timed out.'),
          );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);

        await _cacheService.saveData(_cacheBoxName, _testsCacheKey, data);

        final mappedData =
            data
                .map<Map<String, dynamic>>(
                  (item) => Map<String, dynamic>.from(item),
                )
                .where((test) => test['status'] != 'deleted')
                .toList();

        setState(() {
          tests = mappedData;
          filteredTests = mappedData;
          isLoading = false;
          _isOfflineMode = false;
        });
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      await _handleError();
    }
  }

  Future<void> _updateTestsInBackground({bool showSuccess = false}) async {
    try {
      final response = await http
          .get(
            Uri.parse(_buildApiUrl()),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);

        await _cacheService.saveData(_cacheBoxName, _testsCacheKey, data);

        final mappedData =
            data
                .map<Map<String, dynamic>>(
                  (item) => Map<String, dynamic>.from(item),
                )
                .where((test) => test['status'] != 'deleted')
                .toList();

        // Update UI if different
        if (mounted && !_areTestsEqual(tests, mappedData)) {
          setState(() {
            tests = mappedData;
            // Reapply search filter
            _filterTests(searchQuery);
          });
          if (showSuccess) {
            showTopMessage('Tests updated', color: Colors.green);
          }
        }
      }
    } catch (e) {
      print('Background update failed: $e');
      // Silently fail - user already has cached data
    }
  }

  bool _areTestsEqual(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) {
    if (a.length != b.length) return false;
    return jsonEncode(a) == jsonEncode(b);
  }

  Future<void> _handleError() async {
    // Try to load from cache one more time
    final cachedData = _cacheService.getData(
      _cacheBoxName,
      _testsCacheKey,
      defaultValue: null,
    );

    if (cachedData != null && cachedData is List) {
      final mappedData =
          cachedData
              .map<Map<String, dynamic>>(
                (item) => Map<String, dynamic>.from(item),
              )
              .where((test) => test['status'] != 'deleted')
              .toList();

      setState(() {
        tests = mappedData;
        filteredTests = mappedData;
        isLoading = false;
        _isOfflineMode = true;
        errorMessage = null;
      });

      showTopMessage(
        'You are offline. Tests cannot be refreshed.',
        color: Colors.orange,
      );
    } else {
      setState(() {
        tests = [];
        filteredTests = [];
        isLoading = false;
        _isOfflineMode = false;
        errorMessage = 'No data available. Please check your connection.';
      });
    }
  }

  void _filterTests(String query) {
    setState(() {
      searchQuery = query;
      filteredTests =
          query.isEmpty
              ? tests
              : tests.where((test) {
                final testName = _getTestName(test).toLowerCase();
                return testName.contains(query.toLowerCase());
              }).toList();
    });
  }

  String _getTestName(Map<String, dynamic> test) {
    return test['test_name'] ?? test['name'] ?? 'Unnamed Test';
  }

  Future<void> _onTestTap(Map<String, dynamic> test) async {
    final testId = test['id'];
    final testName = _getTestName(test);

    // Add to search history
    if (testId != null) {
      _searchWithHistoryKey.currentState?.addToHistory(
        testId.toString(),
        testName,
      );
    }

    final testData =
        Map<String, dynamic>.from(test)
          ..['category_name'] = widget.categoryName
          ..['category_id'] = widget.categoryId;

    if (_isOfflineMode || testId == null) {
      await _navigateToTestInfo(testData);
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final response = await http
          .get(
            Uri.parse('${getBaseUrl()}/api/tests/$testId?includeinfos=true'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      Navigator.of(context).pop();

      if (response.statusCode == 200) {
        final fullData =
            Map<String, dynamic>.from(json.decode(response.body))
              ..['category_name'] = widget.categoryName
              ..['category_id'] = widget.categoryId;
        await _navigateToTestInfo(fullData);
      } else {
        await _navigateToTestInfo(testData);
      }
    } catch (_) {
      Navigator.of(context).pop();
      await _navigateToTestInfo(testData);
    }
  }

  Future<void> _navigateToTestInfo(Map<String, dynamic> testData) async {
    if (!mounted) return;
    final updatedBookmark = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => TestInfoScreen(tests: testData)),
    );
    if (updatedBookmark != null) {
      setState(() {
        final index = tests.indexWhere((t) => t['id'] == testData['id']);
        if (index != -1) tests[index]['isBookmarked'] = updatedBookmark;
      });
    }
  }

  void _scrollToLetter(String letter) {
    final index = filteredTests.indexWhere(
      (test) => _getTestName(test).toUpperCase().startsWith(letter),
    );

    if (index != -1) {
      final key = _itemKeys[index];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
      showTopMessage('Jumped to "$letter"', color: Colors.blue);
    } else {
      showTopMessage('No tests starting with "$letter"', color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Text(
                  widget.categoryName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 20,
                  ),
                ),
              ),
            ),
            if (_isOfflineMode) ...[
              const SizedBox(width: 6),
              Icon(Icons.cloud_off, size: 18, color: Colors.orange[700]),
            ],
          ],
        ),
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
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (errorMessage != null) return _buildErrorView();
    if (tests.isEmpty) return _buildEmptyView();
    return _buildTestsListWithSearch();
  }

  Widget _buildErrorView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
          const SizedBox(height: 16),
          Text(
            errorMessage!,
            style: const TextStyle(color: Colors.red, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );

  Widget _buildEmptyView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No tests found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'There are no tests available in this category.',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );

  Widget _buildTestsListWithSearch() {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Stack(
        children: [
          Column(
            children: [
              _buildSearchBar(),
              if (searchQuery.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${filteredTests.length} result${filteredTests.length != 1 ? 's' : ''} found',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ),
                ),
              Expanded(
                child:
                    filteredTests.isEmpty
                        ? _buildNoResultsView()
                        : RefreshIndicator(
                          onRefresh:
                              () => _updateTestsInBackground(showSuccess: true),
                          child: ListView.builder(
                            controller: _scrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(10, 8, 40, 8),
                            itemCount: filteredTests.length,
                            itemBuilder: (context, index) {
                              final test = filteredTests[index];
                              _itemKeys[index] = GlobalKey();
                              return Card(
                                key: _itemKeys[index],
                                color: Colors.white,
                                elevation: 2,
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: InkWell(
                                  onTap: () => _onTestTap(test),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 16,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: AutoSizeText(
                                            _getTestName(test),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 16,
                                            ),
                                            maxLines: 2,
                                            minFontSize: 12,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Icon(
                                          Icons.arrow_forward_ios,
                                          size: 16,
                                          color: Colors.grey,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
              ),
            ],
          ),
          if (searchQuery.isEmpty && filteredTests.isNotEmpty)
            _buildAlphabetSidebar(),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: SearchWithHistory(
        key: _searchWithHistoryKey,
        hintText: 'Search tests...',
        historyKey:
            'testSearchHistory_${widget.categoryId ?? widget.categoryName}',
        controller: _searchController,
        focusNode: FocusNode(),
        onSearch: _filterTests,
        onHistoryItemTap: (item) {
          final test = tests.firstWhere(
            (t) => t['id'].toString() == item.id,
            orElse: () => {},
          );

          if (test.isNotEmpty) {
            _onTestTap(test);
          }
        },
      ),
    );
  }

  Widget _buildAlphabetSidebar() {
    return Positioned(
      right: 4,
      top: 80,
      bottom: 16,
      child: Container(
        width: 24,
        decoration: BoxDecoration(
          color: Colors.grey[200]?.withOpacity(0.8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListView.builder(
          itemCount: alphabet.length,
          itemBuilder: (context, index) {
            return GestureDetector(
              onTap: () => _scrollToLetter(alphabet[index]),
              child: Container(
                height: 20,
                alignment: Alignment.center,
                child: Text(
                  alphabet[index],
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue[700],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildNoResultsView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No results found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try different keywords',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
