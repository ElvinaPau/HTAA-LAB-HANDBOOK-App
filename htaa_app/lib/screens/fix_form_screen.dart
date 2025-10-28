import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '/api_config.dart';
import 'package:url_launcher/url_launcher.dart';

class FixFormScreen extends StatefulWidget {
  const FixFormScreen({super.key});

  @override
  FixFormScreenState createState() => FixFormScreenState();
}

class FixFormScreenState extends State<FixFormScreen> {
  List<dynamic> allForms = [];
  String searchQuery = '';
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    fetchFixForms();
  }

  Future<void> fetchFixForms() async {
    final url = '${getBaseUrl()}/api/forms';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          allForms = data;
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = 'Failed to load forms.';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error: $e';
        isLoading = false;
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
        title: const Text(
          "Forms List",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus(); // dismiss keyboard
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child:
              isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : errorMessage != null
                  ? Center(child: Text(errorMessage!))
                  : Column(
                    children: [
                      // Search bar
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search form...',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.grey[100],
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25.0),
                            borderSide: BorderSide(
                              color: Colors.grey,
                              width: 1.5,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25.0),
                            borderSide: BorderSide(
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
                          setState(() {
                            searchQuery = query;
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                      // Table
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final availableWidth = constraints.maxWidth;

                            // Calculate column widths based on available space
                            final noWidth = availableWidth * 0.10;
                            final fieldWidth = availableWidth * 0.22;
                            final titleWidth = availableWidth * 0.38;
                            final formWidth = availableWidth * 0.30;

                            return SingleChildScrollView(
                              child: DataTable(
                                columnSpacing: 8,
                                horizontalMargin: 8,
                                dataRowMinHeight: 48,
                                dataRowMaxHeight:
                                    double.infinity, // Allow rows to grow
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
                                >.generate(filteredForms.length, (index) {
                                  final form = filteredForms[index];
                                  final formUrl = form['form_url'];
                                  final linkText =
                                      form['link_text'] ?? 'Open Form';

                                  return DataRow(
                                    color: MaterialStateProperty.resolveWith(
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
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          child: Text('${index + 1}'),
                                        ),
                                      ),
                                      DataCell(
                                        Container(
                                          width: fieldWidth - 16,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          child: Text(
                                            form['field'] ?? '-',
                                            softWrap: true,
                                            overflow: TextOverflow.visible,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Container(
                                          width: titleWidth - 16,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          child: Text(
                                            form['title'] ?? '-',
                                            softWrap: true,
                                            overflow: TextOverflow.visible,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Container(
                                          width: formWidth - 16,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          child: InkWell(
                                            onTap: () async {
                                              if (formUrl != null &&
                                                  formUrl
                                                      .toString()
                                                      .isNotEmpty) {
                                                final uri = Uri.parse(formUrl);
                                                if (await canLaunchUrl(uri)) {
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
                                              overflow: TextOverflow.visible,
                                              style: const TextStyle(
                                                color: Colors.blue,
                                                decoration:
                                                    TextDecoration.underline,
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
                    ],
                  ),
        ),
      ),
    );
  }
}
