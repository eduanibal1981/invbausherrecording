import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'patient_dashboard_screen.dart';
import 'filter_screen.dart';

class PatientListScreen extends StatefulWidget {
  const PatientListScreen({super.key});

  @override
  State<PatientListScreen> createState() => _PatientListScreenState();
}

class _PatientListScreenState extends State<PatientListScreen> {
  // Filters
  Map<String, dynamic> _filters = {};
  List<int>? _filteredPcids;
  bool _isLoadingFilter = false;

  // Staff Logic
  Map<String, dynamic>? _currentStaff;
  bool _showMyPatientsOnly = false;

  @override
  void initState() {
    super.initState();
    _fetchStaffDetails();
  }

  Future<void> _fetchStaffDetails() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final data = await Supabase.instance.client
          .from('staff')
          .select()
          .eq('userid', userId)
          .maybeSingle();
      if (mounted) setState(() => _currentStaff = data);
    } catch (_) {
      // Handle error cleanly
    }
  }

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();
  }

  Stream<List<Map<String, dynamic>>> get _patientsStream {
    return Supabase.instance.client
        .from('patients')
        .stream(primaryKey: ['pcid'])
        .eq('status', 'Active');
  }

  Future<void> _openFilter() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => FilterScreen(initialFilters: _filters),
      ),
    );

    if (result != null) {
      setState(() {
        _filters = result;
      });
      _applyFilters();
    }
  }

  Future<void> _applyFilters() async {
    if (_filters.isEmpty) {
      setState(() {
        _filteredPcids = null;
      });
      return;
    }

    setState(() => _isLoadingFilter = true);
    try {
      var query = Supabase.instance.client.from('schedules').select('pcid');

      if (_filters['hallname'] != null) {
        query = query.eq('hallname', _filters['hallname']);
      }
      if (_filters['day'] != null) {
        query = query.eq('day', _filters['day']);
      }
      if (_filters['shift'] != null) {
        query = query.eq('shift', _filters['shift']);
      }

      final response = await query;
      final ids = (response as List)
          .map((e) => e['pcid'] as int)
          .toSet()
          .toList(); // Unique IDs

      setState(() {
        _filteredPcids = ids;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error applying filter: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoadingFilter = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentStaff != null ? 'Hi ${_currentStaff!['name']}' : 'Patients',
          style: const TextStyle(fontSize: 16), // Reduced font size
        ),
        backgroundColor: const Color.fromARGB(255, 43, 138, 161),
        foregroundColor: Colors.white,
        actions: [
          if (_currentStaff != null)
            Row(
              children: [
                const Text('My Patients', style: TextStyle(fontSize: 12)),
                Switch(
                  value: _showMyPatientsOnly,
                  activeThumbColor: Colors.amber,
                  onChanged: (val) => setState(() => _showMyPatientsOnly = val),
                ),
              ],
            ),
          IconButton(
            icon: Icon(
              Icons.filter_list,
              color: _filters.isNotEmpty ? Colors.amber : Colors.white,
            ),
            onPressed: _openFilter,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoadingFilter) const LinearProgressIndicator(),
          if (_filters.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.teal.shade50,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Filtering by: ${_filters.entries.map((e) => e.key == 'showLabNotRecorded' ? 'Lab Not Recorded' : e.value).join(", ")}',
                      style: TextStyle(color: Colors.teal.shade900),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () {
                      setState(() {
                        _filters = {};
                        _filteredPcids = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _patientsStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Filter the list client-side
                final allPatients = snapshot.data!;
                var patients = allPatients;

                // 1. Apply Schedule Filters
                if (_filteredPcids != null) {
                  patients = patients
                      .where((p) => _filteredPcids!.contains(p['pcid']))
                      .toList();
                }

                // 2. Apply My Patients Filter
                if (_showMyPatientsOnly && _currentStaff != null) {
                  final staffId = _currentStaff!['medicalstaffid'];
                  patients = patients
                      .where(
                        (p) =>
                            p['dstaffid'] == staffId ||
                            p['nstaffid'] == staffId,
                      )
                      .toList();
                }

                // 3. Apply Search Filter
                if (_filters['search'] != null &&
                    _filters['search'].isNotEmpty) {
                  final query = _filters['search'].toString().toLowerCase();
                  patients = patients.where((p) {
                    final name = (p['name'] ?? '').toString().toLowerCase();
                    final id = p['pcid'].toString();
                    return name.contains(query) || id.contains(query);
                  }).toList();
                }

                // 4. Apply Lab Not Recorded Filter
                if (_filters['showLabNotRecorded'] == true) {
                  final currentMonth = DateFormat(
                    'MMMM',
                  ).format(DateTime.now());
                  patients = patients.where((p) {
                    final lastBw = p['lastbwcollected']?.toString() ?? '';
                    return lastBw != currentMonth;
                  }).toList();
                }

                return Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 16,
                      ),
                      color: Colors.blue.shade50,
                      child: Text(
                        'Total Patients: ${patients.length}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      child: patients.isEmpty
                          ? const Center(child: Text('No patients found.'))
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: patients.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final patient = patients[index];
                                return Card(
                                  elevation: 4,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 8,
                                    ),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              PatientDashboardScreen(
                                                patient: patient,
                                                staffRole:
                                                    _currentStaff?['staffrole'],
                                              ),
                                        ),
                                      );
                                    },
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.teal.shade100,
                                      child: Text(
                                        (patient['name'] as String?)
                                                ?.substring(0, 1)
                                                .toUpperCase() ??
                                            '?',
                                        style: TextStyle(
                                          color: Colors.teal.shade900,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      patient['name'] ?? 'Unknown Name',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'ID: ${patient['pcid']}',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // BW Collected Indicator
                                        Tooltip(
                                          message:
                                              'Last BW: ${patient['lastbwcollected'] ?? 'N/A'}',
                                          child: Container(
                                            width: 22,
                                            height: 22,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color:
                                                  (patient['lastbwcollected'] ==
                                                      DateFormat(
                                                        'MMMM',
                                                      ).format(DateTime.now()))
                                                  ? Colors.green
                                                  : const Color.fromARGB(
                                                      255,
                                                      247,
                                                      152,
                                                      152,
                                                    ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // Doctor Reviewed Indicator
                                        Tooltip(
                                          message:
                                              'Doctor Reviewed: ${patient['isdrreviwed'] == true ? "Yes" : "No"}',
                                          child: Container(
                                            width: 18,
                                            height: 18,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.rectangle,
                                              color:
                                                  (patient['isdrreviwed'] ==
                                                      true)
                                                  ? Colors.green
                                                  : Colors.red.shade200,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        const Icon(
                                          Icons.arrow_forward_ios,
                                          size: 16,
                                          color: Colors.grey,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
