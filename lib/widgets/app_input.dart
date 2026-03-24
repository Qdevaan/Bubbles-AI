import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/design_tokens.dart';

class AppInput extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData? prefixIcon;
  final TextInputType type;
  final bool obscure;
  final String? Function(String?)? validator;
  final String? hintText;
  final bool readOnly;
  final VoidCallback? onTap;
  final IconData? suffixIcon;

  const AppInput({
    super.key,
    required this.controller,
    required this.label,
    this.prefixIcon,
    this.type = TextInputType.text,
    this.obscure = false,
    this.validator,
    this.hintText,
    this.readOnly = false,
    this.onTap,
    this.suffixIcon,
  });

  @override
  State<AppInput> createState() => _AppInputState();
}

class _AppInputState extends State<AppInput> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPassword = widget.obscure;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              widget.label.toUpperCase(),
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: isDark ? AppColors.slate400 : AppColors.slate500,
              ),
            ),
          ),
        TextFormField(
          controller: widget.controller,
          keyboardType: widget.type,
          obscureText: isPassword ? _hidden : false,
          validator: widget.validator,
          readOnly: widget.readOnly,
          onTap: widget.onTap,
          style: GoogleFonts.manrope(
            fontSize: 15,
            color: isDark ? Colors.white : AppColors.slate900,
          ),
          decoration: InputDecoration(
            hintText: widget.hintText ?? 'Enter ${widget.label.toLowerCase()}',
            hintStyle: GoogleFonts.manrope(
              fontSize: 15,
              color: isDark ? AppColors.slate500 : AppColors.slate400,
            ),
            prefixIcon: widget.prefixIcon != null
                ? Icon(
                    widget.prefixIcon,
                    size: 20,
                    color: AppColors.slate400,
                  )
                : null,
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(
                      _hidden ? Icons.visibility_off : Icons.visibility,
                      size: 20,
                      color: AppColors.slate400,
                    ),
                    onPressed: () => setState(() => _hidden = !_hidden),
                  )
                : (widget.suffixIcon != null
                      ? Icon(widget.suffixIcon, size: 20, color: AppColors.slate400)
                      : null),
            filled: true,
            fillColor: isDark ? AppColors.glassInput : Colors.white.withAlpha(200),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              borderSide: BorderSide(
                color: isDark ? AppColors.glassBorder : AppColors.slate200,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              borderSide: BorderSide(
                color: isDark ? AppColors.glassBorder : AppColors.slate200,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              borderSide: const BorderSide(color: AppColors.error),
            ),
          ),
        ),
      ],
    );
  }
}
