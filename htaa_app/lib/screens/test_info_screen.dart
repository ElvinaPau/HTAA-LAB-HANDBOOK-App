import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:htaa_app/main.dart';
import 'package:htaa_app/screens/bookmark_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '/api_config.dart';
import 'package:htaa_app/services/bookmark_service.dart';
import 'package:htaa_app/services/cache_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:htaa_app/services/connectivity_service.dart';

class TestInfoScreen extends StatefulWidget {
  final Map<String, dynamic> tests;
  const TestInfoScreen({super.key, required this.tests});

  @override
  State<TestInfoScreen> createState() => _TestInfoScreenState();
}

class _TestInfoScreenState extends State<TestInfoScreen> with RouteAware {
  final BookmarkService _bookmarkService = BookmarkService();
  final CacheService _cacheService = CacheService();
  bool _isBookmarked = false;
  bool _isOfflineMode = false;
  Map<String, dynamic>? _cachedTestData;

  // Cache configuration
  static const String _cacheBoxName = 'testDetailsBox';
  String get _testDetailsCacheKey {
    final testId = widget.tests['id'] ?? widget.tests['test_id'];
    return 'test_details_$testId';
  }

  // Connectivity
  late final StreamSubscription<ConnectivityResult> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _checkBookmarkStatus();
    _initializeTestData();

