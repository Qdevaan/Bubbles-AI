class SubscriptionTier {
  final String id;
  final String userId;
  final String? stripeCustomerId;
  final String? stripeSubscriptionId;
  final String planId;
  final String status;
  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final bool cancelAtPeriodEnd;
  final DateTime createdAt;
  final DateTime updatedAt;

  SubscriptionTier({
    required this.id,
    required this.userId,
    this.stripeCustomerId,
    this.stripeSubscriptionId,
    required this.planId,
    required this.status,
    this.currentPeriodStart,
    this.currentPeriodEnd,
    this.cancelAtPeriodEnd = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SubscriptionTier.fromJson(Map<String, dynamic> json) {
    return SubscriptionTier(
      id: json['id'],
      userId: json['user_id'],
      stripeCustomerId: json['stripe_customer_id'],
      stripeSubscriptionId: json['stripe_subscription_id'],
      planId: json['plan_id'],
      status: json['status'],
      currentPeriodStart: json['current_period_start'] != null
          ? DateTime.parse(json['current_period_start'])
          : null,
      currentPeriodEnd: json['current_period_end'] != null
          ? DateTime.parse(json['current_period_end'])
          : null,
      cancelAtPeriodEnd: json['cancel_at_period_end'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }
}

class Integration {
  final String id;
  final String userId;
  final String provider;
  final bool isActive;
  final String syncStatus;
  final DateTime? expiresAt;

  Integration({
    required this.id,
    required this.userId,
    required this.provider,
    this.isActive = true,
    this.syncStatus = 'ok',
    this.expiresAt,
  });

  factory Integration.fromJson(Map<String, dynamic> json) {
    return Integration(
      id: json['id'],
      userId: json['user_id'],
      provider: json['provider'],
      isActive: json['is_active'] ?? true,
      syncStatus: json['sync_status'] ?? 'ok',
      expiresAt: json['expires_at'] != null ? DateTime.parse(json['expires_at']) : null,
    );
  }
}

class TeamWorkspace {
  final String id;
  final String ownerId;
  final String name;
  final String? domain;
  final String? billingEmail;
  final bool enterpriseTier;
  final bool ssoEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  TeamWorkspace({
    required this.id,
    required this.ownerId,
    required this.name,
    this.domain,
    this.billingEmail,
    this.enterpriseTier = false,
    this.ssoEnabled = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TeamWorkspace.fromJson(Map<String, dynamic> json) {
    return TeamWorkspace(
      id: json['id'],
      ownerId: json['owner_id'],
      name: json['name'],
      domain: json['domain'],
      billingEmail: json['billing_email'],
      enterpriseTier: json['enterprise_tier'] ?? false,
      ssoEnabled: json['sso_enabled'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }
}
