import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NurseAssignmentScreen extends StatefulWidget {
  const NurseAssignmentScreen({super.key});

  @override
  State<NurseAssignmentScreen> createState() => _NurseAssignmentScreenState();
}

class _NurseAssignmentScreenState extends State<NurseAssignmentScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _nurses = [];
  final Map<String, int?> _assignments =
      {}; // Key: "hall-shift-day", Value: staffid
  final Map<String, int?> _originalAssignments =
      {}; // Original values from database
  // Grouped data structure: Key = Hall Name, Value = List of group objects
  Map<String, List<Map<String, dynamic>>> _groupedGroups = {};

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final client = Supabase.instance.client;

      // 1. Fetch Groups
      final groupsResponse = await client
          .from('groupsofpatients')
          .select()
          .eq('ismain', true) // Filter by ismain = true
          .order('ghall')
          .order('gday')
          .order('gshift');

      // 2. Fetch Nurses (Staff)
      final staffResponse = await client
          .from('staff')
          .select('medicalstaffid, name, staffrole')
          .eq('staffrole', 'Nurse') // Assuming we only assign nurses
          .order('name');

      setState(() {
        _groups = List<Map<String, dynamic>>.from(groupsResponse);
        _nurses = List<Map<String, dynamic>>.from(staffResponse);

        // Group by Hall
        _groupedGroups = {};
        for (var group in _groups) {
          final hall = group['ghall'] as String;
          if (!_groupedGroups.containsKey(hall)) {
            _groupedGroups[hall] = [];
          }
          _groupedGroups[hall]!.add(group);

          // Initialize assignments
          final key = _makeKey(group);
          _assignments[key] = group['staffid'];
          _originalAssignments[key] = group['staffid'];
        }
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

  String _makeKey(Map<String, dynamic> group) {
    return '${group['ghall']}-${group['gshift']}-${group['gday']}';
  }

  bool get _hasUnsavedChanges {
    for (var key in _assignments.keys) {
      if (_assignments[key] != _originalAssignments[key]) {
        return true;
      }
    }
    return false;
  }

  void _updateLocalAssignment(Map<String, dynamic> group, int? staffId) {
    final key = _makeKey(group);
    setState(() {
      _assignments[key] = staffId;
    });
  }

  Future<void> _saveAllAssignments() async {
    // Find changed assignments
    final changedKeys = _assignments.keys
        .where((key) => _assignments[key] != _originalAssignments[key])
        .toList();

    if (changedKeys.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No changes to save'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final client = Supabase.instance.client;

      // Update each changed group
      for (var key in changedKeys) {
        final parts = key.split('-');
        final hall = parts[0];
        final shift = parts[1];
        final day = parts[2];

        await client
            .from('groupsofpatients')
            .update({'staffid': _assignments[key]})
            .match({'ghall': hall, 'gshift': shift, 'gday': day});

        // Update original to match current
        _originalAssignments[key] = _assignments[key];
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved ${changedKeys.length} assignment(s) successfully!',
            ),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {}); // Refresh UI to update button state
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save assignments: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final halls = _groupedGroups.keys.toList();

    // Custom expansion state tracking
    // We use a local key for the ExpansionPanelList to force rebuilds when data changes effectively
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nurse Assignment'),
        backgroundColor: const Color.fromARGB(255, 43, 138, 161),
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilledButton.icon(
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save, size: 20),
              label: Text(_isSaving ? 'Saving...' : 'Save'),
              style: FilledButton.styleFrom(
                backgroundColor: _hasUnsavedChanges
                    ? Colors.red
                    : const Color.fromARGB(255, 6, 107, 95),
                foregroundColor: Colors.white,
              ),
              onPressed: _isSaving ? null : _saveAllAssignments,
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _groupedGroups.isEmpty
          ? const Center(child: Text('No groups found'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _ExpansionListWrapper(
                halls: halls,
                groupedGroups: _groupedGroups,
                nurses: _nurses,
                assignments: _assignments,
                onAssignmentChanged: _updateLocalAssignment,
              ),
            ),
    );
  }
}

class _ExpansionListWrapper extends StatefulWidget {
  final List<String> halls;
  final Map<String, List<Map<String, dynamic>>> groupedGroups;
  final List<Map<String, dynamic>> nurses;
  final Map<String, int?> assignments;
  final Function(Map<String, dynamic>, int?) onAssignmentChanged;

  const _ExpansionListWrapper({
    required this.halls,
    required this.groupedGroups,
    required this.nurses,
    required this.assignments,
    required this.onAssignmentChanged,
  });

  @override
  State<_ExpansionListWrapper> createState() => _ExpansionListWrapperState();
}

class _ExpansionListWrapperState extends State<_ExpansionListWrapper> {
  // Track which panel is expanded by index. -1 means none.
  // Using a separate stateful widget to manage the expansion state easily
  // while keeping the parent fetching logic clean.
  int? _expandedIndex;

  @override
  Widget build(BuildContext context) {
    return ExpansionPanelList(
      elevation: 1,
      expandedHeaderPadding: const EdgeInsets.symmetric(vertical: 8),
      expansionCallback: (int index, bool isExpanded) {
        setState(() {
          // Toggle: if currently expanded (index matches), close it (null).
          // Otherwise, open the clicked one (index).
          _expandedIndex = (_expandedIndex == index) ? null : index;
        });
      },
      children: widget.halls.asMap().entries.map<ExpansionPanel>((entry) {
        final index = entry.key;
        final hallName = entry.value;
        final groups = widget.groupedGroups[hallName]!;
        final isExpanded = _expandedIndex == index;

        return ExpansionPanel(
          headerBuilder: (BuildContext context, bool isExpanded) {
            return ListTile(
              leading: Icon(
                Icons.meeting_room,
                color: isExpanded ? Colors.teal : Colors.grey,
              ),
              title: Text(
                'Hall: $hallName',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: isExpanded ? Colors.teal.shade900 : Colors.black87,
                ),
              ),
            );
          },
          body: Column(
            children: groups.map((group) {
              final key =
                  '${group['ghall']}-${group['gshift']}-${group['gday']}'; // Re-gen key locally or pass function
              final currentStaffId = widget.assignments[key];

              return Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                  color: Colors.grey.shade50,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    // Shift/Day Info
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group['gday'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            group['gshift'] ?? '',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Dropdown
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<int>(
                        value: currentStaffId,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 0,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          isDense: true,
                          fillColor: Colors.white,
                          filled: true,
                        ),
                        items: [
                          const DropdownMenuItem<int>(
                            value: null,
                            child: Text(
                              'Unassigned',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          ...widget.nurses.map((nurse) {
                            return DropdownMenuItem<int>(
                              value: nurse['medicalstaffid'],
                              child: Text(
                                nurse['name'],
                                style: const TextStyle(fontSize: 14),
                              ),
                            );
                          }).toList(),
                        ],
                        onChanged: (newId) {
                          widget.onAssignmentChanged(group, newId);
                        },
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          isExpanded: isExpanded,
          canTapOnHeader: true,
        );
      }).toList(),
    );
  }
}
