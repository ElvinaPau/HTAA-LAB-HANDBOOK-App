import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '/api_config.dart';
import 'package:htaa_app/services/cache_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:htaa_app/services/connectivity_service.dart';

class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key});

  @override
  _ContactScreenState createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  final CacheService _cacheService = CacheService();

  List<Map<String, dynamic>> contacts = [];
  bool isLoading = true;
  String? errorMessage;
  bool _isOfflineMode = false;

  // Top message state
  String? topMessage;
  Color? topMessageColor;

  // Cache configuration
  static const String _cacheBoxName = 'contactsBox';
  static const String _contactsCacheKey = 'contacts';

  // Connectivity
  late final StreamSubscription<ConnectivityResult> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    fetchContacts();

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

  Future<void> fetchContacts() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
      _isOfflineMode = false;
    });

    try {
      final response = await http
          .get(
            Uri.parse('${getBaseUrl()}/api/contacts'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception('Request timed out.'),
          );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        final contactsList = List<Map<String, dynamic>>.from(data);

        // Save to cache
        await _cacheService.saveData(
          _cacheBoxName,
          _contactsCacheKey,
          contactsList,
        );

        setState(() {
          contacts = contactsList;
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
      _contactsCacheKey,
      defaultValue: null,
      maxAge: const Duration(hours: 24),
    );

    if (cachedData != null && cachedData is List) {
      setState(() {
        contacts = List<Map<String, dynamic>>.from(
          cachedData.map((item) => Map<String, dynamic>.from(item)),
        );
        isLoading = false;
        _isOfflineMode = true;
        errorMessage = null;
      });

      showTopMessage(
        'You are offline. Contact cannot be refreshed.',
        color: Colors.orange,
      );
    } else {
      setState(() {
        contacts = [];
        isLoading = false;
        _isOfflineMode = false;
        errorMessage = 'No data available. Please check your connection.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Contact Information'),
            if (_isOfflineMode) ...[
              const SizedBox(width: 6),
              Icon(Icons.cloud_off, size: 18, color: Colors.orange[700]),
            ],
          ],
        ),
        centerTitle: true,
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
            child:
                isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : errorMessage != null
                    ? _buildErrorView()
                    : contacts.isEmpty
                    ? _buildEmptyView()
                    : RefreshIndicator(
                      onRefresh: fetchContacts,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        itemCount: contacts.length,
                        itemBuilder: (context, index) {
                          final contact = contacts[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 16),
                            elevation: 3,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Title
                                  Text(
                                    contact['title'] ?? 'No title',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  // Description (HTML)
                                  Html(
                                    data:
                                        contact['description'] ??
                                        '<p>No description</p>',
                                    style: {
                                      "body": Style(
                                        margin: Margins.zero,
                                        padding: HtmlPaddings.zero,
                                        fontSize: FontSize(14),
                                        lineHeight: LineHeight(1.4),
                                      ),
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() => RefreshIndicator(
    onRefresh: fetchContacts,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height - 200,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.contact_mail_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Contacts Found',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'There are no contact information available at the moment.',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildErrorView() => RefreshIndicator(
    onRefresh: fetchContacts,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height - 200,
          child: Center(
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
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
