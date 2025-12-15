import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '/api_config.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:htaa_app/services/cache_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:htaa_app/services/connectivity_service.dart';
import 'package:htaa_app/services/data_preload_service.dart';
import 'package:htaa_app/widgets/search_with_history.dart';

class FixFormScreen extends StatefulWidget {
  const FixFormScreen({super.key});

  @override
  FixFormScreenState createState() => FixFormScreenState();
}

class FixFormScreenState extends State<FixFormScreen> {
  final CacheService _cacheService = CacheService();
  late final DataPreloadService _preloadService;
  final GlobalKey<SearchWithHistoryState> _searchWithHistoryKey =
      GlobalKey<SearchWithHistoryState>();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<dynamic> allForms = [];
  List<dynamic> filteredForms = [];
  String searchQuery = '';
  bool isLoading = true;
  String? errorMessage;
  bool _isOfflineMode = false;
  bool _isRefreshing = false;

  // Top message state
  String? topMessage;
  Color? topMessageColor;

  // Cache configuration
  static const String _cacheBoxName = 'formsBox';
  static const String _formsCacheKey = 'forms';

  // Connectivity
  late final StreamSubscription<ConnectivityResult> _connectivitySubscription;

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
    await fetchFixForms();
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
    _searchFocusNode.dispose();
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

  Future<void> fetchFixForms({bool forceRefresh = false}) async {
    if (!mounted) return;

    // Only show loading spinner on initial load or when no cache exists
    if (allForms.isEmpty) {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
    }

    try {
      // First, try to load from cache (preloaded data)
      final cachedData = _cacheService.getData(
        _cacheBoxName,
        _formsCacheKey,
        defaultValue: null,
        maxAge: const Duration(hours: 24),
      );

      if (cachedData != null && cachedData is List && !forceRefresh) {
        // Load from cache immediately
        setState(() {
          allForms = cachedData;
          filteredForms = cachedData;
          isLoading = false;
        });

        // Then try to update in background if online
        final connectivityResult = await Connectivity().checkConnectivity();
        if (connectivityResult != ConnectivityResult.none) {
          _updateFormsInBackground();
        } else {
          setState(() => _isOfflineMode = true);
        }
      } else {
        // No cache or force refresh - fetch from network
        await _fetchFromNetwork();
      }
    } catch (e) {
      print('Error loading forms: $e');
      await _handleError();
    }
  }

