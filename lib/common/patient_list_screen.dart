import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'filter_screen.dart';
import 'patient_dashboard_screen_v2.dart';
import '../admin/administration_screen.dart';
import '../admin/nurse_patient_summary_screen.dart';
import '../admin/nurse_dr_patient_summary_screen.dart';
import '../admin/lab_requests_screen.dart';
import 'about_screen.dart';
import '../screens/pending_uploads_screen.dart';
import '../services/background_upload_service.dart';
import '../vascandecg/vascular_management_screen.dart';
import '../investigations/bloodweek/indicators_screen.dart';

/// Filter mode for patient list when navigating from other screens
enum PatientFilterMode {
  none, // Normal view - no special filter
  unassigned, // Show only patients with no nurse assigned
  nurseOnLeave, // Show only patients whose nurse is on leave
  assignedToNurse, // Show only patients assigned to a specific nurse
}

class PatientListScreen extends StatefulWidget {
  final PatientFilterMode filterMode;
  final List<int>? nurseOnLeaveIds;
  final int? assignedNurseId;
  final String? assignedNurseName;

  const PatientListScreen({
    super.key,
    this.filterMode = PatientFilterMode.none,
    this.nurseOnLeaveIds,
    this.assignedNurseId,
    this.assignedNurseName,
  });

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

  // Logout loading state
  bool _isLoggingOut = false;

  // Future for patients data
  late Future<List<Map<String, dynamic>>> _patientsFuture;

  // Bloodweek status with entered_by info (pcid -> entered_by_name)
  Map<int, String?> _bwEnteredBy = {};

  // Upload Queue Listener
  final BackgroundUploadService _uploadService = BackgroundUploadService();
  int _pendingUploadCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchStaffDetails();
    _syncStaffAssignmentsInBackground(); // Silent sync on load
    _patientsFuture = _fetchPatients();

