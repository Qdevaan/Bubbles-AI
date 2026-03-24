import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

import '../services/auth_service.dart';
import '../widgets/app_button.dart';
import '../widgets/app_input.dart';
import '../widgets/app_logo.dart';
import '../theme/design_tokens.dart';
import '../widgets/glass_morphism.dart';

class ProfileCompletionScreen extends StatefulWidget {
  const ProfileCompletionScreen({super.key});

  @override
  State<ProfileCompletionScreen> createState() =>
      _ProfileCompletionScreenState();
}

class _ProfileCompletionScreenState extends State<ProfileCompletionScreen> {
  final _nameCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _genderCtrl = TextEditingController();

  DateTime? _dob;
  String? _gender;

  File? _imageFile;
  String? _avatarUrl;
  bool _loading = false;
  bool _initialLoading = true;

  // Extensive list of countries
  static const List<String> _countries = [
    'United States',
    'United Kingdom',
    'Canada',
    'Australia',
    'Pakistan',
    'India',
    'Germany',
    'France',
    'Italy',
    'Spain',
    'Brazil',
    'Mexico',
    'Japan',
    'South Korea',
    'China',
    'Russia',
    'South Africa',
    'Nigeria',
    'Egypt',
    'Saudi Arabia',
    'UAE',
    'Argentina',
    'Netherlands',
    'Sweden',
    'Norway',
    'Denmark',
    'Finland',
    'Poland',
    'Turkey',
    'Indonesia',
    'Thailand',
    'Vietnam',
    'Philippines',
    'Malaysia',
    'Singapore',
    'New Zealand',
    'Ireland',
    'Portugal',
    'Greece',
    'Switzerland',
    'Austria',
    'Belgium',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    try {
      final user = AuthService.instance.currentUser;
      if (user == null) return;

      final profile = await AuthService.instance.getProfile();

      if (profile != null) {
        _nameCtrl.text = profile['full_name'] ?? '';
        _countryCtrl.text = profile['country'] ?? '';
        _gender = profile['gender'];
        _genderCtrl.text = _gender ?? '';
        _avatarUrl = profile['avatar_url'];

        if (profile['dob'] != null) {
          _dob = DateTime.parse(profile['dob']);
          _dobCtrl.text = "${_dob!.day}/${_dob!.month}/${_dob!.year}";
        }
      }

      if (_nameCtrl.text.isEmpty) {
        final metaName = user.userMetadata?['full_name'];
        if (metaName != null) _nameCtrl.text = metaName;
      }
      if (_avatarUrl == null) {
        final metaAvatar = user.userMetadata?['avatar_url'];
        if (metaAvatar != null) _avatarUrl = metaAvatar;
      }
    } catch (e) {
      debugPrint("Error loading profile: $e");
    } finally {
      if (mounted) setState(() => _initialLoading = false);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _imageFile = File(picked.path);
      });
    }
  }

  Future<void> _selectDate() async {
    final now = DateTime.now();
    final initialDate = DateTime(2000);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? initialDate,
      firstDate: DateTime(1900),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              surface: Colors.transparent,
              surfaceContainer: Colors.transparent,
              surfaceContainerHigh: Colors.transparent,
              surfaceContainerHighest: Colors.transparent,
            ),
          ),
          child: Builder(
            builder: (context) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  GlassCard(
                    padding: EdgeInsets.zero,
                    borderRadius: AppRadius.xxl,
                    backgroundColor: isDark
                        ? AppColors.backgroundDark.withAlpha(200)
                        : Colors.white.withAlpha(220),
                    borderColor: isDark
                        ? Theme.of(context).colorScheme.primary.withAlpha(60)
                        : Colors.white.withAlpha(255),
                    child: child ?? const SizedBox(),
                  ),
                ],
              );
            }
          ),
        );
      },
    );

    if (picked != null) {
      setState(() {
        _dob = picked;
        _dobCtrl.text = "${picked.day}/${picked.month}/${picked.year}";
      });
    }
  }

  void _showGenderPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return GlassBottomSheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle Bar
              Center(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(76),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              ...['Male', 'Female', 'Other'].map(
                (gender) => ListTile(
                  title: Text(
                    gender,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  onTap: () {
                    setState(() {
                      _gender = gender;
                      _genderCtrl.text = gender;
                    });
                    Navigator.pop(context);
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredCountries = _countries
                .where(
                  (country) =>
                      country.toLowerCase().contains(searchQuery.toLowerCase()),
                )
                .toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.5,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                return GlassBottomSheet(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                    // Handle Bar
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withAlpha(76),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Search Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 8,
                      ),
                      child: TextField(
                        onChanged: (val) {
                          setModalState(() => searchQuery = val);
                        },
                        decoration: InputDecoration(
                          hintText: 'Search Country',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withAlpha(76),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                        ),
                      ),
                    ),
                    const Divider(),
                    // List
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: filteredCountries.length,
                        itemBuilder: (context, index) {
                          final country = filteredCountries[index];
                          final isSelected = country == _countryCtrl.text;
                          return ListTile(
                            title: Text(
                              country,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                            ),
                            trailing: isSelected
                                ? Icon(
                                    Icons.check,
                                    color: Theme.of(context).colorScheme.primary,
                                  )
                                : null,
                            onTap: () {
                              setState(() => _countryCtrl.text = country);
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _saveProfile() async {
    if (_nameCtrl.text.isEmpty ||
        _countryCtrl.text.isEmpty ||
        _dob == null ||
        _gender == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please fill all fields'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Age validation: user must be at least 13 years old
    final age = DateTime.now().difference(_dob!).inDays ~/ 365;
    if (age < 13) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('You must be at least 13 years old'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      String? finalAvatarUrl = _avatarUrl;
      if (_imageFile != null) {
        final dir = await getTemporaryDirectory();
        final targetPath = '${dir.absolute.path}/temp.jpg';
        final compressedFile = await FlutterImageCompress.compressAndGetFile(
          _imageFile!.absolute.path,
          targetPath,
          quality: 70,
          minWidth: 512,
          minHeight: 512,
        );
        final fileToUpload = compressedFile != null
            ? File(compressedFile.path)
            : _imageFile!;
        finalAvatarUrl = await AuthService.instance.uploadAvatar(fileToUpload);
      }

      await AuthService.instance.upsertProfile(
        fullName: _nameCtrl.text.trim(),
        avatarUrl: finalAvatarUrl,
        dob: _dob,
        gender: _gender,
        country: _countryCtrl.text.trim(),
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/home');
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    ImageProvider? bgImage;
    if (_imageFile != null) {
      bgImage = FileImage(_imageFile!);
    } else if (_avatarUrl != null) {
      bgImage = CachedNetworkImageProvider(_avatarUrl!);
    }

    if (_initialLoading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      body: Stack(
        children: [
          const MeshGradientBackground(),
          SafeArea(
        child: Column(
          children: [
            // Consistent header
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
                      icon: Icon(
                        Icons.arrow_back_rounded,
                        color: isDark ? Colors.white : AppColors.slate900,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Text(
                      'Profile Setup',
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

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: AppLogo(size: 80)),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Complete Profile',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Tell us a bit more about yourself',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xl),

                      // 1. Photo Section
                      Center(
                        child: Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Theme.of(context).colorScheme.primary
                                        .withAlpha(51),
                                    blurRadius: 15,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: CircleAvatar(
                                radius: 60,
                                backgroundColor:
                                    theme.colorScheme.surfaceContainerHighest,
                                backgroundImage: bgImage,
                                child: bgImage == null
                                    ? Icon(
                                        Icons.person_rounded,
                                        size: 60,
                                        color: theme
                                            .colorScheme
                                            .onSurfaceVariant
                                            .withAlpha(128),
                                      )
                                    : null,
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: _pickImage,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: theme.scaffoldBackgroundColor,
                                      width: 2,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.camera_alt_rounded,
                                    size: 20,
                                    color: theme.colorScheme.onPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: AppSpacing.xl),

                      // 2. Full Name Input
                      AppInput(
                        controller: _nameCtrl,
                        label: 'Full Name',
                        prefixIcon: Icons.person_outline_rounded,
                      ),

                      const SizedBox(height: AppSpacing.md),

                      // 3. Gender Picker
                      AppInput(
                        controller: _genderCtrl,
                        label: 'Gender',
                        prefixIcon: Icons.wc_rounded,
                        readOnly: true,
                        onTap: _showGenderPicker,
                        suffixIcon: Icons.arrow_drop_down_rounded,
                      ),

                      const SizedBox(height: AppSpacing.md),

                      // 4. Date of Birth
                      AppInput(
                        controller: _dobCtrl,
                        label: 'Date of Birth',
                        prefixIcon: Icons.calendar_today_rounded,
                        readOnly: true,
                        onTap: _selectDate,
                      ),

                      const SizedBox(height: AppSpacing.md),

                      // 5. Country Picker (Modern Modal)
                      AppInput(
                        controller: _countryCtrl,
                        label: 'Country',
                        prefixIcon: Icons.public_rounded,
                        readOnly: true,
                        onTap: _showCountryPicker,
                        suffixIcon: Icons.arrow_drop_down_rounded,
                      ),

                      const SizedBox(height: AppSpacing.xl),

                      // 6. Complete Button
                      AppButton(
                        label: 'Complete Setup',
                        onTap: _saveProfile,
                        loading: _loading,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                    ],
                  ),
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
