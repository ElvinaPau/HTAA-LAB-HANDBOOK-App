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
import 'package:htaa_app/widgets/cached_image_widget.dart';

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
  bool _isLoading = false;
  Map<String, dynamic>? _cachedTestData;

  // Top message state
  String? topMessage;
  Color? topMessageColor;
  Timer? _messageTimer;
  VoidCallback? _topMessageAction;
  String? _topMessageActionLabel;

  // Cache configuration
  static const String _cacheBoxName = 'testDetailsBox';
  String get _testDetailsCacheKey {
    final testId = widget.tests['id'] ?? widget.tests['test_id'];
    return 'test_details_$testId';
  }

  // Connectivity
  late final StreamSubscription<ConnectivityResult> _connectivitySubscription;
  Timer? _connectivityDebounce;

  @override
  void initState() {
    super.initState();
    _checkBookmarkStatus();
    _initializeTestData();

    // Listen for connectivity changes with debouncing
    _connectivitySubscription = ConnectivityService().connectivityStream.listen(
      _handleConnectivityChange,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    _connectivityDebounce?.cancel();
    _connectivitySubscription.cancel();
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  // Uniform notification system
  void showTopMessage(
    String message, {
    Color color = Colors.blue,
    VoidCallback? onActionPressed,
    String? actionLabel,
  }) {
    _messageTimer?.cancel();

    setState(() {
      topMessage = message;
      topMessageColor = color;
      _topMessageAction = onActionPressed;
      _topMessageActionLabel = actionLabel;
    });

    _messageTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          topMessage = null;
          _topMessageAction = null;
          _topMessageActionLabel = null;
        });
      }
    });
  }

  void _handleConnectivityChange(ConnectivityResult result) {
    _connectivityDebounce?.cancel();
    _connectivityDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;

      if (result != ConnectivityResult.none && _isOfflineMode) {
        setState(() => _isOfflineMode = false);
        showTopMessage('Back online!', color: Colors.green);
      } else if (result == ConnectivityResult.none && !_isOfflineMode) {
        setState(() => _isOfflineMode = true);
        showTopMessage('You are offline', color: Colors.red);
      }
    });
  }

  @override
  void didPopNext() {
    _checkBookmarkStatus();
  }

  Future<void> _checkBookmarkStatus() async {
    final testId = widget.tests['test_id'] ?? widget.tests['id'];
    if (testId != null) {
      final isBookmarked = await _bookmarkService.isBookmarked(testId);
      if (mounted) setState(() => _isBookmarked = isBookmarked);
    }
  }

  Future<Map<String, dynamic>> _fixImagePaths(Map<String, dynamic> data) async {
    final infos = data['infos'];
    if (infos == null || infos is! List) return data;

    bool hasChanges = false;

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
              !imagePath.contains('cached_images')) {
            // It's a relative path like /imgUploads/..., convert to network URL
            final networkUrl = '${getBaseUrl()}$imagePath';
            print('🔧 Fixing relative path: $imagePath → $networkUrl');

            if (imageData is String) {
              extraData['image'] = networkUrl;
            } else if (imageData is Map) {
              extraData['image']['url'] = networkUrl;
            }
            hasChanges = true;
          }
        }
      }
    }

    // If we made changes, save back to cache
    if (hasChanges) {
      await _cacheService.saveData(_cacheBoxName, _testDetailsCacheKey, data);
      print('✅ Fixed and saved image paths to cache');
    }

    return data;
  }

  Future<void> _initializeTestData() async {
    setState(() => _isLoading = true);

    final infos = widget.tests['infos'];

    // If we already have complete data, fix image paths, cache it and use it
    if (infos != null && infos is List && infos.isNotEmpty) {
      final fixedData = await _fixImagePaths(widget.tests);
      await _cacheService.saveData(
        _cacheBoxName,
        _testDetailsCacheKey,
        fixedData,
      );
      setState(() {
        _cachedTestData = fixedData;
        _isOfflineMode = false;
        _isLoading = false;
      });
    } else {
      // Try to load from cache first
      var cachedData = _cacheService.getData(
        _cacheBoxName,
        _testDetailsCacheKey,
        defaultValue: null,
        maxAge: null,
      );

      if (cachedData != null && cachedData is Map) {
        // Fix any relative paths in cached data
        cachedData = await _fixImagePaths(
          Map<String, dynamic>.from(cachedData),
        );

        setState(() {
          _cachedTestData = cachedData as Map<String, dynamic>;
          _isOfflineMode = true;
          _isLoading = false;
        });

        showTopMessage(
          'You are offline. Data cannot be refreshed.',
          color: Colors.red,
        );
      } else {
        // No cache - try to fetch from API
        await _refreshTestData();
      }
    }
  }

  Future<void> _refreshTestData() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    final testId = widget.tests['id'] ?? widget.tests['test_id'];
    if (testId == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final response = await http
          .get(
            Uri.parse('${getBaseUrl()}/api/tests/$testId?includeinfos=true'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('Connection timeout');
            },
          );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        // Add category info for bookmarking
        if (widget.tests['category_name'] != null) {
          data['category_name'] = widget.tests['category_name'];
        }
        if (widget.tests['category_id'] != null) {
          data['category_id'] = widget.tests['category_id'];
        }

        // Save to cache
        await _cacheService.saveData(_cacheBoxName, _testDetailsCacheKey, data);

        setState(() {
          _cachedTestData = data;
          _isOfflineMode = false;
          _isLoading = false;
        });
      } else {
        throw Exception('Server error (${response.statusCode})');
      }
    } catch (e) {
      // Try to load from cache on error
      final cachedData = _cacheService.getData(
        _cacheBoxName,
        _testDetailsCacheKey,
        defaultValue: null,
        maxAge: null,
      );

      if (cachedData != null && cachedData is Map) {
        setState(() {
          _cachedTestData = Map<String, dynamic>.from(cachedData);
          _isOfflineMode = true;
          _isLoading = false;
        });

        showTopMessage(
          'You are offline. Data cannot be refreshed.',
          color: Colors.red,
        );
      } else {
        setState(() {
          _isOfflineMode = true;
          _isLoading = false;
        });

        String errorMessage = _getErrorMessage(e);
        showTopMessage(errorMessage, color: Colors.red);
      }
    }
  }

  String _getErrorMessage(dynamic error) {
    final errorStr = error.toString();
    if (errorStr.contains('timeout') || errorStr.contains('Timeout')) {
      return 'Connection timeout. Please check your internet.';
    } else if (errorStr.contains('SocketException') ||
        errorStr.contains('Unable to connect') ||
        errorStr.contains('Failed host lookup')) {
      return 'No internet connection. Please try again.';
    } else if (errorStr.contains('Server error')) {
      return 'Server error. Please try again later.';
    } else {
      return 'Failed to load test info. Please try again.';
    }
  }

  Future<void> _navigateToBookmarks() async {
    final hasChanges = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BookmarkScreen()),
    );

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

      if (nowBookmarked) {
        showTopMessage(
          'Added "$testName" to bookmarks',
          color: Colors.green,
          actionLabel: 'View',
          onActionPressed: _navigateToBookmarks,
        );
      } else {
        showTopMessage(
          'Removed "$testName" from bookmarks',
          color: Colors.grey,
        );
      }
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
              Icon(Icons.cloud_off, size: 18, color: Colors.orange[700]),
            ],
          ],
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () {
            Navigator.pop(context, _isBookmarked);
          },
        ),
        actions: [
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
      body: Column(
        children: [
          // Uniform top message banner
          if (topMessage != null)
            Container(
              width: double.infinity,
              color: topMessageColor,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      topMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (_topMessageAction != null &&
                      _topMessageActionLabel != null)
                    TextButton(
                      onPressed: () {
                        _topMessageAction?.call();
                        setState(() {
                          topMessage = null;
                          _topMessageAction = null;
                          _topMessageActionLabel = null;
                        });
                        _messageTimer?.cancel();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                      ),
                      child: Text(
                        _topMessageActionLabel!,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child:
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : infos.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                      onRefresh: _refreshTestData,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: infos.length,
                        itemBuilder: (context, index) {
                          final info = infos[index];
                          final Map<String, dynamic> d =
                              info['extraData'] ?? {};
                          return _TestInfoCard(data: d, apiBaseUrl: apiBaseUrl);
                        },
                      ),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 64, color: Colors.grey[400]),
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
          ],
        ),
      ),
    );
  }
}

