import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '/api_config.dart';
import 'test_info_screen.dart';
import 'package:auto_size_text/auto_size_text.dart';

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
  List<dynamic> tests = [];
  List<dynamic> filteredTests = [];
  bool isLoading = true;
  String? errorMessage;
  String searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Alphabet for quick scroll
  final List<String> alphabet = [
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
  ];

  @override
  void initState() {
    super.initState();
    _fetchTests();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _buildApiUrl() {
    final baseUrl = getBaseUrl();
    if (widget.categoryId != null) {
      return '$baseUrl/api/tests?category_id=${widget.categoryId}';
    } else {
      return '$baseUrl/api/tests?category=${Uri.encodeComponent(widget.categoryName)}';
    }
  }

  Future<void> _fetchTests() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final response = await http
          .get(
            Uri.parse(_buildApiUrl()),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception(
                'Request timed out. Please check your connection.',
              );
            },
          );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);

        setState(() {
          tests = data;
          filteredTests = data;
          isLoading = false;
          errorMessage = null;
        });
      } else if (response.statusCode == 404) {
        setState(() {
          errorMessage = 'Category not found';
          isLoading = false;
          tests = [];
          filteredTests = [];
        });
      } else {
        setState(() {
          errorMessage =
              'Failed to load tests (Status: ${response.statusCode})';
          isLoading = false;
          tests = [];
          filteredTests = [];
        });
      }
    } on http.ClientException catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'Network error: Unable to connect to server';
        isLoading = false;
        tests = [];
        filteredTests = [];
      });
      debugPrint('ClientException: $e');
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'Invalid response format from server';
        isLoading = false;
        tests = [];
        filteredTests = [];
      });
      debugPrint('FormatException: $e');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'Error: ${e.toString()}';
        isLoading = false;
        tests = [];
        filteredTests = [];
      });
      debugPrint('Error fetching tests: $e');
    }
  }

  void _filterTests(String query) {
    setState(() {
      searchQuery = query;
      if (query.isEmpty) {
        filteredTests = tests;
      } else {
        filteredTests =
            tests.where((test) {
              final testName = _getTestName(test).toLowerCase();
              return testName.contains(query.toLowerCase());
            }).toList();
      }
    });
  }

  void _scrollToLetter(String letter) {
    final index = filteredTests.indexWhere((test) {
      final testName = _getTestName(test);
      return testName.toUpperCase().startsWith(letter);
    });

    if (index != -1) {
      final position = (index * 88.0) + 16.0;
      _scrollController.animateTo(
        position,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Jumped to "$letter"'),
          duration: const Duration(milliseconds: 800),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 80, left: 16, right: 60),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No tests starting with "$letter"'),
          duration: const Duration(milliseconds: 800),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 80, left: 16, right: 60),
        ),
      );
    }
  }

  String _getTestName(Map<String, dynamic> test) {
    return test['test_name'] ?? test['name'] ?? 'Unnamed Test';
  }

  Future<void> _onTestTap(Map<String, dynamic> test) async {
  final testId = test['id'];

  if (testId == null) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid test ID')));
    }
    return;
  }

  if (mounted) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
  }

  try {
    final response = await http
        .get(
          Uri.parse('${getBaseUrl()}/api/tests/$testId?includeinfos=true'),
          headers: {'Content-Type': 'application/json'},
        )
        .timeout(const Duration(seconds: 30));

    if (!mounted) return;
    Navigator.of(context).pop(); // Close loading dialog

    if (response.statusCode == 200) {
      final Map<String, dynamic> fullTestData = json.decode(response.body);

      // Add category info for bookmarking
      fullTestData['category_name'] = widget.categoryName;
      fullTestData['category_id'] = widget.categoryId;

      if (mounted) {
        // Await the returned bookmark status
        final updatedBookmark = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => TestInfoScreen(tests: fullTestData),
          ),
        );

        // Update the test in the list if bookmark changed
        if (updatedBookmark != null) {
          setState(() {
            test['isBookmarked'] = updatedBookmark;
          });
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to load test details (${response.statusCode})',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  } catch (e) {
    if (!mounted) return;
    Navigator.of(context).pop(); // Close loading dialog

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error loading test: ${e.toString()}'),
        backgroundColor: Colors.red,
      ),
    );
    debugPrint('Error fetching test details: $e');
  }
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.categoryName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null) {
      return _buildErrorView();
    }

    if (tests.isEmpty) {
      return _buildEmptyView();
    }

    return _buildTestsListWithSearch();
  }

  Widget _buildErrorView() {
    return Center(
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
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchTests,
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
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
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
            ElevatedButton.icon(
              onPressed: _fetchTests,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestsListWithSearch() {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search tests...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon:
                        searchQuery.isNotEmpty
                            ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _filterTests('');
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
                  onChanged: _filterTests,
                ),
              ),
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
                          onRefresh: _fetchTests,
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            itemCount: filteredTests.length,
                            itemBuilder: (context, index) {
                              final test = filteredTests[index];

                              return Card(
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
            Positioned(
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
            ),
        ],
      ),
    );
  }

  Widget _buildNoResultsView() {
    return Center(
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
}
