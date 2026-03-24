import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../theme/design_tokens.dart';
import '../services/connection_service.dart';

class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key});
  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  final _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final service = Provider.of<ConnectionService>(context, listen: false);
      _urlController.text = service.serverUrl;
    });
  }

  void _saveAndTest() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    final service = Provider.of<ConnectionService>(context, listen: false);
    await service.saveUrl(url);

    if (mounted) {
      if (service.isConnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Connected to Brain!"),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("❌ Connection Failed. Check URL."),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final connectionService = Provider.of<ConnectionService>(context);
    final isConnected = connectionService.isConnected;
    final isConnecting =
        connectionService.status == ConnectionStatus.connecting;
    final primary = Theme.of(context).colorScheme.primary;
    final serverUrl = connectionService.serverUrl;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      body: Stack(
        children: [
          if (isDark) ...[
            Positioned(
              top: -120,
              left: -120,
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Theme.of(context).colorScheme.primary.withAlpha(38), Colors.transparent],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -120,
              right: -120,
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Theme.of(context).colorScheme.primary.withAlpha(26), Colors.transparent],
                  ),
                ),
              ),
            ),
          ],
          SafeArea(
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color: isDark
                        ? AppColors.glassBorder
                        : AppColors.slate200,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.arrow_back_rounded,
                        color: isDark ? Colors.white : AppColors.slate900,
                      ),
                    ),
                    Text(
                      'Brain Connection',
                      style: GoogleFonts.manrope(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : AppColors.slate900,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // -- Content ------------------------------------------------
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),

                    // -- Status Card (matches HTML centered layout with glow) --
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.glassWhite
                            : Colors.white,
                        borderRadius: BorderRadius.circular(AppRadius.xxl),
                        border: Border.all(
                          color: isDark
                              ? AppColors.glassBorder
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: Column(
                        children: [
                          // Icon with glow
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              // Glow blur behind icon
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isConnected
                                      ? AppColors.success.withAlpha(38)
                                      : AppColors.error.withAlpha(26),
                                ),
                              ),
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isConnected
                                      ? AppColors.success.withAlpha(26)
                                      : AppColors.error.withAlpha(20),
                                  border: Border.all(
                                    color: isConnected
                                        ? AppColors.success
                                        : AppColors.error,
                                    width: 2,
                                  ),
                                ),
                                child: Icon(
                                  isConnected
                                      ? Icons.wifi_rounded
                                      : Icons.wifi_off_rounded,
                                  color: isConnected
                                      ? AppColors.success
                                      : AppColors.error,
                                  size: 36,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            isConnected
                                ? 'Connected to Brain'
                                : 'Not Connected',
                            style: GoogleFonts.manrope(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? Colors.white
                                  : AppColors.slate900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (isConnected && serverUrl.isNotEmpty)
                            Text(
                              serverUrl,
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: primary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          const SizedBox(height: 12),
                          // Status badge with pulse dot
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isConnected
                                  ? AppColors.success.withAlpha(26)
                                  : AppColors.error.withAlpha(26),
                              borderRadius: BorderRadius.circular(
                                AppRadius.full,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isConnected)
                                  _PulseDot(color: AppColors.success)
                                else
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColors.error,
                                    ),
                                  ),
                                const SizedBox(width: 6),
                                Text(
                                  isConnected
                                      ? 'Status: Active'
                                      : 'Status: Offline',
                                  style: GoogleFonts.manrope(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isConnected
                                        ? AppColors.success
                                        : AppColors.error,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Disconnect / Connect button
                          if (isConnected)
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () async {
                                  await connectionService.saveUrl('');
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.error,
                                  side: const BorderSide(
                                    color: AppColors.error,
                                    width: 1.5,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.lg,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  'Disconnect',
                                  style: GoogleFonts.manrope(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // -- Server URL Input -------------------------------
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'Server URL',
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.slate400
                              : AppColors.slate500,
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.glassWhite
                            : Colors.white,
                        borderRadius: BorderRadius.circular(AppRadius.xxl),
                        border: Border.all(
                          color: isDark
                              ? AppColors.glassBorder
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 16),
                          Icon(
                            Icons.dns_rounded,
                            color: isDark
                                ? AppColors.slate500
                                : AppColors.slate400,
                            size: 20,
                          ),
                          Expanded(
                            child: TextField(
                              controller: _urlController,
                              style: GoogleFonts.manrope(
                                fontSize: 14,
                                color: isDark
                                    ? Colors.white
                                    : AppColors.slate900,
                              ),
                              decoration: InputDecoration(
                                hintText: 'http://192.168.x.x:8000',
                                hintStyle: GoogleFonts.manrope(
                                  color: isDark
                                      ? AppColors.slate600
                                      : AppColors.slate400,
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 16,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.content_paste_rounded,
                              color: isDark
                                  ? AppColors.slate500
                                  : AppColors.slate400,
                              size: 20,
                            ),
                            tooltip: 'Paste from clipboard',
                            onPressed: () async {
                              final data = await Clipboard.getData(Clipboard.kTextPlain);
                              if (data?.text != null && data!.text!.isNotEmpty) {
                                _urlController.text = data.text!;
                              }
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // -- 1-column action button ----
                    Row(
                      children: [
                        Expanded(
                          child: _ActionButton(
                            isDark: isDark,
                            icon: Icons.network_check_rounded,
                            label: 'Test Connection',
                            loading: isConnecting,
                            onTap: isConnecting ? null : _saveAndTest,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // -- How to connect? Collapsible section ------------
                    _HowToConnectSection(isDark: isDark, primary: primary),

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
        ],
      ),
    );
  }
}

// -- Helper Widgets ---------------------------------------------------------

class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});
  @override
  State<_PulseDot> createState() => __PulseDotState();
}

class __PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _anim = Tween(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _anim,
    child: Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
    ),
  );
}

class _ActionButton extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool loading;

  const _ActionButton({
    required this.isDark,
    required this.icon,
    required this.label,
    this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.glassWhite : AppColors.slate100,
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          border: Border.all(
            color: isDark ? AppColors.glassBorder : AppColors.slate200,
          ),
        ),
        child: loading
            ? Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: isDark
                        ? AppColors.slate300
                        : AppColors.slate600,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.slate300
                          : AppColors.slate600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _HowToConnectSection extends StatefulWidget {
  final bool isDark;
  final Color primary;
  const _HowToConnectSection({required this.isDark, required this.primary});

  @override
  State<_HowToConnectSection> createState() => __HowToConnectSectionState();
}

class __HowToConnectSectionState extends State<_HowToConnectSection> {
  bool _expanded = false;

  static const _steps = [
    (
      '1',
      'Ensure your Brain Server is powered on and connected to the same local network as this device.',
    ),
    (
      '2',
      'If not automatically detected, enter the server\'s local URL to connect to your Docker container.',
    ),
    (
      '3',
      'Tap \'Test Connection\' to verify the pairing. Once successful, status will turn green.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.glassWhite
            : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(
          color: isDark ? AppColors.glassBorder : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.help_outline_rounded,
                    color: widget.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'How to connect?',
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppColors.slate900,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: AppDurations.tooltip,
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: isDark
                          ? AppColors.slate400
                          : AppColors.slate500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? AppColors.slate700
                        : AppColors.slate200,
                  ),
                ),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: _steps.map((step) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.primary.withAlpha(46),
                          ),
                          child: Center(
                            child: Text(
                              step.$1,
                              style: GoogleFonts.manrope(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: widget.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            step.$2,
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              height: 1.6,
                              color: isDark
                                  ? AppColors.slate400
                                  : AppColors.slate500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
