import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '/api_config.dart';
import 'test_info_screen.dart';

class CategoryScreen extends StatefulWidget {
  final String categoryName;

  const CategoryScreen({super.key, required this.categoryName});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  List<dynamic> labTests = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    fetchLabTests();
  }

  Future<void> fetchLabTests() async {
    final url =
        '${getBaseUrl()}/api/lab-tests?category=${Uri.encodeComponent(widget.categoryName)}';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          labTests = data;
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = 'Failed to load lab tests';
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.categoryName), centerTitle: true),
      body:
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : errorMessage != null
              ? Center(child: Text(errorMessage!))
              : labTests.isEmpty
              ? const Center(child: Text('No lab tests found.'))
              : ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: labTests.length,
                itemBuilder: (context, index) {
                  final test = labTests[index];
                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      title: Text(
                        test['test_name'] ?? 'Unnamed Test',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => TestInfoScreen(labTest: test),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
    );
  }
}
