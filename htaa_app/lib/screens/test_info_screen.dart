import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:htaa_app/main.dart';
import 'package:htaa_app/screens/bookmark_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:html/parser.dart' as html_parser;
import '/api_config.dart';
import 'package:htaa_app/services/bookmark_service.dart';

class TestInfoScreen extends StatefulWidget {
  final Map<String, dynamic> tests;
  const TestInfoScreen({super.key, required this.tests});

  @override
  State<TestInfoScreen> createState() => _TestInfoScreenState();
}

class _TestInfoScreenState extends State<TestInfoScreen> with RouteAware {
  final BookmarkService _bookmarkService = BookmarkService();
  bool _isBookmarked = false;

  @override
  void initState() {
    super.initState();
    _checkBookmarkStatus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route changes
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
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

    final nowBookmarked = await _bookmarkService.toggleBookmark(widget.tests);

    setState(() => _isBookmarked = nowBookmarked);

    if (mounted) {
      // Show SnackBar with optional "View" action
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nowBookmarked
                ? 'Added "${widget.tests['test_name'] ?? widget.tests['name']}" to bookmarks'
                : 'Removed "${widget.tests['test_name'] ?? widget.tests['name']}" from bookmarks',
          ),
          duration: const Duration(seconds: 3),
          backgroundColor: nowBookmarked ? Colors.green : Colors.grey[700],
          action:
              nowBookmarked
                  ? SnackBarAction(
                    label: 'View',
                    textColor: Colors.white,
                    onPressed:
                        _navigateToBookmarks, // Updated to use new method
                  )
                  : null,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<dynamic> infos = widget.tests['infos'] ?? [];
    final String testName =
        widget.tests['test_name'] ?? widget.tests['name'] ?? 'Lab Test Info';
    final String apiBaseUrl = getBaseUrl();

    return Scaffold(
      appBar: AppBar(
        title: AutoSizeText(
          testName,
          style: const TextStyle(fontWeight: FontWeight.w600),
          maxLines: 1,
          minFontSize: 12,
          maxFontSize: 20,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () {
            Navigator.pop(context, _isBookmarked); // send back status
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
      body:
          infos.isEmpty
              ? const Center(
                child: Text(
                  "No test infos available",
                  style: TextStyle(fontSize: 16, color: Colors.white70),
                ),
              )
              : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: infos.length,
                itemBuilder: (context, index) {
                  final info = infos[index];
                  final Map<String, dynamic> d = info['extraData'] ?? {};

                  return _TestInfoCard(data: d, apiBaseUrl: apiBaseUrl);
                },
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
