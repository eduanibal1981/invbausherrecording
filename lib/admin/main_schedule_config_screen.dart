import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MainScheduleConfigScreen extends StatefulWidget {
  const MainScheduleConfigScreen({super.key});

  @override
  State<MainScheduleConfigScreen> createState() =>
      _MainScheduleConfigScreenState();
}

class _MainScheduleConfigScreenState extends State<MainScheduleConfigScreen> {
  List<Map<String, dynamic>> _mainSchedules = []; // Groups where ismain = true
  List<Map<String, dynamic>> _allGroups =
      []; // All groups from groupsofpatients
  bool _isLoading = true;
  bool _isSyncing = false;
  String? _expandedHall; // Track which hall is expanded (accordion behavior)
  final Set<String> _savingCollectionKeys = {};

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final client = Supabase.instance.client;

      // Fetch all groups from groupsofpatients
      final allGroupsResponse = await client
          .from('groupsofpatients')
          .select()
          .order('ghall')
          .order('gday')
          .order('gshift');

      final allGroups = List<Map<String, dynamic>>.from(allGroupsResponse);

      // Filter to get only those marked as main
      final mainSchedules = allGroups
          .where((g) => g['ismain'] == true)
          .toList();

      setState(() {
        _allGroups = allGroups;
        _mainSchedules = mainSchedules;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _addMainSchedule(String hall, String day, String shift) async {
    try {
      // Update the existing group to mark it as main
      await Supabase.instance.client
          .from('groupsofpatients')
          .update({'ismain': true})
          .eq('ghall', hall)
          .eq('gday', day)
          .eq('gshift', shift);

      await _fetchData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Marked as main: $hall - $day - $shift'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _removeMainSchedule(
    String hall,
    String day,
    String shift,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from Main Schedules?'),
        content: Text('Unmark "$hall - $day - $shift" as a main schedule?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await Supabase.instance.client
          .from('groupsofpatients')
          .update({'ismain': false})
          .eq('ghall', hall)
          .eq('gday', day)
          .eq('gshift', shift);

      await _fetchData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed from main: $hall - $day - $shift'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _syncMainSchedules() async {
    setState(() => _isSyncing = true);
    try {
      final client = Supabase.instance.client;
      int totalUpdated = 0;

      // For each main schedule (where ismain = true), update matching patients
      for (var schedule in _mainSchedules) {
        final hall = schedule['ghall'];
        final day = schedule['gday'];
        final shift = schedule['gshift'];

        // Find patients who have this schedule in their schedules table
        final patientsWithSchedule = await client
            .from('schedules')
            .select('pcid')
            .eq('hallname', hall)
            .eq('day', day)
            .eq('shift', shift);

        if (patientsWithSchedule.isNotEmpty) {
          final pcids = (patientsWithSchedule as List)
              .map((s) => s['pcid'])
              .toList();

          // Update patients table with main schedule
          await client
              .from('patients')
              .update({'hall_main': hall, 'day_main': day, 'shift_main': shift})
              .inFilter('pcid', pcids);

          totalUpdated += pcids.length;
        }
      }

      // Also sync staff assignments after updating main schedules
      await client.rpc('sync_all_patients_staffid');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync complete! Updated $totalUpdated patient(s)'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error syncing: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  String _scheduleKey(String hall, String day, String shift) =>
      '$hall|$day|$shift';

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  String _formatDateForDb(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _formatDateForDisplay(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year.toString();
    return '$d/$m/$y';
  }

  Future<bool> _updateCollectionFields(
    String hall,
    String day,
    String shift, {
    required bool isCollected,
    DateTime? bwDate,
    DateTime? pthDate,
    DateTime? ironDate,
  }) async {
    final key = _scheduleKey(hall, day, shift);
    setState(() => _savingCollectionKeys.add(key));

    try {
      final updates = <String, dynamic>{
        'ismcollected': isCollected,
        'collectiontime_bw': bwDate == null ? null : _formatDateForDb(bwDate),
        'collectiontime_pth': pthDate == null
            ? null
            : _formatDateForDb(pthDate),
        'collectiontime_iron': ironDate == null
            ? null
            : _formatDateForDb(ironDate),
      };

      await Supabase.instance.client
          .from('groupsofpatients')
          .update(updates)
          .eq('ghall', hall)
          .eq('gday', day)
          .eq('gshift', shift);

      if (!mounted) return true;
      setState(() {
        for (final list in [_mainSchedules, _allGroups]) {
          final idx = list.indexWhere(
            (g) =>
                g['ghall'] == hall && g['gday'] == day && g['gshift'] == shift,
          );
          if (idx == -1) continue;
          list[idx]['ismcollected'] = isCollected;
          list[idx]['collectiontime_bw'] = bwDate == null
              ? null
              : _formatDateForDb(bwDate);
          list[idx]['collectiontime_pth'] = pthDate == null
              ? null
              : _formatDateForDb(pthDate);
          list[idx]['collectiontime_iron'] = ironDate == null
              ? null
              : _formatDateForDb(ironDate);
        }
      });
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating collection info: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _savingCollectionKeys.remove(key));
      }
    }
  }

  Future<void> _showCollectionSetupBottomSheet(
    String hall,
    String day,
    String shift,
    Map<String, dynamic> schedule,
  ) async {
    final key = _scheduleKey(hall, day, shift);
    if (_savingCollectionKeys.contains(key)) return;

    bool isCollected = schedule['ismcollected'] == true;
    DateTime? bwDate = _parseDate(schedule['collectiontime_bw']);
    DateTime? pthDate = _parseDate(schedule['collectiontime_pth']);
    DateTime? ironDate = _parseDate(schedule['collectiontime_iron']);
    bool isSaving = false;

    Future<DateTime?> pickDate(DateTime? currentValue, String label) async {
      final now = DateTime.now();
      final initialDate = currentValue ?? now;
      return showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: DateTime(now.year - 3, 1, 1),
        lastDate: DateTime(now.year + 3, 12, 31),
        helpText: 'Select $label collection date',
      );
    }

    Widget buildDateRow(
      String label,
      DateTime? value,
      ValueChanged<DateTime?> onChanged,
      StateSetter setSheetState,
    ) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey.shade50,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value == null
                        ? 'No date set'
                        : _formatDateForDisplay(value),
                    style: TextStyle(
                      fontSize: 12,
                      color: value == null
                          ? Colors.grey.shade600
                          : Colors.teal.shade700,
                    ),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: isSaving
                  ? null
                  : () async {
                      final picked = await pickDate(value, label);
                      if (picked == null) return;
                      setSheetState(() => onChanged(picked));
                    },
              icon: const Icon(Icons.event, size: 16),
              label: const Text('Set'),
            ),
            IconButton(
              tooltip: 'Clear date',
              onPressed: isSaving || value == null
                  ? null
                  : () => setSheetState(() => onChanged(null)),
              icon: const Icon(Icons.clear, size: 18),
            ),
          ],
        ),
      );
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                14,
                16,
                16 + MediaQuery.of(sheetCtx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$hall - $day - $shift',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Set collection dates by lab type',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: isCollected,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('BW Collected'),
                    subtitle: const Text(
                      'Mark Blood Week collection as completed',
                    ),
                    onChanged: isSaving
                        ? null
                        : (value) =>
                              setSheetState(() => isCollected = value ?? false),
                  ),
                  const SizedBox(height: 6),
                  buildDateRow('Blood Week', bwDate, (value) {
                    bwDate = value;
                  }, setSheetState),
                  buildDateRow('PTH', pthDate, (value) {
                    pthDate = value;
                  }, setSheetState),
                  buildDateRow('Iron', ironDate, (value) {
                    ironDate = value;
                  }, setSheetState),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: isSaving
                          ? null
                          : () async {
                              final navigator = Navigator.of(sheetCtx);
                              setSheetState(() => isSaving = true);
                              final success = await _updateCollectionFields(
                                hall,
                                day,
                                shift,
                                isCollected: isCollected,
                                bwDate: bwDate,
                                pthDate: pthDate,
                                ironDate: ironDate,
                              );

                              if (!mounted) return;
                              if (success) {
                                if (navigator.canPop()) navigator.pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Collection details updated successfully',
                                    ),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              } else {
                                setSheetState(() => isSaving = false);
                              }
                            },
                      icon: isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save),
                      label: Text(
                        isSaving ? 'Saving...' : 'Save Collection Details',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAddDialog() {
    // Get groups that are NOT already marked as main
    final availableGroups = _allGroups
        .where((g) => g['ismain'] != true)
        .toList();

    if (availableGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All schedules are already marked as main'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    String? selectedHall;
    String? selectedDay;
    String? selectedShift;

    // Get unique halls from available groups
    final halls =
        availableGroups.map((g) => g['ghall'] as String).toSet().toList()
          ..sort();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          // Filter days based on selected hall
          final daysForHall = selectedHall != null
              ? availableGroups
                    .where((g) => g['ghall'] == selectedHall)
                    .map((g) => g['gday'] as String)
                    .toSet()
                    .toList()
              : <String>[];
          daysForHall.sort(_compareDays);

          // Filter shifts based on selected hall and day
          final shiftsForHallDay = (selectedHall != null && selectedDay != null)
              ? availableGroups
                    .where(
                      (g) =>
                          g['ghall'] == selectedHall &&
                          g['gday'] == selectedDay,
                    )
                    .map((g) => g['gshift'] as String)
                    .toSet()
                    .toList()
              : <String>[];
          shiftsForHallDay.sort();

          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.add_circle, color: Colors.teal.shade700),
                const SizedBox(width: 8),
                const Text('Add Main Schedule'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Hall dropdown
                DropdownButtonFormField<String>(
                  key: const ValueKey('hall_dropdown'),
                  initialValue: selectedHall,
                  decoration: InputDecoration(
                    labelText: 'Hall',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items: halls
                      .map((h) => DropdownMenuItem(value: h, child: Text(h)))
                      .toList(),
                  onChanged: (v) {
                    setDialogState(() {
                      selectedHall = v;
                      selectedDay = null;
                      selectedShift = null;
                    });
                  },
                ),
                const SizedBox(height: 16),
                // Day dropdown
                DropdownButtonFormField<String>(
                  key: ValueKey('day_dropdown_$selectedHall'),
                  initialValue: selectedDay,
                  decoration: InputDecoration(
                    labelText: 'Day',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items: daysForHall
                      .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: selectedHall == null
                      ? null
                      : (v) {
                          setDialogState(() {
                            selectedDay = v;
                            selectedShift = null;
                          });
                        },
                ),
                const SizedBox(height: 16),
                // Shift dropdown
                DropdownButtonFormField<String>(
                  key: ValueKey('shift_dropdown_${selectedHall}_$selectedDay'),
                  initialValue: selectedShift,
                  decoration: InputDecoration(
                    labelText: 'Shift',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items: shiftsForHallDay
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: selectedDay == null
                      ? null
                      : (v) {
                          setDialogState(() => selectedShift = v);
                        },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed:
                    selectedHall != null &&
                        selectedDay != null &&
                        selectedShift != null
                    ? () {
                        Navigator.pop(ctx);
                        _addMainSchedule(
                          selectedHall!,
                          selectedDay!,
                          selectedShift!,
                        );
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
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

  Widget _buildGroupedList() {
    // Group schedules by hall
    final Map<String, List<Map<String, dynamic>>> groupedByHall = {};
    for (var schedule in _mainSchedules) {
      final hall = schedule['ghall'] as String? ?? 'Unknown';
      groupedByHall.putIfAbsent(hall, () => []).add(schedule);
    }

    // Sort halls and schedules within each hall
    final sortedHalls = groupedByHall.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedHalls.length,
      itemBuilder: (context, hallIndex) {
        final hall = sortedHalls[hallIndex];
        final schedules = groupedByHall[hall]!;

        // Sort schedules by day then shift
        schedules.sort((a, b) {
          final dayCompare = _compareDays(a['gday'] ?? '', b['gday'] ?? '');
          if (dayCompare != 0) return dayCompare;
          return (a['gshift'] ?? '').compareTo(b['gshift'] ?? '');
        });

        // Calculate total patients in this hall
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
            key: Key(hall), // Important for proper state management
            initiallyExpanded: _expandedHall == hall,
            onExpansionChanged: (isExpanded) {
              setState(() {
                _expandedHall = isExpanded ? hall : null;
              });
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
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Text(
              '${schedules.length} schedules - $totalPatients patients',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            children: schedules.map((schedule) {
              final day = schedule['gday'] ?? '';
              final shift = schedule['gshift'] ?? '';
              final staffId = schedule['staffid'];
              final patientCount = schedule['gcount'] ?? 0;
              final isCollected = schedule['ismcollected'] == true;
              final scheduleKey = _scheduleKey(hall, day, shift);
              final isSavingCollection = _savingCollectionKeys.contains(
                scheduleKey,
              );

              return Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 4,
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
                          shift == 'AM'
                              ? Icons.wb_sunny
                              : Icons.nightlight_round,
                          color: shift == 'AM'
                              ? Colors.orange.shade700
                              : Colors.indigo.shade700,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        '$day - $shift',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        '$patientCount patients${staffId != null ? ' - Nurse assigned' : ' - No nurse'}${isCollected ? ' - BW collected' : ''}',
                        style: TextStyle(
                          fontSize: 11,
                          color: staffId != null
                              ? Colors.green.shade700
                              : Colors.orange.shade700,
                        ),
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          Icons.remove_circle,
                          color: Colors.red.shade400,
                        ),
                        onPressed: () => _removeMainSchedule(hall, day, shift),
                        tooltip: 'Remove from main schedules',
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(72, 0, 16, 10),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                isCollected
                                    ? 'BW collected: Yes'
                                    : 'BW collected: No',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isCollected
                                      ? Colors.green.shade700
                                      : Colors.grey.shade700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: isSavingCollection
                                  ? null
                                  : () => _showCollectionSetupBottomSheet(
                                      hall,
                                      day,
                                      shift,
                                      schedule,
                                    ),
                              icon: const Icon(Icons.edit_calendar, size: 18),
                              label: const Text('Set Dates'),
                            ),
                            if (isSavingCollection)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Main Schedule Configuration'),
        backgroundColor: const Color.fromARGB(255, 43, 138, 161),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Header info
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.teal.shade50,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.teal.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Define which Hall/Day/Shift combinations are main schedules. '
                              'Click Sync to assign patients who have matching schedules.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.teal.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Sync button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isSyncing || _mainSchedules.isEmpty
                              ? null
                              : _syncMainSchedules,
                          icon: _isSyncing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.sync),
                          label: Text(
                            _isSyncing
                                ? 'Syncing...'
                                : 'Sync Patient Schedules',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Main schedules list
                Expanded(
                  child: _mainSchedules.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 64,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No main schedules defined',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Tap + to add a main schedule',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        )
                      : _buildGroupedList(),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        backgroundColor: Colors.teal,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Add Schedule',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
