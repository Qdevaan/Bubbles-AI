import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'package:provider/provider.dart';

class QuestsScreen extends StatefulWidget {
  const QuestsScreen({super.key});

  @override
  State<QuestsScreen> createState() => _QuestsScreenState();
}

class _QuestsScreenState extends State<QuestsScreen> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _gamification;
  List<dynamic> _quests = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    final api = context.read<ApiService>();
    final userId = AuthService.instance.currentUser?.id ?? '';
    if (userId.isEmpty) {
      if (mounted) {
        setState(() {
          _error = 'User not logged in';
          _isLoading = false;
        });
      }
      return;
    }
    try {
      // Assuming api.getGamification() and api.getQuests() exist,
      // but if not implement them in apiservice or make a direct http call.
      // We will make a direct fetch here if ApiService doesn't have it yet.
      final gamification = await api.getGamification(userId);
      final questsRes = await api.getQuests(userId);
      
      if (mounted) {
        setState(() {
          _gamification = gamification;
          _quests = questsRes?['quests'] ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load gamification data';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Quests & XP', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildProfileHeader(theme, isDark),
                    const SizedBox(height: 24),
                    Text(
                      'Daily Quests',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    ..._quests.map((q) => _buildQuestCard(theme, q)),
                  ],
                ),
    );
  }

  Widget _buildProfileHeader(ThemeData theme, bool isDark) {
    int xp = _gamification?['xp'] ?? 0;
    int level = _gamification?['level'] ?? 1;
    List<dynamic> badges = _gamification?['badges'] ?? [];

    // Calculate progress to next level (mock logic: 100 XP per level)
    int currentLevelBaseXp = (level - 1) * 100;
    int nextLevelBaseXp = level * 100;
    double progress = (xp - currentLevelBaseXp) / (nextLevelBaseXp - currentLevelBaseXp);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.primary.withAlpha(50)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Level $level', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withAlpha(40),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$xp XP', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 12,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerRight,
            child: Text('Next level at 100 XP increment', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ),
          if (badges.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Badges Earned', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: badges.map((b) => Chip(
                label: Text(b.toString()),
                backgroundColor: Colors.amber.withAlpha(50),
              )).toList(),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildQuestCard(ThemeData theme, dynamic q) {
    String title = q['title'] ?? 'Unknown Quest';
    int xpReward = q['xp_reward'] ?? 0;
    int target = q['target'] ?? 1;
    int progress = q['progress'] ?? 0;
    bool isCompleted = q['is_completed'] ?? false;
    if (progress > target) progress = target;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isCompleted ? theme.colorScheme.primaryContainer.withAlpha(50) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isCompleted ? Colors.green.withAlpha(40) : Colors.orange.withAlpha(40),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isCompleted ? Icons.check_circle : Icons.star,
                color: isCompleted ? Colors.green : Colors.orange,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('+$xpReward XP', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Text('$progress / $target', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