    // Listen for connectivity changes
    _connectivitySubscription = ConnectivityService().connectivityStream.listen(
      _handleConnectivityChange,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route changes
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    routeObserver.unsubscribe(this);
    super.dispose();
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

  // Called when the current route has been popped back to (i.e., screen is visible again)
  @override
  void didPopNext() {
    _checkBookmarkStatus(); // refresh bookmark status
  }

  Future<void> _checkBookmarkStatus() async {
    final testId = widget.tests['test_id'] ?? widget.tests['id'];
    if (testId != null) {
      final isBookmarked = await _bookmarkService.isBookmarked(testId);
      if (mounted) setState(() => _isBookmarked = isBookmarked);
    }
  }

  Future<void> _initializeTestData() async {
    final infos = widget.tests['infos'];

    // If we already have complete data, cache it and use it
    if (infos != null && infos is List && infos.isNotEmpty) {
      await _cacheService.saveData(
        _cacheBoxName,
        _testDetailsCacheKey,
        widget.tests,
      );
      setState(() {
        _cachedTestData = widget.tests;
        _isOfflineMode = false;
      });
    } else {
      // Try to load from cache first
      final cachedData = _cacheService.getData(
        _cacheBoxName,
        _testDetailsCacheKey,
        defaultValue: null,
        maxAge: null,
      );

      if (cachedData != null && cachedData is Map) {
        // Cache exists, use it
        setState(() {
          _cachedTestData = Map<String, dynamic>.from(cachedData);
          _isOfflineMode = true;
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
                onPressed: _refreshTestData,
              ),
            ),
          );
        }
      } else {
        // No cache - try to fetch from API (will fail if offline)
        await _refreshTestData();
      }
    }
  }

  Future<void> _refreshTestData() async {
    if (!mounted) return;

    final testId = widget.tests['id'] ?? widget.tests['test_id'];
    if (testId == null) return;

    try {
      final response = await http
          .get(
            Uri.parse('${getBaseUrl()}/api/tests/$testId?includeinfos=true'),
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
        final Map<String, dynamic> data = json.decode(response.body);

        // Add category info for bookmarking
        data['category_name'] = widget.tests['category_name'];
        data['category_id'] = widget.tests['category_id'];

        // Save to cache
        await _cacheService.saveData(_cacheBoxName, _testDetailsCacheKey, data);

        setState(() {
          _cachedTestData = data;
          _isOfflineMode = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Data refreshed successfully'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        throw Exception('Failed to load data (${response.statusCode})');
      }
    } catch (e) {
      // Failed to fetch - set offline mode
      setState(() => _isOfflineMode = true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  String _getCacheAgeMessage() {
    final age = _cacheService.getCacheAge(_cacheBoxName, _testDetailsCacheKey);
    if (age == null) return '';

    if (age.inMinutes < 60) {
      return 'Updated ${age.inMinutes} min ago';
    } else if (age.inHours < 24) {
      return 'Updated ${age.inHours} hrs ago';
    } else {
      return 'Updated ${age.inDays} days ago';
    }
  }

  Future<void> _navigateToBookmarks() async {
    final hasChanges = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BookmarkScreen()),
    );

    // If bookmarks were modified in BookmarkScreen, refresh status
    if (hasChanges == true) {
      _checkBookmarkStatus();
    }
  }

  Future<void> _toggleBookmark() async {
    final testId = widget.tests['test_id'] ?? widget.tests['id'];
    if (testId == null) return;

    final dataToBookmark = _cachedTestData ?? widget.tests;
    final nowBookmarked = await _bookmarkService.toggleBookmark(dataToBookmark);

    setState(() => _isBookmarked = nowBookmarked);

    if (mounted) {
      final testName = dataToBookmark['test_name'] ?? dataToBookmark['name'];

      // Show SnackBar with optional "View" action
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nowBookmarked
                ? 'Added "$testName" to bookmarks'
                : 'Removed "$testName" from bookmarks',
          ),
          duration: const Duration(seconds: 3),
          backgroundColor: nowBookmarked ? Colors.green : Colors.grey[700],
          action:
              nowBookmarked
                  ? SnackBarAction(
                    label: 'View',
                    textColor: Colors.white,
                    onPressed: _navigateToBookmarks,
                  )
                  : null,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayData = _cachedTestData ?? widget.tests;
    final List<dynamic> infos = displayData['infos'] ?? [];
    final String testName =
        displayData['test_name'] ?? displayData['name'] ?? 'Lab Test Info';
    final String apiBaseUrl = getBaseUrl();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: AutoSizeText(
                testName,
                style: const TextStyle(fontWeight: FontWeight.w600),
                maxLines: 1,
                minFontSize: 12,
                maxFontSize: 20,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_isOfflineMode) ...[
              const SizedBox(width: 6),
              Icon(Icons.cloud_off, size: 18, color: Colors.orange),
            ],
          ],
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () {
            Navigator.pop(context, _isBookmarked); // send back status
          },
        ),
        actions: [
          if (_isOfflineMode)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshTestData,
              tooltip: 'Refresh data',
            ),
          IconButton(
            icon: Icon(
              _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
              color: _isBookmarked ? Colors.blue : null,
            ),
            onPressed: _toggleBookmark,
            tooltip: _isBookmarked ? 'Remove bookmark' : 'Add bookmark',
          ),
        ],
      ),
      body:
          infos.isEmpty
              ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "No test infos available",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isOfflineMode
                            ? "This test hasn't been cached yet.\nPlease connect to the internet to view."
                            : "No information available for this test.",
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                        textAlign: TextAlign.center,
                      ),
                      if (!_isOfflineMode) ...[
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _refreshTestData,
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
                    ],
                  ),
                ),
              )
              : RefreshIndicator(
                onRefresh: _refreshTestData,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: infos.length,
                  itemBuilder: (context, index) {
                    final info = infos[index];
                    final Map<String, dynamic> d = info['extraData'] ?? {};

                    return _TestInfoCard(data: d, apiBaseUrl: apiBaseUrl);
                  },
                ),
              ),
    );
  }
}

