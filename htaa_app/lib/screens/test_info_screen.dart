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
  IconData? topMessageIcon;
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

  // Enhanced notification system with icons
  void showTopMessage(
    String message, {
    Color color = Colors.blue,
    IconData? icon,
    VoidCallback? onActionPressed,
    String? actionLabel,
  }) {
    _messageTimer?.cancel();

    setState(() {
      topMessage = message;
      topMessageColor = color;
      topMessageIcon = icon;
      _topMessageAction = onActionPressed;
      _topMessageActionLabel = actionLabel;
    });

    _messageTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          topMessage = null;
          topMessageIcon = null;
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
    final baseUrl = getBaseUrl();

    for (var info in infos) {
      if (info is Map && info.containsKey('extraData')) {
        final extraData = info['extraData'];
        if (extraData is Map && extraData.containsKey('image')) {
          dynamic imageData = extraData['image'];
          String? imagePath;

          if (imageData is String) {
            imagePath = imageData;
          } else if (imageData is Map && imageData['url'] != null) {
            imagePath = imageData['url'].toString();
          }

          if (imagePath != null && imagePath.startsWith('/')) {
            if (!imagePath.contains('cached_images')) {
              final networkUrl = '$baseUrl$imagePath';
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
    }

    if (hasChanges) {
      await _cacheService.saveData(_cacheBoxName, _testDetailsCacheKey, data);
    }

    return data;
  }

  Future<void> _initializeTestData() async {
    setState(() => _isLoading = true);

    final infos = widget.tests['infos'];

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
      var cachedData = _cacheService.getData(
        _cacheBoxName,
        _testDetailsCacheKey,
        defaultValue: null,
        maxAge: null,
      );

      if (cachedData != null && cachedData is Map) {
        cachedData = await _fixImagePaths(
          Map<String, dynamic>.from(cachedData),
        );

        setState(() {
          _cachedTestData = cachedData as Map<String, dynamic>;
          _isOfflineMode = true;
          _isLoading = false;
        });

        showTopMessage(
          'You are offline. Test info cannot be refreshed.',
          color: Colors.orange,
        );
      } else {
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

        if (widget.tests['category_name'] != null) {
          data['category_name'] = widget.tests['category_name'];
        }
        if (widget.tests['category_id'] != null) {
          data['category_id'] = widget.tests['category_id'];
        }

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
          'You are offline. Test info cannot be refreshed.',
          color: Colors.orange,
        );
      } else {
        setState(() {
          _isOfflineMode = true;
          _isLoading = false;
        });

        String errorMessage = _getErrorMessage(e);
        showTopMessage(
          errorMessage,
          color: Colors.red[600]!,
          icon: Icons.error_outline,
        );
      }
    }
  }

  String _getErrorMessage(dynamic error) {
    final errorStr = error.toString();
    if (errorStr.contains('timeout') || errorStr.contains('Timeout')) {
      return 'Connection timeout';
    } else if (errorStr.contains('SocketException') ||
        errorStr.contains('Unable to connect') ||
        errorStr.contains('Failed host lookup')) {
      return 'No internet connection';
    } else if (errorStr.contains('Server error')) {
      return 'Server error occurred';
    } else {
      return 'Failed to load data';
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
          'Added to bookmarks',
          color: Colors.green,
          icon: Icons.bookmark_added,
          actionLabel: 'View',
          onActionPressed: _navigateToBookmarks,
        );
      } else {
        showTopMessage(
          'Removed from bookmarks',
          color: Colors.grey[600]!,
          icon: Icons.bookmark_remove,
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
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: AutoSizeText(
                testName,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                maxLines: 1,
                minFontSize: 12,
                maxFontSize: 20,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_isOfflineMode) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off, size: 18, color: Colors.orange[700]),
                  const SizedBox(width: 4),
                ],
              ),
            ],
          ],
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.pop(context, _isBookmarked),
        ),
        actions: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: IconButton(
              key: ValueKey(_isBookmarked),
              icon: Icon(
                _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                color:
                    _isBookmarked
                        ? Theme.of(context).primaryColor
                        : Colors.grey[600],
              ),
              onPressed: _toggleBookmark,
              tooltip: _isBookmarked ? 'Remove bookmark' : 'Add bookmark',
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Enhanced status banner
          if (topMessage != null)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: double.infinity,
              decoration: BoxDecoration(
                color: topMessageColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              child: Row(
                children: [
                  if (topMessageIcon != null) ...[
                    Icon(topMessageIcon, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      topMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
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
                          topMessageIcon = null;
                          _topMessageAction = null;
                          _topMessageActionLabel = null;
                        });
                        _messageTimer?.cancel();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,

                        // REMOVE ALL INTERNAL PADDING
                        padding: EdgeInsets.zero,

                        // REMOVE BUTTON MINIMUM CONSTRAINTS
                        minimumSize: Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,

                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        _topMessageActionLabel!,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child:
                _isLoading
                    ? _buildLoadingState()
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
                          return _TestInfoCard(
                            data: d,
                            apiBaseUrl: apiBaseUrl,
                            index: index,
                          );
                        },
                      ),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[600]!),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading test information...',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isOfflineMode ? Icons.cloud_off : Icons.info_outline,
                size: 64,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _isOfflineMode
                  ? "No Cached Data Available"
                  : "No Information Available",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _isOfflineMode
                  ? "This test hasn't been viewed while online yet.\nConnect to the internet to view details."
                  : "No information is currently available for this test.",
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            if (_isOfflineMode) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _refreshTestData,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[600],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Enhanced _TestInfoCard class
class _TestInfoCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String apiBaseUrl;
  final int index;

  const _TestInfoCard({
    required this.data,
    required this.apiBaseUrl,
    required this.index,
  });

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
      if (image.contains('cached_images')) {
        return image;
      }

      if (image.startsWith('/')) {
        result = '$apiBaseUrl$image';
      } else if (image.contains('localhost:5001')) {
        result = image.replaceAll('http://localhost:5001', apiBaseUrl);
      } else if (image.startsWith('http')) {
        result = image;
      } else {
        result = '$apiBaseUrl$image';
      }
    } else if (image is Map) {
      if (image['imageUrl'] != null) {
        final imageUrl = image['imageUrl'].toString();

        if (imageUrl.contains('cached_images')) {
          return imageUrl;
        }

        if (imageUrl.startsWith('/')) {
          result = '$apiBaseUrl$imageUrl';
        } else if (imageUrl.contains('localhost:5001')) {
          result = imageUrl.replaceAll('http://localhost:5001', apiBaseUrl);
        } else if (imageUrl.startsWith('http')) {
          result = imageUrl;
        } else {
          result = '$apiBaseUrl$imageUrl';
        }
      } else if (image['url'] != null) {
        final String url = image['url'].toString();

        if (url.contains('cached_images')) {
          return url;
        }

        if (url.startsWith('/')) {
          result = '$apiBaseUrl$url';
        } else if (url.contains('localhost:5001')) {
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
    final List<Widget> children = [];

    final title = (data['title'] ?? '').toString().trim();
    if (title.isNotEmpty) children.add(_buildTitle());

    final labInCharge = (data['labInCharge'] ?? '').toString().trim();
    if (labInCharge.isNotEmpty) children.add(_buildLabInCharge());

    if (_getSpecimenTypes().isNotEmpty) children.add(_buildSpecimenType());

    final form = data['form'];
    if (form != null &&
        form is Map &&
        (form['text'] != null || form['url'] != null)) {
      children.add(_buildForm(context));
    }

    final tat = (data['TAT'] ?? '').toString().trim();
    if (tat.isNotEmpty) children.add(_buildTAT());

    final imageSrc = _getImageSrc();
    if (imageSrc != null) children.add(_buildContainer());

    final sampleVolume = (data['sampleVolume'] ?? '').toString().trim();
    if (sampleVolume.isNotEmpty) children.add(_buildSampleVolume());

    final description = (data['description'] ?? '').toString().trim();
    if (description.isNotEmpty) children.add(_buildDescription());

    final remark = (data['remark'] ?? '').toString().trim();
    if (remark.isNotEmpty) children.add(_buildRemark());

    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 300 + (index * 50)),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        elevation: 2,
        shadowColor: Colors.black.withOpacity(0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Colors.grey[50]!],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildTitle() {
    if (data['title'] == null) return const SizedBox.shrink();
    return Text(
      _stripHtml(data['title']),
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
        height: 1.3,
        letterSpacing: -0.5,
      ),
    );
  }

  Widget _buildLabInCharge() {
    if (data['labInCharge'] == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Lab In-Charge'),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 2, 0, 10),
            child: Text(_stripHtml(data['labInCharge']), style: TextStyle()),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecimenType() {
    final List<String> types = _getSpecimenTypes();
    if (types.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Specimen Type'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 2, 0, 10),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:
                  types
                      .map(
                        (type) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(_stripHtml(type), style: TextStyle()),
                        ),
                      )
                      .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final form = data['form'];
    if (form == null ||
        form is! Map ||
        (form['text'] == null && form['url'] == null)) {
      return const SizedBox.shrink();
    }

    final formText = (form['text'] ?? form['url'] ?? '').toString().trim();
    if (formText.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Form'),
          if (form['url'] != null)
            InkWell(
              onTap: () => _launchUrl(context, _sanitizeData(form['url'])),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 2, 0, 10),
                child: Text(
                  _sanitizeData(form['text'] ?? form['url']),
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.underline,
                  ),
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
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white),
                  const SizedBox(width: 8),
                  Text('Could not launch $urlString'),
                ],
              ),
              backgroundColor: Colors.red[600],
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 8),
                Text('Error launching URL: $e'),
              ],
            ),
            backgroundColor: Colors.red[600],
          ),
        );
      }
    }
  }

  Widget _buildTAT() {
    final tat = (data['TAT'] ?? '').toString().trim();
    if (tat.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('TAT'),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 2, 0, 10),
            child: Html(
              data: _processHtmlForAlignment(
                _sanitizeData(
                  data['TAT'],
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
          ),
        ],
      ),
    );
  }

  Widget _buildContainer() {
    final String? imageSrc = _getImageSrc();
    final String containerLabel =
        (data['containerLabel'] ?? '').toString().trim();

    // Don't show container section if both image and label are empty
    if (imageSrc == null && containerLabel.isEmpty)
      return const SizedBox.shrink();

    final bool isLocalImage = imageSrc?.contains('cached_images') ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Container'),
          Container(
            padding: const EdgeInsets.fromLTRB(0, 2, 0, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (imageSrc != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 5, left: 10),
                    child: ClipRRect(
                      child: CachedImageWidget(
                        imagePath: imageSrc,
                        width: 250,
                        fit: BoxFit.contain,
                        placeholder: Container(
                          width: 250,
                          height: 100,
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 32,
                                height: 32,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.blue[600]!,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                isLocalImage
                                    ? 'Loading cached image...'
                                    : 'Downloading image...',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        errorWidget: Container(
                          width: 250,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red[200]!),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isLocalImage
                                    ? Icons.image_not_supported
                                    : Icons.cloud_off,
                                color: Colors.red[400],
                                size: 40,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                isLocalImage
                                    ? 'Cached image unavailable'
                                    : 'Image unavailable offline',
                                style: TextStyle(
                                  color: Colors.red[700],
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              if (!isLocalImage)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    'Will download when online',
                                    style: TextStyle(
                                      color: Colors.red[600],
                                      fontSize: 11,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                if (imageSrc != null && containerLabel.isNotEmpty)
                  const SizedBox(height: 12),
                if (containerLabel.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(10, 0, 0, 0),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _stripHtml(containerLabel),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContainerLabel() {
    if (data['containerLabel'] == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 2, 0, 10),
        child: Text(
          _stripHtml(data['containerLabel']),
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _buildSampleVolume() {
    final sampleVolume = (data['sampleVolume'] ?? '').toString().trim();
    if (sampleVolume.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Sample Volume'),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 2, 0, 10),
            child: Html(
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
          ),
        ],
      ),
    );
  }

  Widget _buildDescription() {
    final description = (data['description'] ?? '').toString().trim();
    if (description.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Html(
            data: _processHtmlForAlignment(data['description']),
            style: {
              "body": Style(margin: Margins.zero, padding: HtmlPaddings.zero),
              "img": Style(
                display: Display.block,
                padding: HtmlPaddings.only(top: 20),
              ),
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

  Widget _buildRemark() {
    final remark = (data['remark'] ?? '').toString().trim();
    if (remark.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Remark'),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 2, 0, 10),
            child: Html(
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
          ),
        ],
      ),
    );
  }
}
