import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'nurse_assignment_screen.dart';
import 'staff_on_leave_screen.dart';
import '../common/patient_list_screen.dart';

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
  final int _selectedYear = DateTime.now().year;
  late String _selectedMonth;

  static const List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  // Achievement target (default 20, loaded from SharedPreferences)
  static const String _achievementTargetKey = 'achievement_target';
  int _achievementTarget = 20;

  @override
  void initState() {
    super.initState();
    _selectedMonth = _monthNames[DateTime.now().month - 1];
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
      final response = await Supabase.instance.client.rpc(
        'get_nurse_patient_summary',
        params: {
          'in_target_year': _selectedYear,
          'in_target_month': _selectedMonth,
        },
      );

      final List<Map<String, dynamic>> data = List<Map<String, dynamic>>.from(
        response as List,
      );

      // Load nurses currently marked on leave to exclude them from ranking rows.
      final onLeaveResponse = await Supabase.instance.client
          .from('staff')
          .select('medicalstaffid, name, fullname')
          .eq('staffrole', 'Nurse')
          .eq('is_on_leave', true);
      final onLeaveRows = List<Map<String, dynamic>>.from(
        onLeaveResponse as List,
      );
      final onLeaveIds = <int>{};
      final onLeaveNames = <String>{};
      for (final row in onLeaveRows) {
        final id = int.tryParse((row['medicalstaffid'] ?? '').toString());
        if (id != null) onLeaveIds.add(id);
        final name = (row['name'] ?? '').toString().trim().toLowerCase();
        if (name.isNotEmpty) onLeaveNames.add(name);
        final fullName = (row['fullname'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
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
      if (e.toString().contains('get_nurse_patient_summary')) {
        throw Exception(
          'Database function get_nurse_patient_summary is missing. '
          'Apply the latest migration first.',
        );
      }
      throw Exception('Error loading summary: $e');
    }
  }

  List<String> _selectableMonthsForCurrentYear() {
    final currentMonthIndex = DateTime.now().month;
    final available = _monthNames.sublist(0, currentMonthIndex);
    return available.reversed.toList();
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
            icon: const Icon(Icons.home),
            tooltip: 'Return to Home',
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
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
            icon: const Icon(Icons.beach_access),
            tooltip: 'Staff on Leave',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const StaffOnLeaveScreen(),
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
          Map<String, dynamic>? totalRow;
          for (final row in allData) {
            if (row['nurse_name'] == 'TOTAL') {
              totalRow = row;
              break;
            }
          }

          var nurseRows = allData
              .where((row) => row['nurse_name'] != 'TOTAL')
              .toList();

          if (_selectedHall != null) {
            nurseRows = nurseRows.where((row) {
              final groups = row['assigned_groups']?.toString() ?? '';
              return groups.contains(_selectedHall!);
            }).toList();
          }

          nurseRows.sort((a, b) {
            final pctA = _calculateAchievementPct(a);
            final pctB = _calculateAchievementPct(b);
            final pctCompare = pctB.compareTo(pctA);
            if (pctCompare != 0) return pctCompare;

            final enteredA =
                int.tryParse(a['bw_entered_this_month']?.toString() ?? '0') ??
                0;
            final enteredB =
                int.tryParse(b['bw_entered_this_month']?.toString() ?? '0') ??
                0;
            final enteredCompare = enteredB.compareTo(enteredA);
            if (enteredCompare != 0) return enteredCompare;

            final nameA = (a['nurse_name'] ?? '').toString().toLowerCase();
            final nameB = (b['nurse_name'] ?? '').toString().toLowerCase();
            return nameA.compareTo(nameB);
          });

          return Column(
            children: [
              // Filters
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.teal.shade50,
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_month, color: Colors.teal),
                        const SizedBox(width: 12),
                        const Text(
                          'Month:',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedMonth,
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
                            items: _selectableMonthsForCurrentYear()
                                .map(
                                  (month) => DropdownMenuItem(
                                    value: month,
                                    child: Text(month),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null || value == _selectedMonth) {
                                return;
                              }
                              setState(() {
                                _selectedMonth = value;
                                _selectedHall = null;
                                _summaryFuture = _fetchSummary();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.teal.shade200),
                          ),
                          child: Text(
                            '$_selectedYear',
                            style: TextStyle(
                              color: Colors.teal.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.filter_list, color: Colors.teal),
                        const SizedBox(width: 12),
                        const Text(
                          'Hall:',
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
                  ],
                ),
              ),
              if (totalRow != null) _buildTotalSummaryCard(totalRow),
              // Data Table
              Expanded(
                child: nurseRows.isEmpty
                    ? const Center(
                        child: Text('No nurses match the selected filter.'),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: DataTable(
                              headingRowColor: WidgetStateProperty.all(
                                Colors.teal.shade50,
                              ),
                              dataRowColor:
                                  WidgetStateProperty.resolveWith<Color?>((
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
                                    '#',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  numeric: true,
                                ),
                                DataColumn(
                                  label: Text(
                                    'Nurse',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: Text(
                                    'Achievement',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  numeric: true,
                                ),
                                DataColumn(
                                  label: Text(
                                    'Assigned Groups',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: Text(
                                    'Total Patients',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  numeric: true,
                                ),
                                DataColumn(
                                  label: Text(
                                    'BW Entered',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  numeric: true,
                                ),
                              ],
                              rows: nurseRows.asMap().entries.map((entry) {
                                final index = entry.key;
                                final row = entry.value;
                                const textStyle = TextStyle(fontSize: 14);
                                final rowColor = index % 2 == 0
                                    ? Colors.grey.shade50
                                    : Colors.white;

                                return DataRow(
                                  color: WidgetStateProperty.all(rowColor),
                                  cells: [
                                    DataCell(
                                      Text('${index + 1}', style: textStyle),
                                    ),
                                    DataCell(
                                      InkWell(
                                        onTap: () {
                                          final nurseName = row['nurse_name']?.toString() ?? 'Unknown';
                                          int? staffId;
                                          for (final key in ['medicalstaffid', 'staffid', 'nurse_id', 'nstaffid']) {
                                            final id = int.tryParse((row[key] ?? '').toString());
                                            if (id != null) {
                                              staffId = id;
                                              break;
                                            }
                                          }
                                          if (staffId != null) {
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
                                          } else {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Nurse ID not found. Cannot filter.')),
                                            );
                                          }
                                        },
                                        child: Text(
                                          row['nurse_name']?.toString() ?? '-',
                                          style: textStyle.copyWith(
                                            color: Colors.blue.shade700,
                                            decoration: TextDecoration.underline,
                                            decorationColor: Colors.blue.shade700,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      _buildPercentageCell(
                                        row['bw_entered_this_month'],
                                        row['total_patients'],
                                        row['assigned_groups'],
                                        textStyle,
                                        false,
                                      ),
                                    ),
                                    DataCell(
                                      _buildAssignedGroupsCell(
                                        row['assigned_groups'],
                                        row['nurse_name'],
                                        false,
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        row['total_patients']?.toString() ??
                                            '0',
                                        style: textStyle,
                                      ),
                                    ),
                                    DataCell(
                                      _buildBwEnteredCell(
                                        row['bw_entered_this_month'],
                                        row['total_patients'],
                                        row['assigned_groups'],
                                        textStyle,
                                        false,
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

  double _calculateAchievementPct(Map<String, dynamic> row) {
    final enteredCount =
        int.tryParse(row['bw_entered_this_month']?.toString() ?? '0') ?? 0;
    if (_achievementTarget <= 0) return 0;
    return (enteredCount / _achievementTarget) * 100;
  }

  Widget _buildTotalSummaryCard(Map<String, dynamic> row) {
    final int totalPatients =
        int.tryParse(row['total_patients']?.toString() ?? '0') ?? 0;
    final int bwEntered =
        int.tryParse(row['bw_entered_this_month']?.toString() ?? '0') ?? 0;
    final double totalPct = totalPatients > 0
        ? (bwEntered / totalPatients) * 100
        : 0;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.summarize, color: Colors.amber.shade800, size: 18),
              const SizedBox(width: 8),
              Text(
                'Overall Total',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.amber.shade900,
                ),
              ),
            ],
          ),
          _buildTotalMetric('Patients', '$totalPatients'),
          _buildTotalMetric('BW Entered', '$bwEntered'),
          _buildTotalMetric('Achievement', '${totalPct.toStringAsFixed(1)}%'),
          _buildTotalMetric('Period', '$_selectedMonth $_selectedYear'),
        ],
      ),
    );
  }

  Widget _buildTotalMetric(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.black87, fontSize: 13),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildPercentageCell(
    dynamic bwEntered,
    dynamic totalPatients,
    dynamic assignedGroups,
    TextStyle style,
    bool isTotal,
  ) {
    final int enteredCount = int.tryParse(bwEntered?.toString() ?? '0') ?? 0;
    final int totalCount = int.tryParse(totalPatients?.toString() ?? '0') ?? 0;
    final bool hasAssignedGroups = assignedGroups != null &&
        assignedGroups.toString().trim().isNotEmpty;
    final bool isUnassigned =
        !isTotal && (totalCount == 0 || !hasAssignedGroups);

    // If unassigned staff who entered lab data: show star badge instead of percentage
    if (isUnassigned) {
      if (enteredCount > 0) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.shade400),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star, size: 15, color: Colors.amber.shade800),
            ],
          ),
        );
      } else {
        return Text('-', style: style.copyWith(color: Colors.grey));
      }
    }

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
              border: Border.all(color: textColor.withValues(alpha: 0.3)),
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
    dynamic assignedGroups,
    TextStyle style,
    bool isTotal,
  ) {
    final int enteredCount = int.tryParse(entered?.toString() ?? '0') ?? 0;
    final int totalCount = int.tryParse(total?.toString() ?? '0') ?? 0;
    final bool hasAssignedGroups = assignedGroups != null &&
        assignedGroups.toString().trim().isNotEmpty;
    final bool isUnassigned =
        !isTotal && (totalCount == 0 || !hasAssignedGroups);

    // For TOTAL row: show entered / total patients
    // For unassigned staff: show entered count only (no assigned target)
    // For individual nurses: show entered / achievement target
    final String displayText = isTotal
        ? '$enteredCount / $totalCount'
        : isUnassigned
            ? '$enteredCount'
            : '$enteredCount / $_achievementTarget';

    return Text(
      displayText,
      style: style.copyWith(
        color: enteredCount > 0 ? Colors.green.shade700 : null,
        fontWeight: isUnassigned && enteredCount > 0 ? FontWeight.w600 : null,
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