// Rest of the _TestInfoCard class remains the same
class _TestInfoCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String apiBaseUrl;

  const _TestInfoCard({required this.data, required this.apiBaseUrl});

  String _stripHtml(String? html) {
    if (html == null || html.isEmpty) return '';
    final regex = RegExp(r'<[^>]*>');
    return html.replaceAll(regex, '').replaceAll('&nbsp;', ' ').trim();
  }

  dynamic _sanitizeData(dynamic data) {
    if (data is String) return _stripHtml(data);
    if (data is List) return data.map(_sanitizeData).toList();
    if (data is Map) {
      return Map.fromEntries(
        data.entries.map(
          (entry) => MapEntry(entry.key, _sanitizeData(entry.value)),
        ),
      );
    }
    return data;
  }

  String? _getImageSrc() {
    final dynamic image = data['image'];
    if (image == null) return null;

    String? result;
    if (image is String) {
      if (image.contains('localhost:5001')) {
        result = image.replaceAll('http://localhost:5001', apiBaseUrl);
      } else if (image.startsWith('http')) {
        result = image;
      } else {
        result = '$apiBaseUrl$image';
      }
    } else if (image is Map && image['url'] != null) {
      final String url = image['url'].toString();
      if (url.contains('localhost:5001')) {
        result = url.replaceAll('http://localhost:5001', apiBaseUrl);
      } else if (url.startsWith('http')) {
        result = url;
      } else {
        result = '$apiBaseUrl$url';
      }
    }
    return result;
  }

  List<String> _getSpecimenTypes() {
    final List<String> types = [];
    if (data['specimenType'] != null) {
      if (data['specimenType'] is List) {
        types.addAll(
          List<String>.from(
            data['specimenType'],
          ).where((type) => type != "Others..."),
        );
      } else if (data['specimenType'] is String &&
          data['specimenType'] != "Others...") {
        types.add(data['specimenType']);
      }
    }
    if (data['otherSpecimen'] != null) {
      types.add(data['otherSpecimen'].toString());
    }
    return types;
  }

  String _processHtmlForAlignment(String htmlContent) {
    final document = html_parser.parse(htmlContent);
    final listItems = document.querySelectorAll('li');
    for (var li in listItems) {
      final style = li.attributes['style'] ?? '';
      if (style.contains('text-align: center') ||
          style.contains('text-align:center')) {
        final cleanedStyle =
            style
                .replaceAll(RegExp(r'list-style-position:\s*[^;]+;?'), '')
                .trim();
        li.attributes['style'] =
            '$cleanedStyle list-style-position: outside;'.trim();
      } else if (style.contains('text-align: right') ||
          style.contains('text-align:right')) {
        final cleanedStyle =
            style
                .replaceAll(RegExp(r'list-style-position:\s*[^;]+;?'), '')
                .replaceAll(RegExp(r'direction:\s*[^;]+;?'), '')
                .trim();
        li.attributes['style'] =
            '$cleanedStyle list-style-position: outside;'.trim();
      }
    }

    final images = document.querySelectorAll('img');
    for (var img in images) {
      final alignment = img.attributes['data-alignment'] ?? '';
      final classes = img.attributes['class'] ?? '';
      final currentStyle = img.attributes['style'] ?? '';

      String alignStyle = '';
      if (alignment == 'center' || classes.contains('image-align-center')) {
        alignStyle = 'display: block; margin-left: auto; margin-right: auto;';
      } else if (alignment == 'right' ||
          classes.contains('image-align-right')) {
        alignStyle = 'display: block; margin-left: auto; margin-right: 0;';
      } else if (alignment == 'left' || classes.contains('image-align-left')) {
        alignStyle = 'display: block; margin-left: 0; margin-right: auto;';
      }

      String finalStyle = currentStyle;
      if (alignStyle.isNotEmpty) {
        finalStyle = currentStyle
            .replaceAll(RegExp(r'margin-left:\s*[^;]+;?'), '')
            .replaceAll(RegExp(r'margin-right:\s*[^;]+;?'), '')
            .replaceAll(RegExp(r'display:\s*[^;]+;?'), '');
        finalStyle = '$alignStyle $finalStyle'.trim();
      }
      img.attributes['style'] = finalStyle;
    }
    return document.body?.innerHtml ?? htmlContent;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTitle(),
            _buildLabInCharge(),
            _buildSpecimenType(),
            _buildForm(context),
            _buildTAT(),
            _buildContainer(),
            _buildContainerLabel(),
            _buildSampleVolume(),
            _buildDescription(),
            _buildRemark(),
          ],
        ),
      ),
    );
  }

  Widget _buildTitle() {
    if (data['title'] == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        _stripHtml(data['title']),
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildLabInCharge() {
    if (data['labInCharge'] == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Lab In-Charge:",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(_stripHtml(data['labInCharge'])),
        ],
      ),
    );
  }

  Widget _buildSpecimenType() {
    final List<String> types = _getSpecimenTypes();
    if (types.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Specimen Type:",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          ...types.map(
            (type) => Html(
              data: _sanitizeData(type).toString().replaceAll('\n', '<br />'),
              style: {
                "body": Style(margin: Margins.zero, padding: HtmlPaddings.zero),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    if (data['form'] == null) return const SizedBox.shrink();
    final form = data['form'];
    if (form is! Map || (form['text'] == null && form['url'] == null)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Form:", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          if (form['url'] != null)
            InkWell(
              onTap: () => _launchUrl(context, _sanitizeData(form['url'])),
              child: Text(
                _sanitizeData(form['text'] ?? form['url']),
                style: const TextStyle(
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                ),
              ),
            )
          else
            Text(_stripHtml(form['text'])),
        ],
      ),
    );
  }

  Future<void> _launchUrl(BuildContext context, String urlString) async {
    try {
      final Uri uri = Uri.parse(urlString);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not launch $urlString')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error launching URL: $e')));
      }
    }
  }

  Widget _buildTAT() {
    if (data['TAT'] == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("TAT:", style: TextStyle(fontWeight: FontWeight.bold)),
          Html(
            data: _processHtmlForAlignment(
              _sanitizeData(data['TAT']).toString().replaceAll('\n', '<br />'),
            ),
            style: {
              "body": Style(margin: Margins.zero, padding: HtmlPaddings.zero),
              "img": Style(display: Display.block),
              "ul": Style(
                margin: Margins.zero,
                padding: HtmlPaddings.only(left: 20),
                listStylePosition: ListStylePosition.outside,
              ),
              "ol": Style(
                margin: Margins.zero,
                padding: HtmlPaddings.only(left: 20),
                listStylePosition: ListStylePosition.outside,
              ),
              "li": Style(margin: Margins.only(bottom: 5)),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildContainer() {
    final String? imageSrc = _getImageSrc();
    if (imageSrc == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Container:",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Image.network(
            imageSrc,
            width: 250,
            fit: BoxFit.contain,
            errorBuilder:
                (context, error, stackTrace) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.broken_image, color: Colors.red, size: 50),
                    const SizedBox(height: 4),
                    Text(
                      'Failed to load image',
                      style: TextStyle(color: Colors.red[700], fontSize: 12),
                    ),
                  ],
                ),
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return SizedBox(
                width: 250,
                height: 100,
                child: Center(
                  child: CircularProgressIndicator(
                    value:
                        loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildContainerLabel() {
    if (data['containerLabel'] == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: Text(
        _stripHtml(data['containerLabel']),
        style: const TextStyle(height: 1.0),
      ),
    );
  }

  Widget _buildSampleVolume() {
    if (data['sampleVolume'] == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Sample Volume:",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Html(
            data: _processHtmlForAlignment(
              _sanitizeData(
                data['sampleVolume'],
              ).toString().replaceAll('\n', '<br />'),
            ),
            style: {
              "body": Style(margin: Margins.zero, padding: HtmlPaddings.zero),
              "img": Style(display: Display.block),
              "ul": Style(
                margin: Margins.zero,
                padding: HtmlPaddings.only(left: 20),
                listStylePosition: ListStylePosition.outside,
              ),
              "ol": Style(
                margin: Margins.zero,
                padding: HtmlPaddings.only(left: 20),
                listStylePosition: ListStylePosition.outside,
              ),
              "li": Style(margin: Margins.only(bottom: 5)),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDescription() {
    if (data['description'] == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Html(
        data: _processHtmlForAlignment(data['description']),
        style: {
          "body": Style(margin: Margins.zero, padding: HtmlPaddings.zero),
          "img": Style(display: Display.block),
          "ul": Style(
            margin: Margins.zero,
            padding: HtmlPaddings.only(left: 20),
            listStylePosition: ListStylePosition.outside,
          ),
          "ol": Style(
            margin: Margins.zero,
            padding: HtmlPaddings.only(left: 20),
            listStylePosition: ListStylePosition.outside,
          ),
          "li": Style(margin: Margins.only(bottom: 5)),
        },
      ),
    );
  }

  Widget _buildRemark() {
    if (data['remark'] == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Remark:", style: TextStyle(fontWeight: FontWeight.bold)),
          Html(
            data: _processHtmlForAlignment(data['remark']),
            style: {
              "body": Style(margin: Margins.zero, padding: HtmlPaddings.zero),
              "img": Style(display: Display.block),
              "ul": Style(
                margin: Margins.zero,
                padding: HtmlPaddings.only(left: 20),
                listStylePosition: ListStylePosition.outside,
              ),
              "ol": Style(
                margin: Margins.zero,
                padding: HtmlPaddings.only(left: 20),
                listStylePosition: ListStylePosition.outside,
              ),
              "li": Style(margin: Margins.only(bottom: 5)),
            },
          ),
        ],
      ),
    );
  }
}
