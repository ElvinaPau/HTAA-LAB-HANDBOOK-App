import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '/api_config.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:htaa_app/services/cache_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:htaa_app/services/connectivity_service.dart';

class FixFormScreen extends StatefulWidget {
  const FixFormScreen({super.key});

  @override
  FixFormScreenState createState() => FixFormScreenState();
}

class FixFormScreenState extends State<FixFormScreen> {
  final CacheService _cacheService = CacheService();

  List<dynamic> allForms = [];
  String searchQuery = '';
  bool isLoading = true;
  String? errorMessage;
  bool _isOfflineMode = false;

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
    fetchFixForms();

    _connectivitySubscription = ConnectivityService().connectivityStream.listen(
      _handleConnectivityChange,
    );
  }

  void _handleConnectivityChange(ConnectivityResult result) {
    if (!mounted) return;

    if (result != ConnectivityResult.none && _isOfflineMode) {
      setState(() => _isOfflineMode = false);
      showTopMessage('Back online!', color: Colors.green);
    } else if (result == ConnectivityResult.none && !_isOfflineMode) {
      setState(() => _isOfflineMode = true);
      showTopMessage('You are offline', color: Colors.red);
    }
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
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

  Future<void> fetchFixForms() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
      _isOfflineMode = false;
    });

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
          isLoading = false;
          _isOfflineMode = false;
        });
      } else {
        await _loadFromCache();
      }
    } catch (_) {
      await _loadFromCache();
    }
  }

  Future<void> _loadFromCache() async {
    final cachedData = _cacheService.getData(
      _cacheBoxName,
      _formsCacheKey,
      defaultValue: null,
      maxAge: const Duration(hours: 24),
    );

    if (cachedData != null && cachedData is List) {
      setState(() {
        allForms = cachedData;
        isLoading = false;
        _isOfflineMode = true;
        errorMessage = null;
      });

      showTopMessage(
        'You are offline. Data cannot be refreshed.',
        color: Colors.red,
      );
    } else {
      setState(() {
        allForms = [];
        isLoading = false;
        _isOfflineMode = false;
        errorMessage = 'No data available. Please check your connection.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredForms =
        allForms.where((form) {
          final field = (form['field'] ?? '').toString().toLowerCase();
          final title = (form['title'] ?? '').toString().toLowerCase();
          final linkText = (form['link_text'] ?? '').toString().toLowerCase();
          final query = searchQuery.toLowerCase();
          return field.contains(query) ||
              title.contains(query) ||
              linkText.contains(query);
        }).toList();

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
              Icon(Icons.cloud_off, size: 18, color: Colors.orange),
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
                            // Search bar
                            TextField(
                              decoration: InputDecoration(
                                hintText: 'Search form...',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon:
                                    searchQuery.isNotEmpty
                                        ? IconButton(
                                          icon: const Icon(Icons.clear),
                                          onPressed: () {
                                            setState(() => searchQuery = '');
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
                            const SizedBox(height: 10),
                            // Table
                            Expanded(
                              child: RefreshIndicator(
                                onRefresh: fetchFixForms,
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final availableWidth = constraints.maxWidth;

                                    final noWidth = availableWidth * 0.10;
                                    final fieldWidth = availableWidth * 0.22;
                                    final titleWidth = availableWidth * 0.38;
                                    final formWidth = availableWidth * 0.30;

                                    return SingleChildScrollView(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      child: DataTable(
                                        columnSpacing: 8,
                                        horizontalMargin: 8,
                                        dataRowMinHeight: 48,
                                        dataRowMaxHeight: double.infinity,
                                        border: TableBorder.all(
                                          color: Colors.grey.shade300,
                                        ),
                                        headingRowColor:
                                            MaterialStateProperty.resolveWith(
                                              (states) => Colors.grey.shade200,
                                            ),
                                        columns: [
                                          DataColumn(
                                            label: SizedBox(
                                              width: noWidth - 16,
                                              child: const Text(
                                                'No',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          ),
                                          DataColumn(
                                            label: SizedBox(
                                              width: fieldWidth - 16,
                                              child: const Text(
                                                'Field',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
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
                                                  fontWeight: FontWeight.bold,
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
                                                  fontWeight: FontWeight.bold,
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
                                          final form = filteredForms[index];
                                          final formUrl = form['form_url'];
                                          final linkText =
                                              form['link_text'] ?? 'Open Form';

                                          return DataRow(
                                            color:
                                                MaterialStateProperty.resolveWith(
                                                  (states) =>
                                                      index.isEven
                                                          ? Colors.grey.shade50
                                                          : Colors.white,
                                                ),
                                            cells: [
                                              DataCell(
                                                Container(
                                                  width: noWidth - 16,
                                                  alignment: Alignment.center,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 8,
                                                      ),
                                                  child: Text('${index + 1}'),
                                                ),
                                              ),
                                              DataCell(
                                                Container(
                                                  width: fieldWidth - 16,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 8,
                                                      ),
                                                  child: Text(
                                                    form['field'] ?? '-',
                                                    softWrap: true,
                                                    overflow:
                                                        TextOverflow.visible,
                                                  ),
                                                ),
                                              ),
                                              DataCell(
                                                Container(
                                                  width: titleWidth - 16,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 8,
                                                      ),
                                                  child: Text(
                                                    form['title'] ?? '-',
                                                    softWrap: true,
                                                    overflow:
                                                        TextOverflow.visible,
                                                  ),
                                                ),
                                              ),
                                              DataCell(
                                                Container(
                                                  width: formWidth - 16,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 8,
                                                      ),
                                                  child: InkWell(
                                                    onTap: () async {
                                                      if (formUrl != null &&
                                                          formUrl
                                                              .toString()
                                                              .isNotEmpty) {
                                                        final uri = Uri.parse(
                                                          formUrl,
                                                        );
                                                        if (await canLaunchUrl(
                                                          uri,
                                                        )) {
                                                          await launchUrl(
                                                            uri,
                                                            mode:
                                                                LaunchMode
                                                                    .externalApplication,
                                                          );
                                                        } else {
                                                          if (context.mounted) {
                                                            ScaffoldMessenger.of(
                                                              context,
                                                            ).showSnackBar(
                                                              const SnackBar(
                                                                content: Text(
                                                                  'Could not open the link',
                                                                ),
                                                              ),
                                                            );
                                                          }
                                                        }
                                                      }
                                                    },
                                                    child: Text(
                                                      linkText,
                                                      softWrap: true,
                                                      overflow:
                                                          TextOverflow.visible,
                                                      style: const TextStyle(
                                                        color: Colors.blue,
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
}
