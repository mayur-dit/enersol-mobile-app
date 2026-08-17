import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/page_scaffold.dart';
import '../settings/settings_screen.dart';

/// The signed-in customer's details.
///
/// Read-only by design: these fields are the billing identity the office works
/// from, so changes go through the Enersol team rather than being editable in
/// the app.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().user;
    final theme = Theme.of(context);

    if (user == null) {
      return const PageScaffold(
        title: 'PROFILE',
        child: EmptyState(
          icon: Icons.person_off_outlined,
          title: 'Not signed in',
        ),
      );
    }

    final address = [
      user.address,
      user.city,
      user.state,
      user.pincode,
    ].where((p) => p != null && p.trim().isNotEmpty).join(', ');

    return PageScaffold(
      title: 'PROFILE',
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pageInsets(context),
        children: [
          // ── Identity ──────────────────────────────────────────────────
          GlassCard(
            strong: true,
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    gradient: AppColors.brand,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.ember.withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      user.initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 27,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  user.name,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                StatusChip(
                  label: 'Customer',
                  gradient: AppColors.leaf,
                  icon: Icons.verified_rounded,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const SectionTitle('Contact'),
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                _Row(
                  icon: Icons.badge_outlined,
                  label: 'Username',
                  value: user.userName,
                ),
                _Row(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: user.email,
                ),
                _Row(
                  icon: Icons.phone_outlined,
                  label: 'Mobile',
                  value: user.mobile,
                  isLast: user.referralCode == null || user.referralCode!.isEmpty,
                ),
                if (user.referralCode != null && user.referralCode!.isNotEmpty)
                  _Row(
                    icon: Icons.card_giftcard_outlined,
                    label: 'Referral',
                    value: user.referralCode,
                    isLast: true,
                  ),
              ],
            ),
          ),

          if (address.isNotEmpty || user.companyName != null) ...[
            const SizedBox(height: 20),
            const SectionTitle('Address'),
            GlassCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  if (user.companyName != null)
                    _Row(
                      icon: Icons.business_outlined,
                      label: 'Company',
                      value: user.companyName,
                    ),
                  _Row(
                    icon: Icons.place_outlined,
                    label: 'Address',
                    value: address.isEmpty ? null : address,
                    isLast: user.gstin == null,
                  ),
                  if (user.gstin != null)
                    _Row(
                      icon: Icons.receipt_long_outlined,
                      label: 'GSTIN',
                      value: user.gstin,
                      isLast: true,
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),
          GlassCard(
            padding: const EdgeInsets.all(14),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
            child: Row(
              children: [
                const Icon(Icons.settings_rounded, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Settings',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 20),
              ],
            ),
          ),

          const SizedBox(height: 16),
          Center(
            child: Text(
              'To update your details, please contact the Enersol team.',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String? value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = (value == null || value!.trim().isEmpty) ? '—' : value!;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 19, color: theme.textTheme.bodySmall?.color),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.textTheme.labelSmall),
                    const SizedBox(height: 2),
                    Text(
                      shown,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!isLast) const Divider(height: 1, indent: 46),
      ],
    );
  }
}
