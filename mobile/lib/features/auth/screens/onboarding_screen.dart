import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/providers.dart';
import '../../../core/theme/app_theme.dart';

/// Onboarding — shown once after phone verification.
/// Collects country, city, date of birth, age range, and category preferences.
/// All fields are optional; user can skip. Skip correctly marks onboarding as done.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _cityController = TextEditingController();
  String? _selectedCountry;
  DateTime? _dateOfBirth;
  String? _selectedAge;
  final Set<String> _selectedCategories = {};

  static const _ageRanges = ['under-18', '18-24', '25-34', '35-44', '45+'];

  static const _categories = [
    (value: 'snacks',        label: 'Snacks',         icon: '🍿'),
    (value: 'beverages',     label: 'Beverages',       icon: '🥤'),
    (value: 'dairy',         label: 'Dairy',           icon: '🧀'),
    (value: 'cosmetics',     label: 'Cosmetics',       icon: '💄'),
    (value: 'personal_care', label: 'Personal Care',   icon: '🧴'),
    (value: 'pantry',        label: 'Pantry',          icon: '🫙'),
    (value: 'produce',       label: 'Fresh Produce',   icon: '🥦'),
    (value: 'household',     label: 'Household',       icon: '🧹'),
  ];

  // Middle East + common countries
  static const _countries = [
    'Lebanon', 'Saudi Arabia', 'UAE', 'Kuwait', 'Qatar', 'Bahrain', 'Oman',
    'Jordan', 'Egypt', 'Iraq', 'Syria', 'Palestine', 'Yemen', 'Libya', 'Tunisia',
    'Morocco', 'Algeria', 'Turkey', 'Iran', 'Pakistan',
    'United States', 'United Kingdom', 'Canada', 'Australia', 'France', 'Germany',
    'Other',
  ];

  @override
  void dispose() {
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    await ref.read(authProvider.notifier).completeOnboarding(
          city:        _cityController.text.trim().isEmpty ? null : _cityController.text.trim(),
          ageRange:    _selectedAge,
          preferences: _selectedCategories.toList(),
          country:     _selectedCountry,
          dateOfBirth: _dateOfBirth,
        );
    if (!mounted) return;
    context.go('/');
  }

  /// Skip: must call completeOnboarding with empty data to set onboarding_completed=true
  /// so the router stops redirecting back to this screen.
  Future<void> _skip() async {
    await ref.read(authProvider.notifier).completeOnboarding();
    if (!mounted) return;
    context.go('/');
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 25, 1, 1),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 5),
      helpText: 'Select date of birth',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: AppTheme.primary,
            onPrimary: Colors.white,
            surface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  String _formatDob(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.user;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Header ───────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        gradient:     AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.celebration_outlined,
                          color: Colors.white, size: 28),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      user?.fullName != null
                          ? 'Welcome, ${user!.fullName!.split(' ').first}!'
                          : 'You\'re all set!',
                      style: AppTheme.heading,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Help us personalise your cashback offers.\nAll fields are optional.',
                      style: AppTheme.body,
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            // ── Country ──────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle('Country'),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _selectedCountry,
                      hint: const Text('Select your country'),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.flag_outlined),
                      ),
                      isExpanded: true,
                      items: _countries
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (val) => setState(() => _selectedCountry = val),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // ── City ─────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle('City'),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller:  _cityController,
                      decoration: const InputDecoration(
                        hintText:   'e.g. Beirut',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // ── Date of Birth ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle('Date of birth'),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: _pickDateOfBirth,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(
                          color:        Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _dateOfBirth != null ? AppTheme.primary : AppTheme.border,
                            width: _dateOfBirth != null ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.cake_outlined,
                              color: _dateOfBirth != null ? AppTheme.primary : AppTheme.inkMuted,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _dateOfBirth != null
                                  ? _formatDob(_dateOfBirth!)
                                  : 'Select date of birth',
                              style: TextStyle(
                                color:    _dateOfBirth != null ? AppTheme.ink : AppTheme.inkMuted,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // ── Age range ─────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle('Age range'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      children: _ageRanges.map((age) {
                        final selected = _selectedAge == age;
                        return ChoiceChip(
                          label:    Text(age),
                          selected: selected,
                          onSelected: (_) =>
                              setState(() => _selectedAge = selected ? null : age),
                          selectedColor: AppTheme.primaryBg,
                          backgroundColor: Colors.white,
                          side: BorderSide(
                            color: selected ? AppTheme.primary : AppTheme.border,
                          ),
                          labelStyle: TextStyle(
                            color:      selected ? AppTheme.primary : AppTheme.inkMuted,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                          ),
                          showCheckmark: false,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // ── Category preferences ──────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: _SectionTitle('Favourite categories'),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount:   2,
                  mainAxisSpacing:  10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.6,
                ),
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final cat      = _categories[i];
                    final selected = _selectedCategories.contains(cat.value);
                    return GestureDetector(
                      onTap: () => setState(() {
                        if (selected) {
                          _selectedCategories.remove(cat.value);
                        } else {
                          _selectedCategories.add(cat.value);
                        }
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color:        selected ? AppTheme.primaryBg : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected ? AppTheme.primary : AppTheme.border,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(cat.icon, style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                cat.label,
                                style: TextStyle(
                                  fontSize:   13,
                                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                  color:      selected ? AppTheme.primary : AppTheme.ink,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: _categories.length,
                ),
              ),
            ),

            // ── Buttons ───────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 36, 28, 32),
                child: Column(
                  children: [
                    ElevatedButton(
                      onPressed: auth.isLoading ? null : _submit,
                      child: auth.isLoading
                          ? const SizedBox(
                              height: 20, width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5))
                          : const Text('Save & Start Earning'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: auth.isLoading ? null : _skip,
                      child: const Text('Skip for now'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize:   15,
          fontWeight: FontWeight.w700,
          color:      AppTheme.ink,
        ),
      );
}
