import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';

class TestInfoScreen extends StatefulWidget {
  final Map<String, dynamic> labTest;

  const TestInfoScreen({super.key, required this.labTest});

  @override
  State<TestInfoScreen> createState() => _TestInfoScreenState();
}

class _TestInfoScreenState extends State<TestInfoScreen> {
  @override
  Widget build(BuildContext context) {
    final String htmlContent =
        widget.labTest['content_html'] ?? '<p>No content available.</p>';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.labTest['test_name'] ?? 'Lab Test Info'),
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
            data: htmlContent,
            style: {
              "p": Style(
                margin: Margins.only(bottom: 16.0),
                lineHeight: LineHeight.number(1.0),
                fontSize: FontSize(16.0),
              ),
              "div": Style(
                margin: Margins.only(bottom: 16.0),
                lineHeight: LineHeight.number(0.5),
              ),
              "ul": Style(
                margin: Margins.only(bottom: 16.0),
                lineHeight: LineHeight.number(0.5),
              ),
              "li": Style(
                margin: Margins.only(bottom: 8.0),
                lineHeight: LineHeight.number(0.5),
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
              "strong": Style(
                fontWeight: FontWeight.bold,
              ),
              "em": Style(
                fontStyle: FontStyle.italic,
              ),
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