import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'nurse_patient_summary_screen.dart';
import 'nurse_assignment_screen.dart';

class AdministrationScreen extends StatefulWidget {
  const AdministrationScreen({super.key});

  @override
  State<AdministrationScreen> createState() => _AdministrationScreenState();
}

class _AdministrationScreenState extends State<AdministrationScreen> {
  bool _isSyncing = false;
  String _currentSyncStep = '';

  final String _googleSheetsUrl =
      'https://script.google.com/macros/s/AKfycbxnqQxdSxcAJbzLt07jWPrhKNAEwELl8qoMC07c7xfCMHqLbruxj7NHlaiVN09bACbWLg/exec?type=patients';

  /// Unified sync method - runs all data integration steps
  Future<void> _runFullSync() async {
    setState(() {
      _isSyncing = true;
      _currentSyncStep = 'Starting...';
    });

    int newPatientsCount = 0;
    int schedulesInserted = 0;

    try {
      final client = Supabase.instance.client;

      // Step 1: Fetch from Google Sheets
      setState(
        () => _currentSyncStep = '📥 Fetching patients from Google Sheets...',
      );
      final response = await http.get(Uri.parse(_googleSheetsUrl));
      if (response.statusCode != 200) {
        throw Exception(
          'Failed to fetch from Google Sheets: ${response.statusCode}',
        );
      }
      final List<dynamic> uniqueList = json.decode(response.body);

      // Step 2: Load existing patients
      setState(() => _currentSyncStep = '📋 Checking existing records...');
      final List<dynamic> existingPatients = await client
          .from('patients')
          .select('pcid');
      final existingIds = existingPatients.map((p) => p['pcid']).toSet();

      // Build sheet IDs + insertion list
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

      newPatientsCount = toInsert.length;

      // Step 3: Insert new patients
      if (toInsert.isNotEmpty) {
        setState(
          () =>
              _currentSyncStep = '➕ Adding ${toInsert.length} new patients...',
        );
        await client.from('patients').insert(toInsert);
      }

      // Step 4: Update patient statuses
      setState(() => _currentSyncStep = '🔄 Updating patient statuses...');
      if (sheetIds.isNotEmpty) {
        await client
            .from('patients')
            .update({'status': 'Active'})
            .inFilter('pcid', sheetIds);
        await client
            .from('patients')
            .update({'status': 'Other'})
            .not('pcid', 'in', '(${sheetIds.join(",")})');
      }

      // Step 5: Update Patient Schedule RPC
      setState(() => _currentSyncStep = '📅 Updating patient schedules...');
      await client.rpc('update_patient_schedule');

      // Step 6: Update Staff assignments
      setState(() => _currentSyncStep = '👥 Syncing staff assignments...');
      await client.rpc('sync_all_patients_staffid');

      // Step 7: Sync schedules via Edge Function
      setState(() => _currentSyncStep = '⏰ Syncing schedule data...');
      final session = client.auth.currentSession;
      if (session != null) {
        final res = await client.functions.invoke(
          'sync_schedule',
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        );
        schedulesInserted = res.data?['inserted'] ?? 0;
      }

      // Complete!
      setState(() => _currentSyncStep = '✅ Sync Complete!');

      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 500));
        _showSyncResultDialog(
          success: true,
          newPatients: newPatientsCount,
          totalPatients: sheetIds.length,
          schedulesInserted: schedulesInserted,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _currentSyncStep = '❌ Error occurred');
        _showSyncResultDialog(success: false, error: e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _currentSyncStep = '';
        });
      }
    }
  }

  void _showSyncResultDialog({
    required bool success,
    int newPatients = 0,
    int totalPatients = 0,
    int schedulesInserted = 0,
    String? error,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          success ? Icons.check_circle : Icons.error,
          color: success ? Colors.green : Colors.red,
          size: 48,
        ),
        title: Text(success ? 'Sync Complete!' : 'Sync Failed'),
        content: success
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildResultRow(
                    Icons.people,
                    'Total patients processed',
                    '$totalPatients',
                  ),
                  _buildResultRow(
                    Icons.person_add,
                    'New patients added',
                    '$newPatients',
                  ),
                  _buildResultRow(
                    Icons.schedule,
                    'Schedules synced',
                    '$schedulesInserted',
                  ),
                ],
              )
            : Text(
                'An error occurred during sync:\n\n$error',
                style: const TextStyle(color: Colors.red),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildResultRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.blue.shade700),
          const SizedBox(width: 8),
          Text('$label: '),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
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
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Description
                    const Text(
                      'Synchronize all patient data and schedules from external sources.',
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                    const SizedBox(height: 16),

                    // Progress indicator (visible during sync)
                    if (_isSyncing) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _currentSyncStep,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.blue.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Sync button
                    ElevatedButton.icon(
                      onPressed: _isSyncing ? null : _runFullSync,
                      icon: _isSyncing
                          ? const SizedBox.shrink()
                          : const Icon(Icons.sync, size: 22),
                      label: Text(
                        _isSyncing ? 'Syncing...' : 'Sync All Data',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 2,
                      ),
                    ),

                    // Info text
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 14,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Fetches patients, updates statuses & syncs schedules',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
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
              _buildActionTile(
                title: 'Nurse Patient Summary',
                subtitle: 'View monthly blood work statistics per nurse',
                isLoading: false,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NursePatientSummaryScreen(),
                    ),
                  );
                },
                icon: Icons.analytics_outlined,
              ),
              const Divider(),
              _buildActionTile(
                title: 'Assign Nurses',
                subtitle: 'Assign nurses to patient groups (Hall/Day/Shift)',
                isLoading: false,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NurseAssignmentScreen(),
                    ),
                  );
                },
                icon: Icons.assignment_ind_outlined,
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
