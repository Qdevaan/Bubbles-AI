class Profile {
  final String id;
  final String? fullName;
  final String? avatarUrl;
  final DateTime? dob;
  final String? gender;
  final String? country;
  final String locale;
  final String timezone;
  final String? occupation;
  final String? company;
  final String? bio;
  final bool isDeveloper;
  final DateTime createdAt;
  final DateTime updatedAt;

  Profile({
    required this.id,
    this.fullName,
    this.avatarUrl,
    this.dob,
    this.gender,
    this.country,
    this.locale = 'en_US',
    this.timezone = 'UTC',
    this.occupation,
    this.company,
    this.bio,
    this.isDeveloper = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'],
      fullName: json['full_name'],
      avatarUrl: json['avatar_url'],
      dob: json['dob'] != null ? DateTime.parse(json['dob']) : null,
      gender: json['gender'],
      country: json['country'],
      locale: json['locale'] ?? 'en_US',
      timezone: json['timezone'] ?? 'UTC',
      occupation: json['occupation'],
      company: json['company'],
      bio: json['bio'],
      isDeveloper: json['is_developer'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'avatar_url': avatarUrl,
      'dob': dob?.toIso8601String()?.split('T').first,
      'gender': gender,
      'country': country,
      'locale': locale,
      'timezone': timezone,
      'occupation': occupation,
      'company': company,
      'bio': bio,
      'is_developer': isDeveloper,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class UserSettings {
  final String userId;
  final String theme;
  final String? accentColor;
  final String fontSize;
  final String voiceAssistantName;
  final String assistantPersona;
  final String? assistantVoiceId;
  final double speechRate;
  final double pitch;
  final bool hapticFeedback;
  final bool autoPlayAudio;
  final String transcriptionLanguage;
  final bool enableNsfwFilter;
  final bool dataSharingOptIn;
  final DateTime updatedAt;

  UserSettings({
    required this.userId,
    this.theme = 'system',
    this.accentColor,
    this.fontSize = 'medium',
    this.voiceAssistantName = 'Bubbles',
    this.assistantPersona = 'friendly',
    this.assistantVoiceId,
    this.speechRate = 1.0,
    this.pitch = 1.0,
    this.hapticFeedback = true,
    this.autoPlayAudio = true,
    this.transcriptionLanguage = 'en-US',
    this.enableNsfwFilter = true,
    this.dataSharingOptIn = false,
    required this.updatedAt,
  });

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    return UserSettings(
      userId: json['user_id'],
      theme: json['theme'] ?? 'system',
      accentColor: json['accent_color'],
      fontSize: json['font_size'] ?? 'medium',
      voiceAssistantName: json['voice_assistant_name'] ?? 'Bubbles',
      assistantPersona: json['assistant_persona'] ?? 'friendly',
      assistantVoiceId: json['assistant_voice_id'],
      speechRate: (json['speech_rate'] ?? 1.0).toDouble(),
      pitch: (json['pitch'] ?? 1.0).toDouble(),
      hapticFeedback: json['haptic_feedback'] ?? true,
      autoPlayAudio: json['auto_play_audio'] ?? true,
      transcriptionLanguage: json['transcription_language'] ?? 'en-US',
      enableNsfwFilter: json['enable_nsfw_filter'] ?? true,
      dataSharingOptIn: json['data_sharing_opt_in'] ?? false,
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'theme': theme,
      'accent_color': accentColor,
      'font_size': fontSize,
      'voice_assistant_name': voiceAssistantName,
      'assistant_persona': assistantPersona,
      'assistant_voice_id': assistantVoiceId,
      'speech_rate': speechRate,
      'pitch': pitch,
      'haptic_feedback': hapticFeedback,
      'auto_play_audio': autoPlayAudio,
      'transcription_language': transcriptionLanguage,
      'enable_nsfw_filter': enableNsfwFilter,
      'data_sharing_opt_in': dataSharingOptIn,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
