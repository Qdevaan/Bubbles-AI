import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../theme/design_tokens.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class FeedbackDialog extends StatefulWidget {
  final String? sessionId;

  const FeedbackDialog({super.key, this.sessionId});

  static Future<void> show(BuildContext context, {String? sessionId}) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Feedback',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => FeedbackDialog(sessionId: sessionId),
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(opacity: anim1, child: child);
      },
    );
  }

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  int _selectedRating = 0;
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmitting = false;

  Future<void> _submitFeedback() async {
    if (_selectedRating == 0 && _commentController.text.trim().isEmpty) {
      Navigator.pop(context);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = AuthService.instance.currentUser;
      if (user != null) {
        // We use Provider since it's likely already in the widget tree,
        // but since we might be out of the original context (via showGeneralDialog),
        // we'll pass it if possible, otherwise construct a new one. 
        final api = Provider.of<ApiService>(context, listen: false);
        
        await api.saveFeedback(
          userId: user.id,
          sessionId: widget.sessionId,
          feedbackType: 'star',
          value: _selectedRating,
          comment: _commentController.text.trim(),
        );
      }
    } catch (e) {
      debugPrint("Failed to save feedback: $e");
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
        Navigator.pop(context); // close dialog
      }
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.85,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0D1B1F).withAlpha(240) : Colors.white.withAlpha(240),
            borderRadius: BorderRadius.circular(AppRadius.xxl),
            border: Border.all(
              color: isDark ? AppColors.glassBorder : Colors.grey.shade300,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(20),
                blurRadius: 30,
                spreadRadius: 5,
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.stars_rounded,
                size: 48,
                color: AppColors.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'How was your session?',
                style: GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : AppColors.slate900,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Your feedback helps AI improve its future responses.',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  color: isDark ? AppColors.slate400 : AppColors.slate500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    onPressed: () {
                      setState(() {
                        _selectedRating = index + 1;
                      });
                    },
                    icon: Icon(
                      index < _selectedRating ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: AppColors.warning,
                      size: 32,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _commentController,
                maxLines: 3,
                style: GoogleFonts.manrope(
                  color: isDark ? Colors.white : AppColors.slate900,
                ),
                decoration: InputDecoration(
                  hintText: 'Any specific feedback? (Optional)',
                  hintStyle: GoogleFonts.manrope(
                    color: isDark ? AppColors.slate500 : Colors.grey.shade400,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                      child: Text(
                        'Skip',
                        style: GoogleFonts.manrope(
                          color: isDark ? AppColors.slate400 : AppColors.slate600,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isSubmitting ? null : _submitFeedback,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Submit',
                              style: GoogleFonts.manrope(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
