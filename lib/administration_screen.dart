import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class AdministrationScreen extends StatefulWidget {
  const AdministrationScreen({super.key});

  @override
  State<AdministrationScreen> createState() => _AdministrationScreenState();
}

class _AdministrationScreenState extends State<AdministrationScreen> {
  bool _isSyncingPatients = false;
  bool _isSyncingSchedules = false;

  final String _googleSheetsUrl =
      'https://script.google.com/macros/s/AKfycbxnqQxdSxcAJbzLt07jWPrhKNAEwELl8qoMC07c7xfCMHqLbruxj7NHlaiVN09bACbWLg/exec?type=patients';

  Future<void> _syncPatients() async {
    setState(() => _isSyncingPatients = true);
    try {
      // 1. Fetch from Google Sheets
      final response = await http.get(Uri.parse(_googleSheetsUrl));
      if (response.statusCode != 200) {
        throw Exception(
          'Failed to fetch from Google Sheets: ${response.statusCode}',
        );
      }

      final List<dynamic> uniqueList = json.decode(response.body);
      final client = Supabase.instance.client;

      // 2. Load all existing patients pcid
      final List<dynamic> existingPatients = await client
          .from('patients')
          .select('pcid');
      final existingIds = existingPatients.map((p) => p['pcid']).toSet();

      // 3. Build sheet IDs + insertion list
      final sheetIds = <int>[];
      final List<Map<String, dynamic>> toInsert = [];

      for (var item in uniqueList) {
        final cidRaw = item['0'] ?? item['cid'];
        final name = item['1'] ?? item['name'];
        final cid = int.tryParse(cidRaw.toString());

        if (cid == null) continue;

        sheetIds.add(cid);

        if (!existingIds.contains(cid)) {
          toInsert.add({'pcid': cid, 'name': name, 'status': 'Active'});
        }
      }

      // 4. Insert new patients
      if (toInsert.isNotEmpty) {
        await client.from('patients').insert(toInsert);
      }

      // 5. Set sheet patients = Active
      if (sheetIds.isNotEmpty) {
        await client
            .from('patients')
            .update({'status': 'Active'})
            .inFilter('pcid', sheetIds);
      }

      // 6. Set non-sheet = Other
      if (sheetIds.isNotEmpty) {
        await client
            .from('patients')
            .update({'status': 'Other'})
            .not('pcid', 'in', '(${sheetIds.join(",")})');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sync Complete: Patients updated successfully'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error syncing patients: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncingPatients = false);
    }
  }

  Future<void> _syncSchedule() async {
    setState(() => _isSyncingSchedules = true);

    try {
      final client = Supabase.instance.client;
      final session = client.auth.currentSession;

      if (session == null) {
        throw Exception('User is not logged in');
      }

      final res = await client.functions.invoke(
        'sync_schedule',
        headers: {
          'Authorization':
              'Bearer ${Supabase.instance.client.auth.currentSession!.accessToken}',
        },
      );

      final data = res.data;

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sync Complete'),
          content: Text(
            'Schedules synced successfully.\n'
            'Total records inserted: ${data['inserted'] ?? 0}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error syncing schedules: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSyncingSchedules = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('System Administration'),
        backgroundColor: const Color.fromARGB(255, 43, 138, 161),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildAdminCard(
            title: 'Data Integration',
            icon: Icons.sync_rounded,
            color: Colors.blue.shade50,
            iconColor: Colors.blue.shade900,
            children: [
              _buildActionTile(
                title: 'Fetch Patients from Google Sheets',
                subtitle: 'Updates patient records from master spreadsheet',
                isLoading: _isSyncingPatients,
                onTap: _syncPatients,
                icon: Icons.cloud_download_outlined,
              ),
              const Divider(),
              _buildActionTile(
                title: 'Sync Schedules',
                subtitle: 'Triggers Supabase schedule synchronization',
                isLoading: _isSyncingSchedules,
                onTap: _syncSchedule,
                icon: Icons.schedule_send_outlined,
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildAdminCard(
            title: 'Nurses Assignment',
            icon: Icons.assignment_ind_outlined,
            color: Colors.teal.shade50,
            iconColor: Colors.teal.shade900,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'Feature coming soon...',
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildAdminCard(
            title: 'Message Notifications',
            icon: Icons.notifications_active_outlined,
            color: Colors.orange.shade50,
            iconColor: Colors.orange.shade900,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'System notifications management (Planned)',
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdminCard({
    required String title,
    required IconData icon,
    required Color color,
    required Color iconColor,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: iconColor),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: iconColor,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required String title,
    required String subtitle,
    required bool isLoading,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.blueGrey),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: isLoading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      onTap: isLoading ? null : onTap,
    );
  }
}
