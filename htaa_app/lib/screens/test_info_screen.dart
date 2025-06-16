import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';

class TestInfoScreen extends StatefulWidget {
  final Map<String, dynamic> labTest;

  const TestInfoScreen({super.key, required this.labTest});

  @override
  State<TestInfoScreen> createState() => _TestInfoScreenState();
}

class _TestInfoScreenState extends State<TestInfoScreen> {
  // Helper method for base64 images
  Widget _buildBase64Image(String dataUrl) {
    try {
      // Extract the base64 part from data:image/png;base64,actual_data
      final RegExp regex = RegExp(r'data:image\/[^;]+;base64,(.+)');
      final Match? match = regex.firstMatch(dataUrl);

      if (match == null) {
        throw Exception('Invalid data URL format');
      }

      final String base64String = match.group(1)!;
      final Uint8List bytes = base64Decode(base64String);

      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return FutureBuilder<Size>(
              future: _getImageSize(bytes),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final imageSize = snapshot.data!;
                final availableWidth = constraints.maxWidth;
                final shouldScale = imageSize.width > availableWidth;

                final screenWidth = MediaQuery.of(context).size.width;
                final maxAllowedWidth =
                    screenWidth - 32; // account for paddings

                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxAllowedWidth),
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      width:
                          imageSize.width > maxAllowedWidth
                              ? maxAllowedWidth
                              : imageSize.width,
                      errorBuilder: (context, error, stackTrace) {
                        print('Base64 image decode error: $error');
                        return Container(
                          padding: const EdgeInsets.all(16.0),
                          decoration: BoxDecoration(
                            color: Colors.red[100],
                            borderRadius: BorderRadius.circular(8.0),
                            border: Border.all(color: Colors.red[300]!),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.broken_image, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text(
                                    'Failed to decode base64 image',
                                    style: TextStyle(
                                      color: Colors.red[700],
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            );
          },
        ),
      );
    } catch (e) {
      print('Error processing base64 image: $e');
      return Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Colors.red[100],
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: Colors.red[300]!),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, color: Colors.red),
            SizedBox(width: 8),
            Text(
              'Invalid base64 image data',
              style: TextStyle(color: Colors.red[700]),
            ),
          ],
        ),
      );
    }
  }

  Future<Size> _getImageSize(Uint8List bytes) async {
    final Completer<Size> completer = Completer();
    final image = Image.memory(bytes);
    image.image
        .resolve(ImageConfiguration())
        .addListener(
          ImageStreamListener((ImageInfo info, bool _) {
            final myImage = info.image;
            completer.complete(
              Size(myImage.width.toDouble(), myImage.height.toDouble()),
            );
          }),
        );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final String htmlContent =
        widget.labTest['content_html'] ?? '<p>No content available.</p>';
    String processedHtml = htmlContent.replaceAll('<p></p>', '<br></br>');

    return Scaffold(
      appBar: AppBar(
        title: AutoSizeText(
          widget.labTest['test_name'] ?? 'Lab Test Info',
          style: const TextStyle(fontWeight: FontWeight.w600),
          maxLines: 1,
          minFontSize: 12,
          maxFontSize: 20,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12.0),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withAlpha(51),
                spreadRadius: 2,
                blurRadius: 5,
                offset: Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16.0),
          child: Html(
            data: processedHtml,
            style: {
              "p": Style(
                lineHeight: LineHeight.number(1.0),
                margin: Margins.only(top: 0),
                fontSize: FontSize(18.0),
              ),
              "div": Style(
                margin: Margins.only(bottom: 16.0),
                lineHeight: LineHeight.number(1.0),
              ),
              "ul": Style(
                fontSize: FontSize(18.0),
                margin: Margins.only(bottom: 16.0),
                lineHeight: LineHeight.number(1.0),
              ),
              "li": Style(
                fontSize: FontSize(18.0),
                margin: Margins.only(bottom: 5.0),
                lineHeight: LineHeight.number(1.0),
              ),
              "h1": Style(
                margin: Margins.only(bottom: 20.0, top: 20.0),
                lineHeight: LineHeight.number(1.3),
              ),
              "h2": Style(
                margin: Margins.only(bottom: 16.0, top: 16.0),
                lineHeight: LineHeight.number(1.3),
              ),
              "h3": Style(
                margin: Margins.only(bottom: 12.0, top: 12.0),
                lineHeight: LineHeight.number(1.3),
              ),
              "strong": Style(fontWeight: FontWeight.bold),
              "em": Style(fontStyle: FontStyle.italic),
              "a": Style(
                color: Colors.blue,
                textDecoration: TextDecoration.underline,
              ),
            },

            onLinkTap: (url, attributes, element) async {
              if (url == null) return;
              final uri = Uri.parse(url);
              final scaffoldMessenger = ScaffoldMessenger.of(context);

              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else if (mounted) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(content: Text('Could not launch $url')),
                );
              }
            },
          ),
        ),
      ),
    );
  }
}