// _TestInfoCard class remains the same
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
      // Check if it's already a local file path (from cache)
      if (image.startsWith('/')) {
        print('📦 Using cached local image: $image');
        return image;
      }

      // Otherwise, fix network URL
      if (image.contains('localhost:5001')) {
        result = image.replaceAll('http://localhost:5001', apiBaseUrl);
      } else if (image.startsWith('http')) {
        result = image;
      } else {
        result = '$apiBaseUrl$image';
      }
    } else if (image is Map) {
      // Check for imageUrl (used in infos)
      if (image['imageUrl'] != null) {
        final imageUrl = image['imageUrl'].toString();

        // Check if it's a cached local path
        if (imageUrl.startsWith('/')) {
          print('📦 Using cached local image from map: $imageUrl');
          return imageUrl;
        }

        // Fix network URL
        if (imageUrl.contains('localhost:5001')) {
          result = imageUrl.replaceAll('http://localhost:5001', apiBaseUrl);
        } else if (imageUrl.startsWith('http')) {
          result = imageUrl;
        } else {
          result = '$apiBaseUrl$imageUrl';
        }
      }
      // Fallback to 'url' key
      else if (image['url'] != null) {
        final String url = image['url'].toString();

        if (url.startsWith('/')) {
          print('📦 Using cached local image from url: $url');
          return url;
        }

        if (url.contains('localhost:5001')) {
          result = url.replaceAll('http://localhost:5001', apiBaseUrl);
        } else if (url.startsWith('http')) {
          result = url;
        } else {
          result = '$apiBaseUrl$url';
        }
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

    // Check if using local cache
    final bool isLocalImage = imageSrc.startsWith('/');
    print('📦 Container image source: $imageSrc');
    print('📦 Is local cached image: $isLocalImage');

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
          CachedImageWidget(
            imagePath: imageSrc,
            width: 250,
            fit: BoxFit.contain,
            placeholder: SizedBox(
              width: 250,
              height: 100,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 8),
                    Text(
                      isLocalImage
                          ? 'Loading cached image...'
                          : 'Downloading...',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
            errorWidget: Container(
              width: 250,
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[400]!),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isLocalImage ? Icons.image_not_supported : Icons.cloud_off,
                    color: Colors.grey[600],
                    size: 40,
                  ),
                  SizedBox(height: 8),
                  Text(
                    isLocalImage
                        ? 'Cached image unavailable'
                        : 'Image unavailable offline',
                    style: TextStyle(color: Colors.grey[700], fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  if (!isLocalImage)
                    Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Will download when online',
                        style: TextStyle(color: Colors.grey[600], fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
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
