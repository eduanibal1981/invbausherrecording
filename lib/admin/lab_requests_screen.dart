import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LabRequestsScreen extends StatefulWidget {
  const LabRequestsScreen({super.key});

  @override
  State<LabRequestsScreen> createState() => _LabRequestsScreenState();
}

class _LabRequestsScreenState extends State<LabRequestsScreen> {
  List<Map<String, dynamic>> _dueSchedules = [];
  bool _isLoading = true;
  String? _expandedHall;

  @override
  void initState() {
    super.initState();
    _fetchDueLabRequests();
  }

  String _todayDbDate() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _displayToday() {
    final now = DateTime.now();
    final d = now.day.toString().padLeft(2, '0');
    final m = now.month.toString().padLeft(2, '0');
    final y = now.year.toString();
    return '$d/$m/$y';
  }

  List<String> _dueLabTypesToday(Map<String, dynamic> row) {
    final today = _todayDbDate();
    final isBwDue =
        (row['collectiontime_bw']?.toString() == today) &&
        (row['ismcollected'] != true);
    final isPthDue = row['collectiontime_pth']?.toString() == today;
    final isIronDue = row['collectiontime_iron']?.toString() == today;

    final due = <String>[];
    if (isBwDue) due.add('BW');
    if (isPthDue) due.add('PTH');
    if (isIronDue) due.add('Iron');
    return due;
  }

  Future<void> _fetchDueLabRequests() async {
    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client
          .from('groupsofpatients')
          .select()
          .eq('ismain', true)
          .order('ghall')
          .order('gday')
          .order('gshift');

      final allMainSchedules = List<Map<String, dynamic>>.from(
        response as List,
      );
      final dueSchedules = allMainSchedules
          .where((row) => _dueLabTypesToday(row).isNotEmpty)
          .toList();

      if (!mounted) return;
      setState(() {
        _dueSchedules = dueSchedules;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading lab requests: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  int _compareDays(String a, String b) {
    const dayOrder = [
      'Saturday',
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
    ];
    return dayOrder.indexOf(a).compareTo(dayOrder.indexOf(b));
  }

  Widget _buildDueChip(String label) {
    Color color = Colors.blue;
    if (label == 'BW') color = Colors.red.shade700;
    if (label == 'PTH') color = Colors.deepPurple.shade700;
    if (label == 'Iron') color = Colors.orange.shade800;

    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Today Lab Requests'),
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
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchDueLabRequests,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  color: Colors.teal.shade50,
                  child: Row(
                    children: [
                      const Icon(Icons.science_outlined, color: Colors.teal),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Showing only schedules with collection date = ${_displayToday()}',
                          style: TextStyle(
                            color: Colors.teal.shade900,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _dueSchedules.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                size: 64,
                                color: Colors.green.shade400,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No lab requests due today',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : _buildGroupedList(),
                ),
              ],
            ),
    );
  }

  Widget _buildGroupedList() {
    final groupedByHall = <String, List<Map<String, dynamic>>>{};
    for (final schedule in _dueSchedules) {
      final hall = schedule['ghall'] as String? ?? 'Unknown';
      groupedByHall.putIfAbsent(hall, () => []).add(schedule);
    }

    final sortedHalls = groupedByHall.keys.toList()..sort();

    return RefreshIndicator(
      onRefresh: _fetchDueLabRequests,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sortedHalls.length,
        itemBuilder: (context, hallIndex) {
          final hall = sortedHalls[hallIndex];
          final schedules = groupedByHall[hall]!;

          schedules.sort((a, b) {
            final dayCompare = _compareDays(a['gday'] ?? '', b['gday'] ?? '');
            if (dayCompare != 0) return dayCompare;
            return (a['gshift'] ?? '').compareTo(b['gshift'] ?? '');
          });

          final totalPatients = schedules.fold<int>(
            0,
            (sum, s) => sum + ((s['gcount'] as int?) ?? 0),
          );

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ExpansionTile(
              key: Key(hall),
              initiallyExpanded: _expandedHall == hall,
              onExpansionChanged: (expanded) {
                setState(() => _expandedHall = expanded ? hall : null);
              },
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.teal.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.location_city, color: Colors.teal.shade700),
              ),
              title: Text(
                hall,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              subtitle: Text(
                '${schedules.length} requests - $totalPatients patients',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              children: schedules.map((schedule) {
                final day = schedule['gday'] ?? '';
                final shift = schedule['gshift'] ?? '';
                final staffId = schedule['staffid'];
                final patientCount = schedule['gcount'] ?? 0;
                final dueLabTypes = _dueLabTypesToday(schedule);

                return Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 6,
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: shift == 'AM'
                            ? Colors.orange.shade100
                            : Colors.indigo.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        shift == 'AM' ? Icons.wb_sunny : Icons.nightlight_round,
                        color: shift == 'AM'
                            ? Colors.orange.shade700
                            : Colors.indigo.shade700,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      '$day - $shift',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        Text(
                          '$patientCount patients${staffId != null ? ' - Nurse assigned' : ' - No nurse'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: staffId != null
                                ? Colors.green.shade700
                                : Colors.orange.shade700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(children: dueLabTypes.map(_buildDueChip).toList()),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }
}
