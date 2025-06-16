import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '/api_config.dart';
import 'package:htaa_app/screens/category_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  List<String> allCategories = [];
  String searchQuery = '';
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    fetchCategories();
  }

  Future<void> fetchCategories() async {
    final url = '${getBaseUrl()}/api/categories';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        data.sort((a, b) => (a['position'] ?? 0).compareTo(b['position'] ?? 0));
        setState(() {
          allCategories =
              data
                  .map<String>((item) => item['category_name'] as String)
                  .toList();
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = 'Failed to load categories';
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
    final filteredCategories =
        allCategories.where((category) {
          return category.toLowerCase().contains(searchQuery.toLowerCase());
        }).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.white,
        title: const Text(
          "HTAA LAB HANDBOOK",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(10.0),
        child:
            isLoading
                ? const Center(child: CircularProgressIndicator())
                : errorMessage != null
                ? Center(child: Text(errorMessage!))
                : Column(
                  children: [
                    SizedBox(
                      height: 50,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search for categories...',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25.0),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 15.0,
                            horizontal: 20.0,
                          ),
                        ),
                        onChanged: (query) {
                          setState(() {
                            searchQuery = query;
                          });
                        },
                      ),
                    ),

                    const SizedBox(height: 10),
                    Expanded(
                      child:
                          filteredCategories.isEmpty
                              ? const Center(
                                child: Text('No categories found.'),
                              )
                              : ListView.builder(
                                itemCount: filteredCategories.length,
                                itemBuilder: (context, index) {
                                  return Center(
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        return Center(
                                          child: SizedBox(
                                            width: constraints.maxWidth * 0.6,
                                            child: Card(
                                              color: Colors.white,
                                              elevation: 3,
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 8.0,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                onTap: () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder:
                                                          (
                                                            context,
                                                          ) => CategoryScreen(
                                                            categoryName:
                                                                filteredCategories[index],
                                                          ),
                                                    ),
                                                  );
                                                },
                                                child: Container(
                                                  height: 80,
                                                  alignment: Alignment.center,
                                                  child: Text(
                                                    filteredCategories[index],
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
                    ),
                  ],
                ),
      ),
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              iconSize: 38,
              icon: const Icon(Icons.bookmark),
              onPressed: () {
                // TODO: Navigate to bookmarks
              },
            ),
            const SizedBox(width: 48), // Space for the FAB
            IconButton(
              iconSize: 42,
              icon: const Icon(Icons.settings),
              onPressed: () {
                // TODO: Navigate to profile
              },
            ),
          ],
        ),
      ),
      floatingActionButton: SizedBox(
        width: 70,
        height: 70,
        child: FloatingActionButton(
          onPressed: () {
            // You can scroll to top or open the search
          },
          tooltip: 'Search',
          backgroundColor: Theme.of(context).primaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
          ),
          child: const Icon(Icons.search, color: Colors.white, size: 35),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}
