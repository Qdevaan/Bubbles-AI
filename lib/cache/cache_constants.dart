class CacheKeys {
  static String userProfile(String uid)       => 'user:$uid:profile';
  static String userSettings(String uid)      => 'user:$uid:settings';
  static const String appSettings             =  'app:settings';
  static String homeEvents(String uid)        => 'user:$uid:home:events';
  static String homeHighlights(String uid)    => 'user:$uid:home:highlights';
  static String homeNotifications(String uid) => 'user:$uid:home:notifications';
  static String insightsEvents(String uid)    => 'user:$uid:insights:events';
  static String insightsHighlights(String uid)=> 'user:$uid:insights:highlights';
  static String insightsNotifications(String uid) => 'user:$uid:insights:notifications';
  static String graphExport(String uid)       => 'user:$uid:graph:export';
  static String entities(String uid)          => 'user:$uid:entities';
  static String gamification(String uid)      => 'user:$uid:gamification';
  static String quests(String uid)            => 'user:$uid:quests';
  static String performance(String uid)       => 'user:$uid:performance';
  static String consultantSessions(String uid) => 'user:$uid:sessions:consultant';
  static String liveSessions(String uid)       => 'user:$uid:sessions:live';
  static String sessionLogs(String sessionId) => 'session:$sessionId:logs';
  static String sessionAnalytics(String sessionId) => 'session:$sessionId:analytics';
  static String coachingReport(String sessionId) => 'session:$sessionId:report';
}

class CacheTtl {
  static const Duration profile          = Duration(hours: 24);
  static const Duration homeEvents       = Duration(minutes: 5);
  static const Duration homeHighlights   = Duration(minutes: 5);
  static const Duration homeNotifications = Duration(minutes: 5);
  static const Duration insights         = Duration(minutes: 10);
  static const Duration graphExport      = Duration(minutes: 15);
  static const Duration entities         = Duration(minutes: 15);
  static const Duration gamification     = Duration(minutes: 5);
  static const Duration quests           = Duration(minutes: 5);
  static const Duration performance      = Duration(minutes: 30);
  static const Duration sessions         = Duration(minutes: 10);
  static const Duration sessionLogs      = Duration(hours: 1);
}

class CacheSchemaVersion {
  static const int profile       = 1;
  static const int settings      = 1;
  static const int home          = 1;
  static const int insights      = 1;
  static const int graph         = 1;
  static const int entities      = 1;
  static const int gamification  = 1;
  static const int sessions      = 1;
}
