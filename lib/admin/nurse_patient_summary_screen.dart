import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'nurse_assignment_screen.dart';

class NursePatientSummaryScreen extends StatefulWidget {
  const NursePatientSummaryScreen({super.key});

  @override
  State<NursePatientSummaryScreen> createState() =>
      _NursePatientSummaryScreenState();
}

class _NursePatientSummaryScreenState extends State<NursePatientSummaryScreen> {
  late Future<List<Map<String, dynamic>>> _summaryFuture;
  String? _selectedHall; // null means 'All'
  List<String> _availableHalls = [];

  // Achievement target (default 20, loaded from SharedPreferences)
  static const String _achievementTargetKey = 'achievement_target';
  int _achievementTarget = 20;

  @override
  void initState() {
    super.initState();
    _loadSettingsAndFetchData();
  }

  Future<void> _loadSettingsAndFetchData() async {
    // Load achievement target
    final prefs = await SharedPreferences.getInstance();
    final savedTarget = prefs.getInt(_achievementTargetKey);
    if (savedTarget != null && savedTarget > 0) {
      setState(() => _achievementTarget = savedTarget);
    }
    // Fetch summary data
    setState(() {
      _summaryFuture = _fetchSummary();
    });
  }

  Future<List<Map<String, dynamic>>> _fetchSummary() async {
    try {
      final response = await Supabase.instance.client
          .from('nurse_patient_summary')
          .select();

      final List<Map<String, dynamic>> data = List<Map<String, dynamic>>.from(
        response as List,
      );

      // Load nurses currently marked on leave to exclude them from ranking rows.
      final onLeaveResponse = await Supabase.instance.client
          .from('staff')
          .select('medicalstaffid, name, fullname')
          .eq('staffrole', 'Nurse')
          .eq('is_on_leave', true);
      final onLeaveRows = List<Map<String, dynamic>>.from(onLeaveResponse as List);
      final onLeaveIds = <int>{};
      final onLeaveNames = <String>{};
      for (final row in onLeaveRows) {
        final id = int.tryParse((row['medicalstaffid'] ?? '').toString());
        if (id != null) onLeaveIds.add(id);
        final name = (row['name'] ?? '').toString().trim().toLowerCase();
        if (name.isNotEmpty) onLeaveNames.add(name);
        final fullName = (row['fullname'] ?? '').toString().trim().toLowerCase();
        if (fullName.isNotEmpty) onLeaveNames.add(fullName);
      }

      final filteredData = data.where((row) {
        if (row['nurse_name'] == 'TOTAL') return true;
        return !_isOnLeaveNurseRow(row, onLeaveIds, onLeaveNames);
      }).toList();

      // Sort so TOTAL is first, then others by percentage descending.
      filteredData.sort((a, b) {
        if (a['nurse_name'] == 'TOTAL') return -1;
        if (b['nurse_name'] == 'TOTAL') return 1;
        final double? pctA = double.tryParse(a['bw_percentage'].toString());
        final double? pctB = double.tryParse(b['bw_percentage'].toString());
        if (pctA != null && pctB != null) {
          return pctB.compareTo(pctA);
        }
        return 0;
      });

      // Extract unique halls from visible rows.
      final halls = <String>{};
      for (var row in filteredData) {
        final groups = row['assigned_groups']?.toString() ?? '';
        if (groups.isNotEmpty) {
          final groupList = groups.split(' | ');
          for (var group in groupList) {
            final parts = group.split('-');
            if (parts.isNotEmpty) {
              halls.add(parts[0]);
            }
          }
        }
      }
      _availableHalls = halls.toList()..sort();

      return filteredData;
    } catch (e) {
      throw Exception('Error loading summary: $e');
    }
  }