  Future<void> _fetchFromNetwork() async {
    try {
      final response = await http
          .get(
            Uri.parse('${getBaseUrl()}/api/forms'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception('Request timed out.'),
          );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);

        // Save to cache
        await _cacheService.saveData(_cacheBoxName, _formsCacheKey, data);

        setState(() {
          allForms = data;
          filteredForms = data;
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

  Future<void> _updateFormsInBackground({bool showSuccess = false}) async {
    try {
      final response = await http
          .get(
            Uri.parse('${getBaseUrl()}/api/forms'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);

        // Save to cache
        await _cacheService.saveData(_cacheBoxName, _formsCacheKey, data);

        // Update UI if different
        if (mounted && !_areFormsEqual(allForms, data)) {
          setState(() {
            allForms = data;
            _filterForms(searchQuery);
          });
          if (showSuccess) {
            showTopMessage('Forms updated', color: Colors.green);
          }
        }
      }
    } catch (e) {
      print('Background update failed: $e');
      // Silently fail - user already has cached data
    }
  }

  bool _areFormsEqual(List<dynamic> a, List<dynamic> b) {
    if (a.length != b.length) return false;
    return jsonEncode(a) == jsonEncode(b);
  }

  Future<void> _handleError() async {
    // Try to load from cache one more time
    final cachedData = _cacheService.getData(
      _cacheBoxName,
      _formsCacheKey,
      defaultValue: null,
    );

    if (cachedData != null && cachedData is List) {
      setState(() {
        allForms = cachedData;
        filteredForms = cachedData;
        isLoading = false;
        _isOfflineMode = true;
        errorMessage = null;
      });

      showTopMessage(
        'You are offline. Forms cannot be refreshed.',
        color: Colors.orange,
      );
    } else {
      setState(() {
        allForms = [];
        filteredForms = [];
        isLoading = false;
        _isOfflineMode = false;
        errorMessage = 'No data available. Please check your connection.';
      });
    }
  }

  void _filterForms(String query) {
    setState(() {
      searchQuery = query;
      filteredForms =
          query.isEmpty
              ? allForms
              : allForms.where((form) {
                final field = (form['field'] ?? '').toString().toLowerCase();
                final title = (form['title'] ?? '').toString().toLowerCase();
                final linkText =
                    (form['link_text'] ?? '').toString().toLowerCase();
                final searchLower = query.toLowerCase();
                return field.contains(searchLower) ||
                    title.contains(searchLower) ||
                    linkText.contains(searchLower);
              }).toList();
    });
  }

  String _getFormIdentifier(dynamic form) {
    return '${form['field']}_${form['title']}';
  }

  String _getFormDisplayName(dynamic form) {
    return form['title'] ?? form['field'] ?? 'Unknown Form';
  }

  Future<void> _onFormTap(dynamic form) async {
    final formUrl = form['form_url'];
    final linkText = form['link_text'] ?? 'Open Form';
    final formIdentifier = _getFormIdentifier(form);
    final formName = _getFormDisplayName(form);

    // Add to search history
    _searchWithHistoryKey.currentState?.addToHistory(formIdentifier, formName);

    if (formUrl != null && formUrl.toString().isNotEmpty) {
      final uri = Uri.parse(formUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open the link')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Forms List",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (_isOfflineMode) ...[
              const SizedBox(width: 6),
              Icon(Icons.cloud_off, size: 18, color: Colors.orange[700]),
            ],
          ],
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
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
                padding: const EdgeInsets.all(12.0),
                child:
                    isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : errorMessage != null
                        ? _buildErrorView()
                        : Column(
                          children: [
                            // Search bar with history
                            SearchWithHistory(
                              key: _searchWithHistoryKey,
                              hintText: 'Search forms...',
                              historyKey: 'formSearchHistory',
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              onSearch: _filterForms,
                              onHistoryItemTap: (item) {
                                // Find the form and trigger tap
                                final form = allForms.firstWhere(
                                  (f) => _getFormIdentifier(f) == item.id,
                                  orElse: () => null,
                                );

                                if (form != null) {
                                  _onFormTap(form);
                                }
                              },
                            ),
                            const SizedBox(height: 10),
                            // Results count
                            if (searchQuery.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 4,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '${filteredForms.length} result${filteredForms.length != 1 ? 's' : ''} found',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ),
                              ),

                            // Table with RefreshIndicator
                            // Replace the Expanded widget section (around line 340) with this:
                            Expanded(
                              child: RefreshIndicator(
                                displacement: 0,
                                onRefresh: () async {
                                  setState(() => _isRefreshing = true);

                                  // Check if offline before attempting reload
                                  if (_isOfflineMode) {
                                    showTopMessage(
                                      'You are offline. Forms cannot be refreshed.',
                                      color: Colors.orange,
                                    );
                                    setState(() => _isRefreshing = false);
                                    return;
                                  }

                                  await _updateFormsInBackground(
                                    showSuccess: true,
                                  );
                                  setState(() => _isRefreshing = false);
                                },
                                child:
                                    filteredForms.isEmpty
                                        ? ListView(
                                          physics:
                                              const AlwaysScrollableScrollPhysics(),
                                          children: [
                                            SizedBox(
                                              height:
                                                  MediaQuery.of(
                                                    context,
                                                  ).size.height *
                                                  0.6,
                                              child: _buildNoResultsView(),
                                            ),
                                          ],
                                        )
                                        : ListView(
                                          padding: EdgeInsets.only(
                                            top: _isRefreshing ? 60 : 0,
                                            bottom: 16,
                                          ),
                                          physics:
                                              const AlwaysScrollableScrollPhysics(),
                                          children: [
                                            LayoutBuilder(
                                              builder: (context, constraints) {
                                                final availableWidth =
                                                    constraints.maxWidth;
                                                final noWidth =
                                                    availableWidth * 0.10;
                                                final fieldWidth =
                                                    availableWidth * 0.22;
                                                final titleWidth =
                                                    availableWidth * 0.38;
                                                final formWidth =
                                                    availableWidth * 0.30;

                                                return DataTable(
                                                  columnSpacing: 8,
                                                  horizontalMargin: 8,
                                                  dataRowMinHeight: 48,
                                                  dataRowMaxHeight:
                                                      double.infinity,
                                                  border: TableBorder.all(
                                                    color: Colors.grey.shade300,
                                                  ),
                                                  headingRowColor:
                                                      MaterialStateProperty.resolveWith(
                                                        (states) =>
                                                            Colors
                                                                .grey
                                                                .shade200,
                                                      ),
                                                  columns: [
                                                    DataColumn(
                                                      label: SizedBox(
                                                        width: noWidth - 14,
                                                        child: const Text(
                                                          'No',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                          textAlign:
                                                              TextAlign.center,
                                                        ),
                                                      ),
                                                    ),
                                                    DataColumn(
                                                      label: SizedBox(
                                                        width: fieldWidth - 16,
                                                        child: const Text(
                                                          'Field',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    DataColumn(
                                                      label: SizedBox(
                                                        width: titleWidth - 16,
                                                        child: const Text(
                                                          'Form Title',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    DataColumn(
                                                      label: SizedBox(
                                                        width: formWidth - 16,
                                                        child: const Text(
                                                          'Form',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                  rows: List<
                                                    DataRow
                                                  >.generate(filteredForms.length, (
                                                    index,
                                                  ) {
                                                    final form =
                                                        filteredForms[index];
                                                    final linkText =
                                                        form['link_text'] ??
                                                        'Open Form';

                                                    return DataRow(
                                                      color:
                                                          MaterialStateProperty.resolveWith(
                                                            (states) =>
                                                                index.isEven
                                                                    ? Colors
                                                                        .grey
                                                                        .shade50
                                                                    : Colors
                                                                        .white,
                                                          ),
                                                      cells: [
                                                        DataCell(
                                                          Container(
                                                            width: noWidth - 16,
                                                            alignment:
                                                                Alignment
                                                                    .center,
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  vertical: 8,
                                                                ),
                                                            child: Text(
                                                              '${index + 1}',
                                                            ),
                                                          ),
                                                        ),
                                                        DataCell(
                                                          Container(
                                                            width:
                                                                fieldWidth - 16,
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  vertical: 8,
                                                                ),
                                                            child: Text(
                                                              form['field'] ??
                                                                  '-',
                                                              softWrap: true,
                                                              overflow:
                                                                  TextOverflow
                                                                      .visible,
                                                            ),
                                                          ),
                                                        ),
                                                        DataCell(
                                                          Container(
                                                            width:
                                                                titleWidth - 16,
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  vertical: 8,
                                                                ),
                                                            child: Text(
                                                              form['title'] ??
                                                                  '-',
                                                              softWrap: true,
                                                              overflow:
                                                                  TextOverflow
                                                                      .visible,
                                                            ),
                                                          ),
                                                        ),
                                                        DataCell(
                                                          Container(
                                                            width:
                                                                formWidth - 16,
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  vertical: 8,
                                                                ),
                                                            child: InkWell(
                                                              onTap:
                                                                  () =>
                                                                      _onFormTap(
                                                                        form,
                                                                      ),
                                                              child: Text(
                                                                linkText,
                                                                softWrap: true,
                                                                overflow:
                                                                    TextOverflow
                                                                        .visible,
                                                                style: const TextStyle(
                                                                  color:
                                                                      Colors
                                                                          .blue,
                                                                  decoration:
                                                                      TextDecoration
                                                                          .underline,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    );
                                                  }),
                                                );
                                              },
                                            ),
                                          ],
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
    );
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
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: fetchFixForms,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    ),
  );

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
            'There are no forms available.',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
