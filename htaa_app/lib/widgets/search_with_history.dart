import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class SearchHistoryItem {
  final String id;
  final String name;
  final int timestamp;

  SearchHistoryItem({
    required this.id,
    required this.name,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'timestamp': timestamp,
  };

  factory SearchHistoryItem.fromJson(Map<String, dynamic> json) {
    return SearchHistoryItem(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      timestamp: json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class SearchWithHistory extends StatefulWidget {
  final String hintText;
  final String historyKey;
  final Function(String) onSearch;
  final Function(SearchHistoryItem)? onHistoryItemTap;
  final TextEditingController controller;
  final FocusNode focusNode;

  const SearchWithHistory({
    super.key,
    required this.hintText,
    required this.historyKey,
    required this.onSearch,
    this.onHistoryItemTap,
    required this.controller,
    required this.focusNode,
  });

  @override
  State<SearchWithHistory> createState() => SearchWithHistoryState();
}

class SearchWithHistoryState extends State<SearchWithHistory> {
  List<SearchHistoryItem> _searchHistory = [];
  bool _isFocused = false;
  final int _historyExpiryDays = 7;
  final int _maxHistoryItems = 10;

  @override
  void initState() {
    super.initState();
    _loadSearchHistory();
    widget.focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusChange);
    super.dispose();
  }

  void _handleFocusChange() {
    setState(() {
      _isFocused = widget.focusNode.hasFocus;
    });
  }

  Future<void> _loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString(widget.historyKey);

    if (historyJson != null) {
      try {
        final List<dynamic> decoded = json.decode(historyJson);
        final now = DateTime.now().millisecondsSinceEpoch;
        final expiryTime = _historyExpiryDays * 24 * 60 * 60 * 1000;

        final filtered =
            decoded
                .map((item) => SearchHistoryItem.fromJson(item))
                .where((item) => now - item.timestamp < expiryTime)
                .toList();

        setState(() {
          _searchHistory = filtered;
        });

        // Save filtered history back if items were removed
        if (filtered.length != decoded.length) {
          await _saveSearchHistory();
        }
      } catch (e) {
        print('Error loading search history: $e');
      }
    }
  }

  Future<void> _saveSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = json.encode(
      _searchHistory.map((item) => item.toJson()).toList(),
    );
    await prefs.setString(widget.historyKey, historyJson);
  }

  Future<void> addToHistory(String id, String name) async {
    final newItem = SearchHistoryItem(
      id: id,
      name: name,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    setState(() {
      _searchHistory.removeWhere((item) => item.id == id);
      _searchHistory.insert(0, newItem);
      if (_searchHistory.length > _maxHistoryItems) {
        _searchHistory = _searchHistory.sublist(0, _maxHistoryItems);
      }
    });

    await _saveSearchHistory();
  }

  Future<void> _deleteHistoryItem(String id) async {
    setState(() {
      _searchHistory.removeWhere((item) => item.id == id);
    });
    await _saveSearchHistory();
  }

  Future<void> _clearAllHistory() async {
    setState(() {
      _searchHistory.clear();
    });
    await _saveSearchHistory();
  }

  String _getTimeAgo(int timestamp) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final diff = now - timestamp;
    final minutes = (diff / 60000).floor();
    final hours = (diff / 3600000).floor();
    final days = (diff / 86400000).floor();

    if (minutes < 1) return 'Just now';
    if (minutes < 60) return '${minutes}m ago';
    if (hours < 24) return '${hours}h ago';
    return '${days}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final searchText = widget.controller.text.toLowerCase();
    final filteredHistory =
        _searchHistory
            .where((item) => item.name.toLowerCase().contains(searchText))
            .toList();
    final showHistory = _isFocused && filteredHistory.isNotEmpty;

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius:
                showHistory
                    ? const BorderRadius.only(
                      topLeft: Radius.circular(25),
                      topRight: Radius.circular(25),
                    )
                    : BorderRadius.circular(25),
            boxShadow: null,
          ),
          child: SizedBox(
            height: 50,
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              decoration: InputDecoration(
                hintText: widget.hintText,
                prefixIcon: const Icon(Icons.search),
                suffixIcon:
                    widget.controller.text.isNotEmpty
                        ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            widget.controller.clear();
                            widget.onSearch('');
                          },
                        )
                        : null,
                filled: true,
                fillColor: Colors.grey[100],
                enabledBorder: OutlineInputBorder(
                  borderRadius:
                      showHistory
                          ? const BorderRadius.only(
                            topLeft: Radius.circular(25),
                            topRight: Radius.circular(25),
                            bottomLeft: Radius.circular(0),
                            bottomRight: Radius.circular(0),
                          )
                          : BorderRadius.circular(25),

                  borderSide: const BorderSide(color: Colors.grey, width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius:
                      showHistory
                          ? const BorderRadius.only(
                            topLeft: Radius.circular(25),
                            topRight: Radius.circular(25),
                            bottomLeft: Radius.circular(0),
                            bottomRight: Radius.circular(0),
                          )
                          : BorderRadius.circular(25),

                  borderSide: BorderSide(
                    color: Theme.of(context).primaryColor,
                    width: 2.0,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 12.0,
                  horizontal: 20.0,
                ),
              ),
              onChanged: widget.onSearch,
            ),
          ),
        ),
        if (showHistory)
          Transform.translate(
            offset: const Offset(0, -2),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                border: Border(
                  top: BorderSide.none,
                  left: BorderSide(
                    color: Theme.of(context).primaryColor,
                    width: 2,
                  ),
                  right: BorderSide(
                    color: Theme.of(context).primaryColor,
                    width: 2,
                  ),
                  bottom: BorderSide(
                    color: Theme.of(context).primaryColor,
                    width: 2,
                  ),
                ),

                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              constraints: const BoxConstraints(maxHeight: 300),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Recent Searches',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                        TextButton(
                          onPressed: _clearAllHistory,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'Clear All',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red[400],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: filteredHistory.length,
                      itemBuilder: (context, index) {
                        final item = filteredHistory[index];
                        return InkWell(
                          onTap: () {
                            if (widget.onHistoryItemTap != null) {
                              widget.onHistoryItemTap!(item);
                            }
                            widget.focusNode.unfocus();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 2,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.history,
                                  size: 18,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    item.name,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.close,
                                    size: 18,
                                    color: Colors.grey[400],
                                  ),
                                  onPressed: () => _deleteHistoryItem(item.id),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
