import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../common/patient_list_screen.dart';

class NurseAssignmentScreen extends StatefulWidget {
  final bool isAdmin;

  const NurseAssignmentScreen({super.key, this.isAdmin = true});

  @override
  State<NurseAssignmentScreen> createState() => _NurseAssignmentScreenState();
}

// ==============
class _NurseAssignmentScreenState extends State<NurseAssignmentScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  List<Map<String, dynamic>> _nurses = [];
  Map<int, List<Map<String, dynamic>>> _nurseAssignments =
      {}; // staffid -> list of assignments - to
  Map<int, int> _patientCounts = {}; // staffid -> patient count
  List<Map<String, dynamic>> _availableSlots =
      []; // All hall/day/shift combinations
  int _unassignedPatientCount =
      0; // Count of patients not assigned to any nurse
  int _patientsWithNurseOnLeaveCount =
      0; // Count of patients whose nurse is on leave
  Set<int> _nursesOnLeaveIds = {}; // Set of nurse IDs currently on leave

  // Staged changes: staffId -> List of assignments
  Map<int, List<Map<String, dynamic>>> _stagedAdditions = {};
  // staffId -> List of keys ('ghall-gday-gshift')
  Map<int, Set<String>> _stagedDeletions = {};

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final client = Supabase.instance.client;

      // 1. Fetch all nurses (including leave status)
      final nursesResponse = await client
          .from('staff')
          .select('medicalstaffid, name, staffrole, is_on_leave')
          .eq('staffrole', 'Nurse')
          .order('name');

      // 2. Fetch all assignments (ismain = true)
      final assignmentsResponse = await client
          .from('groupsofpatients')
          .select()
          .eq('ismain', true);

      // 3. Fetch patient counts per nurse
      final patientCountsResponse = await client
          .from('patients')
          .select('nstaffid')
          .eq('status', 'Active');

      // 4. Fetch available hall/day/shift combinations from groupsofpatients where ismain = true
      final slotsResponse = await client
          .from('groupsofpatients')
          .select('ghall, gday, gshift')
          .eq('ismain', true)
          .order('ghall')
          .order('gday')
          .order('gshift');

      // Process data
      final nurses = List<Map<String, dynamic>>.from(nursesResponse);
      final assignments = List<Map<String, dynamic>>.from(assignmentsResponse);
      final patientList = List<Map<String, dynamic>>.from(
        patientCountsResponse,
      );
      final slots = List<Map<String, dynamic>>.from(slotsResponse);

      // Group assignments by nurse
      final nurseAssignments = <int, List<Map<String, dynamic>>>{};
      for (var nurse in nurses) {
        final staffId = nurse['medicalstaffid'] as int;
        nurseAssignments[staffId] = assignments
            .where((a) => a['staffid'] == staffId)
            .toList();
      }

      // Build set of nurses on leave
      final nursesOnLeave = <int>{};
      for (var nurse in nurses) {
        if (nurse['is_on_leave'] == true) {
          nursesOnLeave.add(nurse['medicalstaffid'] as int);
        }
      }

      // Count patients per nurse, unassigned patients, and patients with nurse on leave
      final patientCounts = <int, int>{};
      int unassignedCount = 0;
      int nurseOnLeaveCount = 0;
      for (var patient in patientList) {
        final staffId = patient['nstaffid'];
        if (staffId != null) {
          patientCounts[staffId] = (patientCounts[staffId] ?? 0) + 1;
          // Check if this patient's nurse is on leave
          if (nursesOnLeave.contains(staffId)) {
            nurseOnLeaveCount++;
          }
        } else {
          unassignedCount++;
        }
      }

      setState(() {
        _nurses = nurses;
        _nurseAssignments = nurseAssignments;
        _patientCounts = patientCounts;
        _availableSlots = slots;
        _unassignedPatientCount = unassignedCount;
        _patientsWithNurseOnLeaveCount = nurseOnLeaveCount;
        _nursesOnLeaveIds = nursesOnLeave;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  void _addAssignment(
    int staffId,
    String hall,
    String day,
    String shift,
  ) {
    setState(() {
      final newAssignment = {
        'ghall': hall,
        'gday': day,
        'gshift': shift,
        'staffid': staffId,
      };
      _stagedAdditions[staffId] = (_stagedAdditions[staffId] ?? [])
        ..add(newAssignment);

      // If it was staged for deletion, remove it from deletions
      final key = '$hall-$day-$shift';
      _stagedDeletions[staffId]?.remove(key);
    });
  }

  void _revertAdd(int staffId, int index) {
    setState(() {
      _stagedAdditions[staffId]?.removeAt(index);
    });
  }

  void _removeAssignment(
    int staffId,
    String hall,
    String day,
    String shift,
  ) {
    setState(() {
      final key = '$hall-$day-$shift';

      // Check if it was a staged addition
      final stagedIdx = _stagedAdditions[staffId]?.indexWhere(
        (a) => a['ghall'] == hall && a['gday'] == day && a['gshift'] == shift,
      );

      if (stagedIdx != null && stagedIdx != -1) {
        _stagedAdditions[staffId]?.removeAt(stagedIdx);
      } else {
        _stagedDeletions[staffId] = (_stagedDeletions[staffId] ?? {})..add(key);
      }
    });
  }

  void _revertDelete(int staffId, String key) {
    setState(() {
      _stagedDeletions[staffId]?.remove(key);
    });
  }

  Future<void> _saveAllChanges() async {
    if (_stagedAdditions.isEmpty && _stagedDeletions.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Changes'),
        content: const Text('Confirm sending all staged assignments to database?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Save'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSaving = true);
    try {
      final client = Supabase.instance.client;

      // 1. Process Deletions
      for (var entry in _stagedDeletions.entries) {
        final staffId = entry.key;
        for (var key in entry.value) {
          final parts = key.split('-');
          final hall = parts[0];
          final day = parts[1];
          final shift = parts[2];

          await client
              .from('groupsofpatients')
              .update({'staffid': null, 'ismain': false})
              .match({'ghall': hall, 'gday': day, 'gshift': shift, 'staffid': staffId});

          // Safety cleanup: ensure stale nurse IDs are removed for this slot.
          await client
              .from('patients')
              .update({'nstaffid': null})
              .match({'hall_main': hall, 'day_main': day, 'shift_main': shift})
              .eq('nstaffid', staffId);
        }
      }

      // 2. Process Additions
      for (var additions in _stagedAdditions.values) {
        for (var a in additions) {
          await client
              .from('groupsofpatients')
              .update({'staffid': a['staffid'], 'ismain': true})
              .match({'ghall': a['ghall'], 'gday': a['gday'], 'gshift': a['gshift']});
        }
      }

      // Sync patient assignments
      await client.rpc('sync_all_patients_staffid');

      setState(() {
        _stagedAdditions.clear();
        _stagedDeletions.clear();
      });

      await _fetchData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All changes saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving changes: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _toggleNurseLeave(
    int staffId,
    String nurseName,
    bool currentlyOnLeave,
  ) async {
    final newStatus = !currentlyOnLeave;
    final action = newStatus ? 'mark as on leave' : 'mark as returned';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(newStatus ? 'Mark Nurse On Leave' : 'Mark Nurse Returned'),
        content: Text('Are you sure you want to $action for $nurseName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: newStatus ? Colors.orange : Colors.green,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(newStatus ? 'Mark On Leave' : 'Mark Returned'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSaving = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      String changedBy = 'Unknown';
      if (userId != null) {
        try {
          final staffData = await Supabase.instance.client
              .from('staff')
              .select('name')
              .eq('userid', userId)
              .maybeSingle();
          if (staffData != null && staffData['name'] != null) {
            changedBy = staffData['name'];
          }
        } catch (_) {}
      }

      await Supabase.instance.client
          .from('staff')
          .update({'is_on_leave': newStatus, 'changby': changedBy})
          .eq('medicalstaffid', staffId);

      await _fetchData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus
                  ? '$nurseName marked as on leave'
                  : '$nurseName marked as returned',
            ),
            backgroundColor: newStatus ? Colors.orange : Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating leave status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _openNursePatients(int staffId, String nurseName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PatientListScreen(
          filterMode: PatientFilterMode.assignedToNurse,
          assignedNurseId: staffId,
          assignedNurseName: nurseName,
        ),
      ),
    );
  }

  void _showAddAssignmentDialog(int staffId, String nurseName) {
    // Get currently assigned slots for this nurse (real + staged)
    final realAssignments = _nurseAssignments[staffId] ?? [];
    final stagedAdds = _stagedAdditions[staffId] ?? [];
    final deletedKeys = _stagedDeletions[staffId] ?? {};

    final currentAssignmentsKeys = realAssignments
        .where((a) => !deletedKeys.contains('${a['ghall']}-${a['gday']}-${a['gshift']}'))
        .map((a) => '${a['ghall']}-${a['gday']}-${a['gshift']}')
        .toList();

    currentAssignmentsKeys.addAll(
      stagedAdds.map((a) => '${a['ghall']}-${a['gday']}-${a['gshift']}'),
    );

    final assignedKeysSet = currentAssignmentsKeys.toSet();

    // Filter available slots (not already assigned to this nurse)
    final availableForNurse = _availableSlots.where((slot) {
      final key =
          '${slot['ghall']}-${slot['gday']}-${slot['gshift']}';
      return !assignedKeysSet.contains(key);
    }).toList();

    if (availableForNurse.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No available slots to assign'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    String? selectedHall;
    String? selectedDay;
    String? selectedShift;

    // Get unique halls, days, shifts
    final halls =
        availableForNurse.map((s) => s['ghall'] as String).toSet().toList()
          ..sort();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Filter days based on selected hall
          final daysForHall = selectedHall != null
              ? availableForNurse
                    .where((s) => s['ghall'] == selectedHall)
                    .map((s) => s['gday'] as String)
                    .toSet()
                    .toList()
              : <String>[];
          daysForHall.sort((a, b) => _dayOrder(a).compareTo(_dayOrder(b)));

          // Filter shifts based on selected hall and day
          final shiftsForHallDay = (selectedHall != null && selectedDay != null)
              ? availableForNurse
                    .where(
                      (s) =>
                          s['ghall'] == selectedHall &&
                          s['gday'] == selectedDay,
                    )
                    .map((s) => s['gshift'] as String)
                    .toSet()
                    .toList()
              : <String>[];
          shiftsForHallDay.sort(
            (a, b) => _shiftOrder(a).compareTo(_shiftOrder(b)),
          );

          return AlertDialog(
            title: Text('Add Assignment for $nurseName'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedHall,
                  decoration: const InputDecoration(
                    labelText: 'Hall',
                    border: OutlineInputBorder(),
                  ),
                  items: halls
                      .map((h) => DropdownMenuItem(value: h, child: Text(h)))
                      .toList(),
                  onChanged: (val) {
                    setDialogState(() {
                      selectedHall = val;
                      selectedDay = null;
                      selectedShift = null;
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedDay,
                  decoration: const InputDecoration(
                    labelText: 'Day',
                    border: OutlineInputBorder(),
                  ),
                  items: daysForHall
                      .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: selectedHall == null
                      ? null
                      : (val) {
                          setDialogState(() {
                            selectedDay = val;
                            selectedShift = null;
                          });
                        },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedShift,
                  decoration: const InputDecoration(
                    labelText: 'Shift',
                    border: OutlineInputBorder(),
                  ),
                  items: shiftsForHallDay
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: selectedDay == null
                      ? null
                      : (val) {
                          setDialogState(() {
                            selectedShift = val;
                          });
                        },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    (selectedHall != null &&
                        selectedDay != null &&
                        selectedShift != null)
                    ? () {
                        Navigator.pop(ctx);
                        _addAssignment(
                          staffId,
                          selectedHall!,
                          selectedDay!,
                          selectedShift!,
                        );
                      }
                    : null,
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  int _dayOrder(String day) {
    const order = {
      'Saturday': 1,
      'Sunday': 2,
      'Monday': 3,
      'Tuesday': 4,
      'Wednesday': 5,
      'Thursday': 6,
    };
    return order[day] ?? 99;
  }

  int _shiftOrder(String shift) {
    const order = {'AM': 1, 'PM': 2, 'LPM': 3, 'NIGHT': 4};
    return order[shift] ?? 99;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nurse Assignments'),
        backgroundColor: const Color.fromARGB(255, 43, 138, 161),
        foregroundColor: Colors.white,
        actions: [
          if (_stagedAdditions.isNotEmpty || _stagedDeletions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: _isSaving ? null : _saveAllChanges,
                icon: const Icon(Icons.cloud_upload, color: Colors.white),
                label: const Text('Save All', style: TextStyle(color: Colors.white)),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.orange.shade800,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _nurses.isEmpty
          ? const Center(child: Text('No nurses found'))
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _nurses.length,
                        itemBuilder: (context, index) {
                          final nurse = _nurses[index];
                          final staffId = nurse['medicalstaffid'] as int;
                          final nurseName = nurse['name'] as String;
                          final assignments = _nurseAssignments[staffId] ?? [];
                          final patientCount = _patientCounts[staffId] ?? 0;
                          final isOnLeave = nurse['is_on_leave'] == true;

                          return _buildNurseCard(
                            staffId: staffId,
                            nurseName: nurseName,
                            assignments: assignments,
                            patientCount: patientCount,
                            isOnLeave: isOnLeave,
                          );
                        },
                      ),
                      if (_isSaving)
                        Container(
                          color: Colors.black26,
                          child: const Center(
                            child: Card(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(height: 16),
                                    Text('Saving...'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Bottom bar showing patient status counts
                SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Unassigned patients row
                      if (_unassignedPatientCount > 0)
                        InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PatientListScreen(
                                  filterMode: PatientFilterMode.unassigned,
                                ),
                              ),
                            );
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 16,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              border: Border(
                                top: BorderSide(color: Colors.grey.shade300),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.orange.shade800,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '$_unassignedPatientCount patient(s) not assigned to any nurse',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.orange.shade900,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_forward_ios,
                                  size: 14,
                                  color: Colors.orange.shade700,
                                ),
                              ],
                            ),
                          ),
                        ),
                      // Patients with nurse on leave row
                      if (_patientsWithNurseOnLeaveCount > 0)
                        InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PatientListScreen(
                                  filterMode: PatientFilterMode.nurseOnLeave,
                                  nurseOnLeaveIds: _nursesOnLeaveIds.toList(),
                                ),
                              ),
                            );
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 16,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade100,
                              border: Border(
                                top: BorderSide(color: Colors.grey.shade300),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.person_off,
                                  color: Colors.purple.shade800,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '$_patientsWithNurseOnLeaveCount patient(s) whose nurse is on leave',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.purple.shade900,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_forward_ios,
                                  size: 14,
                                  color: Colors.purple.shade700,
                                ),
                              ],
                            ),
                          ),
                        ),
                      // All good message when no issues
                      if (_unassignedPatientCount == 0 &&
                          _patientsWithNurseOnLeaveCount == 0)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 16,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            border: Border(
                              top: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: Colors.green.shade800,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'All patients are covered',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green.shade900,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildNurseCard({
    required int staffId,
    required String nurseName,
    required List<Map<String, dynamic>> assignments,
    required int patientCount,
    required bool isOnLeave,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Opacity(
        opacity: isOnLeave ? 0.7 : 1.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with nurse name
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isOnLeave ? Colors.orange.shade50 : Colors.teal.shade50,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        backgroundColor: isOnLeave
                            ? Colors.orange.shade700
                            : Colors.teal.shade700,
                        child: Text(
                          nurseName.isNotEmpty
                              ? nurseName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (isOnLeave)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.beach_access,
                              size: 10,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: InkWell(
                                onTap: () =>
                                    _openNursePatients(staffId, nurseName),
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2,
                                    horizontal: 2,
                                  ),
                                  child: Text(
                                    nurseName,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: isOnLeave
                                          ? Colors.orange.shade900
                                          : Colors.teal.shade900,
                                      decoration: TextDecoration.underline,
                                      decorationColor: isOnLeave
                                          ? Colors.orange.shade900
                                          : Colors.teal.shade900,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                            if (isOnLeave)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade200,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'On Leave',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade900,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        Text(
                          '${assignments.length} assignment(s)',
                          style: TextStyle(
                            fontSize: 12,
                            color: isOnLeave
                                ? Colors.orange.shade600
                                : Colors.teal.shade600,
                          ),
                        ),
                        Text(
                          'Tap name to view patients',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Leave toggle button
                  IconButton(
                    icon: Icon(
                      isOnLeave ? Icons.work : Icons.beach_access,
                      color: widget.isAdmin
                          ? (isOnLeave ? Colors.green : Colors.orange)
                          : Colors.grey,
                    ),
                    tooltip: widget.isAdmin
                        ? (isOnLeave ? 'Mark as Returned' : 'Mark as On Leave')
                        : 'Admin only',
                    onPressed: widget.isAdmin
                        ? () => _toggleNurseLeave(staffId, nurseName, isOnLeave)
                        : null,
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.add_circle,
                      color: (!widget.isAdmin || isOnLeave)
                          ? Colors.grey
                          : Colors.teal,
                    ),
                    tooltip: widget.isAdmin ? 'Add Assignment' : 'Admin only',
                    onPressed: (!widget.isAdmin || isOnLeave)
                        ? null
                        : () => _showAddAssignmentDialog(staffId, nurseName),
                  ),
                ],
              ),
            ),

            // Assignments list
            if (assignments.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No assignments yet',
                  style: TextStyle(
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else ...[
              // Existing Assignments
              ...assignments.map((assignment) {
                final hall = assignment['ghall'] ?? '';
                final day = assignment['gday'] ?? '';
                final shift = assignment['gshift'] ?? '';
                final key = '$hall-$day-$shift';
                final isDeleted = _stagedDeletions[staffId]?.contains(key) ?? false;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDeleted ? Colors.red.shade50 : null,
                    border: Border(top: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.meeting_room,
                        size: 18,
                        color: isDeleted ? Colors.red : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$hall  •  $day  •  $shift',
                          style: TextStyle(
                            fontSize: 14,
                            decoration: isDeleted ? TextDecoration.lineThrough : null,
                            color: isDeleted ? Colors.red : null,
                          ),
                        ),
                      ),
                      if (isDeleted)
                        IconButton(
                          icon: const Icon(Icons.undo, color: Colors.blue, size: 20),
                          onPressed: () => _revertDelete(staffId, key),
                          tooltip: 'Restore',
                        )
                      else
                        IconButton(
                          icon: Icon(
                            Icons.remove_circle_outline,
                            color: widget.isAdmin ? Colors.red.shade400 : Colors.grey,
                            size: 22,
                          ),
                          onPressed: widget.isAdmin
                              ? () => _removeAssignment(staffId, hall, day, shift)
                              : null,
                        ),
                    ],
                  ),
                );
              }),
              // Staged Additions
              ...(_stagedAdditions[staffId] ?? []).asMap().entries.map((entry) {
                final idx = entry.key;
                final a = entry.value;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Colors.yellow.shade50,
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.add_circle, size: 18, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${a['ghall']}  •  ${a['gday']}  •  ${a['gshift']} (New)',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.cancel, color: Colors.grey, size: 20),
                        onPressed: () => _revertAdd(staffId, idx),
                        tooltip: 'Remove',
                      ),
                    ],
                  ),
                );
              }),
            ],

            // Footer with patient count
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people, size: 18, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Text(
                    '$patientCount patients assigned',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
