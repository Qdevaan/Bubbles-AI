// Purpose: Thumbs-up/down and star rating dialog — shown after a session turn for per-message feedback collection.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../theme/design_tokens.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'app_dialog.dart';

class FeedbackDialog extends StatefulWidget {
  final String? sessionId;

  const FeedbackDialog({super.key, this.sessionId});

  static Future<void> show(BuildContext context, {String? sessionId}) {
    return AppDialog.show<void>(
      context: context,
      title: 'How was your session?',
      subtitle: 'Your feedback helps AI improve its future responses.',
      icon: Icons.stars_rounded,
      tone: AppDialogTone.info,
      content: FeedbackDialog(sessionId: sessionId),
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
        Navigator.pop(context);
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            return IconButton(
              onPressed: () => setState(() => _selectedRating = index + 1),
              icon: Icon(
                index < _selectedRating
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                color: AppColors.warning,
                size: 32,
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
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
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed:
                    _isSubmitting ? null : () => Navigator.pop(context),
                child: Text(
                  'Skip',
                  style: GoogleFonts.manrope(
                    color:
                        isDark ? AppColors.slate400 : AppColors.slate600,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _isSubmitting ? null : _submitFeedback,
                style: FilledButton.styleFrom(
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
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
