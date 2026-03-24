class HealthMetric {
  final String id;
  final String userId;
  final String metricType;
  final double? metricValue;
  final String? metricUnit;
  final DateTime recordedAt;
  final String source;

  HealthMetric({
    required this.id,
    required this.userId,
    required this.metricType,
    this.metricValue,
    this.metricUnit,
    required this.recordedAt,
    this.source = 'manual',
  });

  factory HealthMetric.fromJson(Map<String, dynamic> json) {
    return HealthMetric(
      id: json['id'],
      userId: json['user_id'],
      metricType: json['metric_type'],
      metricValue: json['metric_value']?.toDouble(),
      metricUnit: json['metric_unit'],
      recordedAt: DateTime.parse(json['recorded_at']),
      source: json['source'] ?? 'manual',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'metric_type': metricType,
      'metric_value': metricValue,
      'metric_unit': metricUnit,
      'recorded_at': recordedAt.toIso8601String(),
      'source': source,
    };
  }
}

class Expense {
  final String id;
  final String userId;
  final double amount;
  final String currency;
  final String? category;
  final String? merchant;
  final DateTime date;
  final String? receiptUrl;
  final bool isRecurring;
  final String? notes;

  Expense({
    required this.id,
    required this.userId,
    required this.amount,
    this.currency = 'USD',
    this.category,
    this.merchant,
    required this.date,
    this.receiptUrl,
    this.isRecurring = false,
    this.notes,
  });

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      id: json['id'],
      userId: json['user_id'],
      amount: (json['amount'] ?? 0).toDouble(),
      currency: json['currency'] ?? 'USD',
      category: json['category'],
      merchant: json['merchant'],
      date: DateTime.parse(json['date']),
      receiptUrl: json['receipt_url'],
      isRecurring: json['is_recurring'] ?? false,
      notes: json['notes'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'amount': amount,
      'currency': currency,
      'category': category,
      'merchant': merchant,
      'date': date.toIso8601String(),
      'receipt_url': receiptUrl,
      'is_recurring': isRecurring,
      'notes': notes,
    };
  }
}
