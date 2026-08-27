class BrowserTab {
  BrowserTab({
    required this.id,
    this.url = 'https://www.google.com',
    this.title = '新标签页',
    this.isIncognito = false,
    this.isLoading = false,
    this.canGoBack = false,
    this.canGoForward = false,
  });

  final String id;
  String url;
  String title;
  bool isIncognito;
  bool isLoading;
  bool canGoBack;
  bool canGoForward;
}

class BookmarkItem {
  BookmarkItem({
    required this.id,
    required this.title,
    required this.url,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  String title;
  String url;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'createdAt': createdAt.toIso8601String(),
      };

  factory BookmarkItem.fromJson(Map<String, dynamic> j) => BookmarkItem(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        url: j['url'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

class HistoryItem {
  HistoryItem({
    required this.id,
    required this.title,
    required this.url,
    DateTime? visitedAt,
  }) : visitedAt = visitedAt ?? DateTime.now();

  final String id;
  final String title;
  final String url;
  final DateTime visitedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'visitedAt': visitedAt.toIso8601String(),
      };

  factory HistoryItem.fromJson(Map<String, dynamic> j) => HistoryItem(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        url: j['url'] as String? ?? '',
        visitedAt: DateTime.tryParse(j['visitedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

class ConsoleLog {
  ConsoleLog({
    required this.level,
    required this.message,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  final String level;
  final String message;
  final DateTime time;
}