  bool _isOnLeaveNurseRow(
    Map<String, dynamic> row,
    Set<int> onLeaveIds,
    Set<String> onLeaveNames,
  ) {
    final nurseName = (row['nurse_name'] ?? '').toString().trim().toLowerCase();
    if (nurseName.isNotEmpty && onLeaveNames.contains(nurseName)) {
      return true;
    }

    for (final key in ['medicalstaffid', 'staffid', 'nurse_id', 'nstaffid']) {
      final id = int.tryParse((row[key] ?? '').toString());
      if (id != null && onLeaveIds.contains(id)) {
        return true;
      }
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nurse Patient Summary'),
        backgroundColor: const Color.fromARGB(255, 43, 138, 161),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.assignment_ind),
            tooltip: 'View Nurse Assignments',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      const NurseAssignmentScreen(isAdmin: false),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              setState(() {
                _summaryFuture = _fetchSummary();
              });
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _summaryFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: SelectableText(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No data found'));
          }

          final allData = snapshot.data!;

          // Filter data by selected hall
          final data = _selectedHall == null
              ? allData
              : allData.where((row) {
                  if (row['nurse_name'] == 'TOTAL')
                    return false; // Hide TOTAL when filtering
                  final groups = row['assigned_groups']?.toString() ?? '';
                  return groups.contains(_selectedHall!);
                }).toList();

          return Column(
            children: [
              // Hall Filter
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.teal.shade50,
                child: Row(
                  children: [
                    const Icon(Icons.filter_list, color: Colors.teal),
                    const SizedBox(width: 12),
                    const Text(
                      'Filter by Hall:',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedHall,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('All Halls'),
                          ),
                          ..._availableHalls.map(
                            (hall) => DropdownMenuItem(
                              value: hall,
                              child: Text(hall),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() => _selectedHall = value);
                        },
                      ),
                    ),
                    // Reset button - shows only when a hall is selected
                    if (_selectedHall != null)
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        tooltip: 'Reset to All Halls',
                        onPressed: () {
                          setState(() => _selectedHall = null);
                        },
                      ),
                  ],
                ),
              ),
              // Data Table
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          Colors.teal.shade50,
                        ),
                        dataRowColor: WidgetStateProperty.resolveWith<Color?>((
                          Set<WidgetState> states,
                        ) {
                          return null; // Default
                        }),
                        border: TableBorder.all(
                          color: Colors.grey.shade300,
                          width: 1,
                          borderRadius: BorderRadius.circular(8),
                          style: BorderStyle.none,
                        ),
                        columns: const [
                          DataColumn(
                            label: Text(
                              'Nurse',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Achievement',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            numeric: true,
                          ),
                          DataColumn(
                            label: Text(
                              'Assigned Groups',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              'Total Patients',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            numeric: true,
                          ),
                          DataColumn(
                            label: Text(
                              'BW Entered',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            numeric: true,
                          ),
                        ],
                        rows: data.asMap().entries.map((entry) {
                          final index = entry.key;
                          final row = entry.value;
                          final bool isTotal = row['nurse_name'] == 'TOTAL';

                          // Style for TOTAL row
                          final TextStyle textStyle = isTotal
                              ? const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.black,
                                )
                              : const TextStyle(fontSize: 14);

                          final Color? rowColor = isTotal
                              ? Colors.amber.shade100
                              : (index % 2 == 0
                                    ? Colors.grey.shade50
                                    : Colors.white);

                          return DataRow(
                            color: WidgetStateProperty.all(rowColor),
                            cells: [
                              DataCell(
                                Text(
                                  row['nurse_name']?.toString() ?? '-',
                                  style: textStyle,
                                ),
                              ),
                              DataCell(
                                _buildPercentageCell(
                                  row['bw_entered_this_month'],
                                  row['total_patients'],
                                  textStyle,
                                  isTotal,
                                ),
                              ),
                              DataCell(
                                _buildAssignedGroupsCell(
                                  row['assigned_groups'],
                                  row['nurse_name'],
                                  isTotal,
                                ),
                              ),
                              DataCell(
                                Text(
                                  row['total_patients']?.toString() ?? '0',
                                  style: textStyle,
                                ),
                              ),
                              DataCell(
                                _buildBwEnteredCell(
                                  row['bw_entered_this_month'],
                                  row['total_patients'],
                                  textStyle,
                                  isTotal,
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPercentageCell(
    dynamic bwEntered,
    dynamic totalPatients,
    TextStyle style,
    bool isTotal,
  ) {
    final int enteredCount = int.tryParse(bwEntered?.toString() ?? '0') ?? 0;
    final int totalCount = int.tryParse(totalPatients?.toString() ?? '0') ?? 0;

    // For TOTAL row: use actual total patients
    // For individual nurses: use achievement target
    final double pct;
    if (isTotal) {
      // TOTAL row: actual percentage of BW entered vs total patients
      pct = totalCount > 0 ? (enteredCount / totalCount) * 100 : 0;
    } else {
      // Individual nurses: percentage based on achievement target
      pct = _achievementTarget > 0
          ? (enteredCount / _achievementTarget) * 100
          : 0;
    }

    // Color coding for percentage (supports >100%)
    Color textColor = style.color ?? Colors.black;
    Color bgColor = Colors.grey.shade100;
    IconData? icon;

    if (!isTotal) {
      if (pct >= 100) {
        textColor = Colors.purple.shade700; // Exceptional - over 100%
        bgColor = Colors.purple.shade50;
        icon = Icons.star;
      } else if (pct >= 80) {
        textColor = Colors.green.shade700; // Excellent
        bgColor = Colors.green.shade50;
        icon = Icons.check_circle;
      } else if (pct >= 50) {
        textColor = Colors.orange.shade800; // Good
        bgColor = Colors.orange.shade50;
      } else if (pct > 0) {
        textColor = Colors.blue.shade700; // In progress
        bgColor = Colors.blue.shade50;
      } else {
        textColor = Colors.red.shade700; // Not started
        bgColor = Colors.red.shade50;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: isTotal
          ? null
          : BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: textColor.withOpacity(0.3)),
            ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isTotal && icon != null) Icon(icon, size: 14, color: textColor),
          if (!isTotal && icon != null) const SizedBox(width: 4),
          Text(
            '${pct.toStringAsFixed(1)}%',
            style: style.copyWith(
              color: isTotal ? null : textColor,
              fontWeight: isTotal ? null : FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBwEnteredCell(
    dynamic entered,
    dynamic total,
    TextStyle style,
    bool isTotal,
  ) {
    final int enteredCount = int.tryParse(entered?.toString() ?? '0') ?? 0;
    final int totalCount = int.tryParse(total?.toString() ?? '0') ?? 0;

    // For TOTAL row: show entered / total patients
    // For individual nurses: show entered / achievement target
    final String displayText = isTotal
        ? '$enteredCount / $totalCount'
        : '$enteredCount / $_achievementTarget';

    return Text(
      displayText,
      style: style.copyWith(
        color: enteredCount > 0 ? Colors.green.shade700 : null,
      ),
    );
  }

  Widget _buildAssignedGroupsCell(
    dynamic assignedGroups,
    dynamic nurseName,
    bool isTotal,
  ) {
    if (isTotal ||
        assignedGroups == null ||
        assignedGroups.toString().isEmpty) {
      return const Text('-', style: TextStyle(color: Colors.grey));
    }

    return InkWell(
      onTap: () {
        _showAssignedGroupsDialog(
          nurseName?.toString() ?? 'Nurse',
          assignedGroups.toString(),
        );
      },
      child: const Text(
        'View',
        style: TextStyle(
          color: Colors.blue,
          decoration: TextDecoration.underline,
          decorationColor: Colors.blue,
        ),
      ),
    );
  }

  void _showAssignedGroupsDialog(String nurseName, String groupsString) {
    // Parse groups: "Hall-Day-Shift | Hall-Day-Shift" format
    final groups = groupsString.split(' | ');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.assignment_ind, color: Colors.teal),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$nurseName - Assignments',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: groups.map((group) {
              final parts = group.split('-');
              final hall = parts.isNotEmpty ? parts[0] : '-';
              final day = parts.length > 1 ? parts[1] : '-';
              final shift = parts.length > 2 ? parts[2] : '-';

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.teal.shade200),
                ),
                child: Row(
                  children: [
                    _buildGroupChip('Hall', hall, Colors.blue),
                    const SizedBox(width: 8),
                    _buildGroupChip('Day', day, Colors.orange),
                    const SizedBox(width: 8),
                    _buildGroupChip('Shift', shift, Colors.purple),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupChip(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
