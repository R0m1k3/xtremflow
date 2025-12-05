import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../auth/providers/auth_provider.dart';

class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(authProvider).currentUser;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.person),
            title: Text(
              'Logged in as',
              style: GoogleFonts.roboto(fontSize: 12, color: Colors.grey),
            ),
            subtitle: Text(
              currentUser?.username ?? 'Unknown',
              style: GoogleFonts.roboto(fontWeight: FontWeight.w600),
            ),
            trailing: currentUser?.isAdmin ?? false
                ? Chip(
                    label: Text('Admin', style: GoogleFonts.roboto(fontSize: 11)),
                    backgroundColor: Colors.blue.shade100,
                  )
                : null,
          ),
        ),
        const SizedBox(height: 16),
        if (currentUser?.isAdmin ?? false) ...[
          Card(
            child: ListTile(
              leading: const Icon(Icons.admin_panel_settings),
              title: Text('Admin Panel', style: GoogleFonts.roboto()),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/admin'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Card(
          child: ListTile(
            leading: const Icon(Icons.playlist_play),
            title: Text('Change Playlist', style: GoogleFonts.roboto()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/playlists'),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text('About', style: GoogleFonts.roboto()),
            subtitle: Text(
              'XtremFlow IPTV v1.0.0',
              style: GoogleFonts.roboto(fontSize: 12),
            ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () {
            ref.read(authProvider.notifier).logout();
            context.go('/login');
          },
          icon: const Icon(Icons.logout),
          label: const Text('Logout'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ],
    );
  }
}
