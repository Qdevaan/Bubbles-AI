import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/design_tokens.dart';

class RoleplaySetupScreen extends StatefulWidget {
  const RoleplaySetupScreen({super.key});

  @override
  State<RoleplaySetupScreen> createState() => _RoleplaySetupScreenState();
}

class _RoleplaySetupScreenState extends State<RoleplaySetupScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _entities = [];
  bool _isLoading = true;
  String? _selectedEntityId;
  String? _selectedEntityName;

  @override
  void initState() {
    super.initState();
    _fetchEntities();
  }

  Future<void> _fetchEntities() async {
    try {
      final res = await _supabase
          .from('entities')
          .select('id, display_name, entity_type')
          .order('display_name');
      if (mounted) {
        setState(() {
          _entities = List<Map<String, dynamic>>.from(res);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        
        String errStr = e.toString().toLowerCase();
        String displayMsg = 'Failed to load entities: $e';
        if (errStr.contains('socketexception') || errStr.contains('failed host lookup') || errStr.contains('clientexception')) {
          displayMsg = 'Network is unreachable. Please check your internet connection.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(displayMsg)),
        );
      }
    }
  }

  void _startRoleplay() {
    if (_selectedEntityId == null) return;
    context.push('/new-session', extra: {
      'targetEntityId': _selectedEntityId,
      'targetEntityName': _selectedEntityName,
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Roleplay Setup',
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : AppColors.slate900,
          ),
        ),
        iconTheme: IconThemeData(
          color: isDark ? Colors.white : AppColors.slate900,
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Choose a Character',
                      style: GoogleFonts.manrope(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : AppColors.slate900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Select an entity to act as your conversation partner. The AI will adopt their persona based on known facts.',
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        color: isDark ? AppColors.slate400 : AppColors.slate600,
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (_entities.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.surfaceDark : Colors.white,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(
                            color: isDark ? AppColors.glassBorder : Colors.grey.shade200,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'No entities found. Add entities from the Knowledge Base first.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.manrope(
                              color: isDark ? AppColors.slate400 : AppColors.slate600,
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.surfaceDark : Colors.white,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(
                            color: isDark ? AppColors.glassBorder : Colors.grey.shade300,
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedEntityId,
                            isExpanded: true,
                            hint: Text(
                              'Select an entity...',
                              style: GoogleFonts.manrope(
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                            ),
                            dropdownColor: isDark ? AppColors.backgroundDark : Colors.white,
                            items: _entities.map((e) {
                              return DropdownMenuItem<String>(
                                value: e['id'].toString(),
                                child: Text(
                                  '${e['display_name']} (${e['entity_type']})',
                                  style: GoogleFonts.manrope(
                                    color: isDark ? Colors.white : AppColors.slate900,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedEntityId = val;
                                  _selectedEntityName = _entities.firstWhere((e) => e['id'].toString() == val)['display_name'];
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    const Spacer(),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                        ),
                      ),
                      onPressed: _selectedEntityId == null ? null : _startRoleplay,
                      child: Text(
                        'Start Roleplay',
                        style: GoogleFonts.manrope(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
