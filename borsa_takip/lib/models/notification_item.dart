class NotificationItem {
  final String id;
  final String symbol;
  final double price;
  final String currency;
  final DateTime date;
  final DateTime createdAt;
  final String message;

  const NotificationItem({
    required this.id,
    required this.symbol,
    required this.price,
    required this.currency,
    required this.date,
    required this.createdAt,
    required this.message,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id'] as String,
      symbol: json['symbol'] as String,
      price: (json['price'] as num).toDouble(),
      currency: json['currency'] as String? ?? '',
      date: DateTime.parse(json['date'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      message: json['message'] as String,
    );
  }
}

class NotificationPage {
  final List<NotificationItem> notifications;
  final int page;
  final int totalPages;
  final int total;

  const NotificationPage({
    required this.notifications,
    required this.page,
    required this.totalPages,
    required this.total,
  });

  factory NotificationPage.fromJson(Map<String, dynamic> json) {
    final list = (json['notifications'] as List)
        .cast<Map<String, dynamic>>()
        .map(NotificationItem.fromJson)
        .toList();
    return NotificationPage(
      notifications: list,
      page: json['page'] as int,
      totalPages: json['totalPages'] as int,
      total: json['total'] as int,
    );
  }
}