    // Initialize pending count and listener
    _updatePendingCount();
    _uploadService.addListener(_updatePendingCount);
  }

  @override
  void dispose() {
    _uploadService.removeListener(_updatePendingCount);
    super.dispose();
  }

  void _updatePendingCount() {
    final count = _uploadService.getAllPendingUploads().values.fold(
      0,
      (sum, list) => sum + list.length,
    );
    if (mounted && count != _pendingUploadCount) {
      setState(() => _pendingUploadCount = count);
    }
  }

  /// Silently syncs nurse-patient assignments in the background
  /// This ensures patients have the correct nurse assigned based on their schedule
  Future<void> _syncStaffAssignmentsInBackground() async {
    try {
      await Supabase.instance.client.rpc('sync_all_patients_staffid');
      debugPrint('Staff assignments synced successfully');
    } catch (e) {
      debugPrint('Background staff sync error: $e');
      // Silently fail - don't interrupt user experience
    }
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
      if (mounted) {
        setState(() {
          _currentStaff = data;
          // Default 'My Patients' to true if the role is Nurse AND no special filter is active
          if (widget.filterMode == PatientFilterMode.none &&
              data != null &&
              data['staffrole'] == 'Nurse') {
            _showMyPatientsOnly = true;
          }
        });
      }
    } catch (e) {
      // Log the error for debugging
      debugPrint('Error fetching staff details: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPatients() async {
    try {
      final response = await Supabase.instance.client
          .from('patients')
          .select()
          .eq('status', 'Active');

      // Fetch bloodweek status with entered_by_name
      await _fetchBwStatus();

      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      throw Exception('Failed to load patients : $e');
    }
  }

  /// Fetches bloodweek entry status with who entered it
  Future<void> _fetchBwStatus() async {
    try {
      final response = await Supabase.instance.client
          .from('vw_patients_bw_status')
          .select('pcid, entered_by_name');

      final list = List<Map<String, dynamic>>.from(response);
      _bwEnteredBy = {
        for (var item in list)
          item['pcid'] as int: item['entered_by_name'] as String?,
      };
    } catch (e) {
      debugPrint('Error fetching BW status: $e');
    }
  }

  void _refreshPatients() {
    setState(() {
      _patientsFuture = _fetchPatients();
    });
  }

  Future<void> _logout() async {
    setState(() => _isLoggingOut = true);
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logout failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoggingOut = false);
    }
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

      // Special handling: if Vascular or ECG filter is active, refresh media status
      if (_filters['vascularFilter'] != null || _filters['ecgFilter'] != null) {
        await _refreshMediaStatus();
      }

      // Always apply schedule filters (hall/day/shift) regardless of media filters
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

  Future<void> _refreshMediaStatus() async {
    try {
      if (mounted) setState(() => _isLoadingFilter = true);

      // 1. Call RPC to update the columns in DB
      await Supabase.instance.client.rpc('refresh_media_status');

      // 2. Refetch the patients to get fresh has_doppler / has_ecg values
      _refreshPatients();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error refreshing media status: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingFilter = false);
    }
  }

  List<Map<String, dynamic>> _applyClientSideFilters(
    List<Map<String, dynamic>> allPatients,
  ) {
    // Get filter parameters once
    final staffId = _currentStaff?['medicalstaffid'];
    final searchQuery = _filters['search']?.toString().toLowerCase() ?? '';
    var labFilter = _filters['labFilter'];
    if (labFilter == null && _filters['showLabNotRecorded'] == true) {
      labFilter = 'none';
    }
    final currentMonth = DateFormat('MMMM').format(DateTime.now());

    // Single iteration with combined conditions
    return allPatients.where((patient) {
      // 0. Special Filter Mode (from navigation)
      if (widget.filterMode == PatientFilterMode.unassigned) {
        // Only show patients with no nurse assigned
        if (patient['nstaffid'] != null) {
          return false;
        }
      } else if (widget.filterMode == PatientFilterMode.nurseOnLeave) {
        // Only show patients whose nurse is on leave
        final nurseId = patient['nstaffid'];
        if (nurseId == null ||
            widget.nurseOnLeaveIds == null ||
            !widget.nurseOnLeaveIds!.contains(nurseId)) {
          return false;
        }
      } else if (widget.filterMode == PatientFilterMode.assignedToNurse) {
        // Only show patients assigned to the selected nurse
        final nurseId = patient['nstaffid'];
        if (widget.assignedNurseId == null ||
            nurseId != widget.assignedNurseId) {
          return false;
        }
      }

      // 1. Schedule Filters
      if (_filteredPcids != null &&
          !_filteredPcids!.contains(patient['pcid'])) {
        return false;
      }

      // 2. My Patients Filter (Skip if special filter mode is active)
      if (widget.filterMode == PatientFilterMode.none &&
          _showMyPatientsOnly &&
          _currentStaff != null) {
        if (patient['dstaffid'] != staffId && patient['nstaffid'] != staffId) {
          return false;
        }
      }

      // 3. Search Filter
      if (searchQuery.isNotEmpty) {
        final name = (patient['name'] ?? '').toString().toLowerCase();
        final id = patient['pcid'].toString();
        if (!name.contains(searchQuery) && !id.contains(searchQuery)) {
          return false;
        }
      }

      // 4. Monthly Labs Filter
      if (labFilter != null) {
        final lastBw = patient['lastbwcollected']?.toString() ?? '';
        if (labFilter == 'has') {
          if (lastBw != currentMonth) {
            return false;
          }
        } else if (labFilter == 'none') {
          if (lastBw == currentMonth) {
            return false;
          }
        }
      }

      // 5. Vascular Images Filter (using the has_doppler column)
      final vascularFilter = _filters['vascularFilter'];
      if (vascularFilter == 'has') {
        // Show only patients WITH vascular images
        if (patient['has_doppler'] != true) {
          return false;
        }
      } else if (vascularFilter == 'none') {
        // Show only patients WITHOUT vascular images
        if (patient['has_doppler'] == true) {
          return false;
        }
      }

      // 6. ECG Images Filter (using the has_ecg column)
      final ecgFilter = _filters['ecgFilter'];
      if (ecgFilter == 'has') {
        // Show only patients WITH ECG images
        if (patient['has_ecg'] != true) {
          return false;
        }
      } else if (ecgFilter == 'none') {
        // Show only patients WITHOUT ECG images
        if (patient['has_ecg'] == true) {
          return false;
        }
      }

      // 7. Vascular Access Type Filter (using the vaccess column)
      final vaccessFilter = _filters['vaccessFilter'];
      if (vaccessFilter != null) {
        final patientVaccess = patient['vaccess']?.toString() ?? '';
        if (patientVaccess != vaccessFilter) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  String _getAppBarTitle() {
    if (widget.filterMode == PatientFilterMode.unassigned) {
      return 'Unassigned Patients';
    } else if (widget.filterMode == PatientFilterMode.nurseOnLeave) {
      return 'Patients (Nurse On Leave)';
    } else if (widget.filterMode == PatientFilterMode.assignedToNurse) {
      final nurseName = widget.assignedNurseName?.trim();
      return (nurseName != null && nurseName.isNotEmpty)
          ? '$nurseName Patients'
          : 'Nurse Patients';
    } else if (_currentStaff != null) {
      return 'Hi ${_currentStaff!['name']}';
    }
    return 'Patients';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getAppBarTitle(), style: const TextStyle(fontSize: 16)),
        backgroundColor: const Color.fromARGB(255, 43, 138, 161),
        foregroundColor: Colors.white,
        actions: [
          // Pending Uploads Button
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.cloud_upload_outlined),
                tooltip: 'Pending Uploads',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PendingUploadsScreen(),
                    ),
                  );
                },
              ),
              if (_pendingUploadCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '$_pendingUploadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.leaderboard),
            tooltip: 'Nurse Patient Summary',
            onPressed: () {
              final isGlobalAdmin =
                  _currentStaff != null &&
                  (_currentStaff!['medicalstaffid'] == 59726 ||
                      _currentStaff!['medicalstaffid'] == 66931 ||
                      _currentStaff!['medicalstaffid'] == 57492);

              if (isGlobalAdmin) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const NurseDrPatientSummaryScreen(),
                  ),
                );
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const NursePatientSummaryScreen(),
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: Icon(
              Icons.filter_list,
              color: _filters.isNotEmpty ? Colors.amber : Colors.white,
            ),
            onPressed: _openFilter,
            tooltip: 'Filter',
          ),
          if (_currentStaff != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (value) {
                if (value == 'refresh') _refreshPatients();
                if (value == 'uploads') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PendingUploadsScreen(),
                    ),
                  );
                }
                if (value == 'lab_requests') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LabRequestsScreen(),
                    ),
                  );
                }
                if (value == 'vascular_management') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const VascularManagementScreen(),
                    ),
                  );
                }
                if (value == 'indicators') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const IndicatorsScreen(),
                    ),
                  );
                }
                if (value == 'about') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AboutScreen(),
                    ),
                  );
                }
                if (value == 'logout') _logout();
                if (value == 'admin') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AdministrationScreen(),
                    ),
                  );
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  enabled: false,
                  child: StatefulBuilder(
                    builder: (context, menuSetState) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.person, color: Colors.teal, size: 20),
                              SizedBox(width: 8),
                              Text(
                                "My Patients",
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          Switch(
                            value: _showMyPatientsOnly,
                            activeThumbColor: Colors.amber,
                            onChanged: (val) {
                              setState(() => _showMyPatientsOnly = val);
                              menuSetState(() {});
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const PopupMenuDivider(),
                if (_currentStaff!['medicalstaffid'] == 59726 ||
                    _currentStaff!['medicalstaffid'] == 66931 ||
                    _currentStaff!['medicalstaffid'] == 57492) ...[
                  const PopupMenuItem<String>(
                    value: 'admin',
                    child: Row(
                      children: [
                        Icon(
                          Icons.admin_panel_settings,
                          color: Colors.blueGrey,
                          size: 20,
                        ),
                        SizedBox(width: 12),
                        Text("Administration"),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                ],
                PopupMenuItem<String>(
                  value: 'uploads',
                  child: Row(
                    children: [
                      const Icon(
                        Icons.cloud_upload_outlined,
                        color: Colors.blueGrey,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _pendingUploadCount > 0
                            ? "Uploads ($_pendingUploadCount)"
                            : "Uploads",
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'lab_requests',
                  child: Row(
                    children: [
                      Icon(
                        Icons.science_outlined,
                        color: Colors.blueGrey,
                        size: 20,
                      ),
                      SizedBox(width: 12),
                      Text("Today Lab Requests"),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'vascular_management',
                  child: Row(
                    children: [
                      Icon(
                        Icons.monitor_heart,
                        color: Colors.blueGrey,
                        size: 20,
                      ),
                      SizedBox(width: 12),
                      Text("Vascular Management"),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'indicators',
                  child: Row(
                    children: [
                      Icon(Icons.bar_chart, color: Colors.blueGrey, size: 20),
                      SizedBox(width: 12),
                      Text("Indicators (Ca, PO4, etc)"),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'refresh',
                  child: Row(
                    children: [
                      Icon(Icons.refresh, color: Colors.teal, size: 20),
                      SizedBox(width: 12),
                      Text("Refresh"),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'about',
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.blueGrey,
                        size: 20,
                      ),
                      SizedBox(width: 12),
                      Text("About"),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, color: Colors.redAccent, size: 20),
                      SizedBox(width: 12),
                      Text("Logout"),
                    ],
                  ),
                ),
              ],
            ),
          if (_isLoggingOut)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
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
                      'Filtering by: ${_filters.entries.map((e) => _labelForFilter(e.key, e.value)).join(", ")}',
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
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _patientsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Error: ${snapshot.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _refreshPatients,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('No patients found.'));
                }

                // Apply all client-side filters
                final allPatients = snapshot.data!;
                final patients = _applyClientSideFilters(allPatients);

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
                          ? const Center(
                              child: Text('No patients match the filters.'),
                            )
                          : RefreshIndicator(
                              onRefresh: () async {
                                _refreshPatients();
                              },
                              child: ListView.separated(
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
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 20,
                                            vertical: 8,
                                          ),
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                PatientDashboardScreenV2(
                                                  patient: patient,
                                                  staffRole:
                                                      _currentStaff?['staffrole'],
                                                  medicalStaffId:
                                                      _currentStaff?['medicalstaffid'],
                                                  patientList: patients,
                                                  currentIndex: index,
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
                                          // BW Collected Indicator with entered_by info
                                          Builder(
                                            builder: (context) {
                                              final pcid =
                                                  patient['pcid'] as int;
                                              final lastBw =
                                                  patient['lastbwcollected'];
                                              final currentMonth = DateFormat(
                                                'MMMM',
                                              ).format(DateTime.now());
                                              final isRecorded =
                                                  lastBw == currentMonth;
                                              final enteredBy =
                                                  _bwEnteredBy[pcid];

                                              String tooltipMsg =
                                                  'Last BW: ${lastBw ?? 'N/A'}';
                                              if (isRecorded &&
                                                  enteredBy != null) {
                                                tooltipMsg +=
                                                    '\nEntered by: $enteredBy';
                                              }

                                              return Tooltip(
                                                message: tooltipMsg,
                                                child: Container(
                                                  width: 22,
                                                  height: 22,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: isRecorded
                                                        ? Colors.green
                                                        : Colors.red.shade200,
                                                  ),
                                                  child:
                                                      isRecorded &&
                                                          enteredBy != null
                                                      ? Center(
                                                          child: Text(
                                                            enteredBy[0]
                                                                .toUpperCase(),
                                                            style:
                                                                const TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                  fontSize: 10,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                ),
                                                          ),
                                                        )
                                                      : null,
                                                ),
                                              );
                                            },
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

  String _labelForFilter(String key, dynamic value) {
    switch (key) {
      case 'showLabNotRecorded':
        return 'Labs: No Labs';
      case 'labFilter':
        if (value == 'has') return 'Labs: Has Labs';
        if (value == 'none') return 'Labs: No Labs';
        return 'Labs: Any';
      case 'vascularFilter':
        if (value == 'has') return 'Has Doppler';
        if (value == 'none') return 'No Doppler';
        return 'Doppler: Any';
      case 'ecgFilter':
        if (value == 'has') return 'Has ECG';
        if (value == 'none') return 'No ECG';
        return 'ECG: Any';
      case 'hallname':
        return 'Hall: $value';
      case 'day':
        return 'Day: $value';
      case 'shift':
        return 'Shift: $value';
      case 'search':
        return 'Search: $value';
      case 'vaccessFilter':
        return 'Access: $value';
      default:
        return value?.toString() ?? key;
    }
  }
}
