import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VascularManagementScreen extends StatefulWidget {
  const VascularManagementScreen({super.key});

  @override
  State<VascularManagementScreen> createState() =>
      _VascularManagementScreenState();
}

class _VascularManagementScreenState extends State<VascularManagementScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _records = [];
  List<Map<String, dynamic>> _patients = [];
  bool _isLoading = true;
  bool _currentOnly = false;
  String? _selectedType;

  static const List<String> _accessTypes = ['AVF', 'AVG', 'PERM_CATH'];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _fetchData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final client = Supabase.instance.client;
      final recordsRes = await client
          .from('vascularaccess')
          .select()
          .order('pcid')
          .order('is_currentaccess', ascending: false)
          .order('created_at', ascending: false);

      final patientsRes = await client
          .from('patients')
          .select('pcid, name, status, vaccess')
          .order('name');

      if (!mounted) return;
      setState(() {
        _records = List<Map<String, dynamic>>.from(recordsRes as List);
        _patients = List<Map<String, dynamic>>.from(patientsRes as List);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading vascular dashboard: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _displayDate(DateTime? date) {
    if (date == null) return '-';
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year.toString();
    return '$d/$m/$y';
  }

  String _accessTypeLabel(String type) {
    if (type == 'PERM_CATH') return 'Perm. Cath';
    return type;
  }

  String? _toPatientVaccess(dynamic type) {
    if (type == null) return null;
    final value = type.toString();
    if (value == 'PERM_CATH') return 'Perm. Cath';
    if (value == 'AVF' || value == 'AVG') return value;
    return value;
  }

  Map<int, Map<String, dynamic>> get _patientById {
    final map = <int, Map<String, dynamic>>{};
    for (final p in _patients) {
      final id = _toInt(p['pcid']);
      if (id != null) map[id] = p;
    }
    return map;
  }

  List<Map<String, dynamic>> get _filteredRecords {
    final query = _searchController.text.trim().toLowerCase();
    final patients = _patientById;

    return _records.where((r) {
      final pcid = _toInt(r['pcid']);
      if (pcid == null) return false;

      final patient = patients[pcid];
      final patientName = (patient?['name'] ?? '').toString().toLowerCase();
      final accessType = (r['ac_type'] ?? '').toString();
      final fullName = (r['ac_fullname'] ?? '').toString().toLowerCase();
      final hospital = (r['ac_createdhospital'] ?? '').toString().toLowerCase();

      if (_currentOnly && r['is_currentaccess'] != true) return false;
      if (_selectedType != null && accessType != _selectedType) return false;

      if (query.isEmpty) return true;
      return patientName.contains(query) ||
          pcid.toString().contains(query) ||
          fullName.contains(query) ||
          hospital.contains(query);
    }).toList();
  }

  Future<void> _syncPatientVaccess(int pcid) async {
    final client = Supabase.instance.client;
    final currentRecord = await client
        .from('vascularaccess')
        .select('ac_type')
        .eq('pcid', pcid)
        .eq('is_currentaccess', true)
        .maybeSingle();

    final currentType = currentRecord == null ? null : currentRecord['ac_type'];
    await client
        .from('patients')
        .update({'vaccess': _toPatientVaccess(currentType)})
        .eq('pcid', pcid);
  }

  Future<void> _setAsCurrent(Map<String, dynamic> record) async {
    final pcid = _toInt(record['pcid']);
    final vasid = _toInt(record['vasid']);
    if (pcid == null || vasid == null) return;
    if (record['is_currentaccess'] == true) return;

    try {
      final client = Supabase.instance.client;
      await client
          .from('vascularaccess')
          .update({'is_currentaccess': false})
          .eq('pcid', pcid);
      await client
          .from('vascularaccess')
          .update({'is_currentaccess': true})
          .eq('vasid', vasid);
      await _syncPatientVaccess(pcid);
      await _fetchData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Current access updated'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error setting current access: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteRecord(Map<String, dynamic> record) async {
    final vasid = _toInt(record['vasid']);
    final pcid = _toInt(record['pcid']);
    if (vasid == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Access Record'),
        content: const Text(
          'This will remove the selected vascular access record. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await Supabase.instance.client
          .from('vascularaccess')
          .delete()
          .eq('vasid', vasid);
      if (pcid != null) await _syncPatientVaccess(pcid);
      await _fetchData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Record deleted'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting record: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openEditor({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final activePatients = _patients
        .where((p) => (p['status'] ?? '').toString() == 'Active')
        .toList();

    int? selectedPcid = _toInt(existing?['pcid']);
    String? selectedType = existing?['ac_type']?.toString();
    bool isCurrent = existing?['is_currentaccess'] == true;
    String createdHospitalValue =
        existing?['ac_createdhospital']?.toString() ?? '';
    String nextHospitalValue =
        existing?['nextappointment_hospital']?.toString() ?? '';
    const hospitalSuggestions = <String>[
      'Royal Hospital',
      'Khawla Hspital',
    ];

    final fullNameCtrl = TextEditingController(
      text: existing?['ac_fullname']?.toString() ?? '',
    );
    final infectionCountCtrl = TextEditingController(
      text: existing?['infection_count']?.toString() ?? '',
    );
    final infectionNoteCtrl = TextEditingController(
      text: existing?['infection_note']?.toString() ?? '',
    );
    final angioplastCountCtrl = TextEditingController(
      text: existing?['angioplast_count']?.toString() ?? '',
    );
    final retplaseCountCtrl = TextEditingController(
      text: existing?['retplase_count']?.toString() ?? '',
    );
    final generalNoteCtrl = TextEditingController(
      text: existing?['general_note']?.toString() ?? '',
    );
    final lastPlanCtrl = TextEditingController(
      text: existing?['lastplan_note']?.toString() ?? '',
    );
    final otherHospitalCtrl = TextEditingController(
      text: existing?['otherhospitalneeded']?.toString() ?? '',
    );
    final nextNoteCtrl = TextEditingController(
      text: existing?['nextappointment_note']?.toString() ?? '',
    );

    DateTime? accessCreationDate = _parseDate(existing?['ac_creationdate']);
    DateTime? nextAppointmentDate = _parseDate(
      existing?['nextappointment_date'],
    );
    bool isSaving = false;

    Widget buildHospitalAutocomplete({
      required String label,
      required String initialValue,
      required ValueChanged<String> onChanged,
    }) {
      return Autocomplete<String>(
        initialValue: TextEditingValue(text: initialValue),
        optionsBuilder: (textEditingValue) {
          final query = textEditingValue.text.trim().toLowerCase();
          if (query.isEmpty || isSaving) {
            return const Iterable<String>.empty();
          }
          return hospitalSuggestions.where(
            (hospital) => hospital.toLowerCase().startsWith(query),
          );
        },
        onSelected: onChanged,
        optionsMaxHeight: 180,
        fieldViewBuilder:
            (context, textController, focusNode, onFieldSubmitted) => TextField(
              controller: textController,
              focusNode: focusNode,
              enabled: !isSaving,
              onChanged: onChanged,
              onSubmitted: (_) => onFieldSubmitted(),
              decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
              ),
            ),
      );
    }

    Future<DateTime?> pickDate(DateTime? current, String helpText) async {
      final now = DateTime.now();
      return showDatePicker(
        context: context,
        initialDate: current ?? now,
        firstDate: DateTime(now.year - 20, 1, 1),
        lastDate: DateTime(now.year + 20, 12, 31),
        helpText: helpText,
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
        builder: (sheetCtx, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.of(sheetCtx).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEdit ? 'Edit Vascular Record' : 'New Vascular Record',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownMenu<int>(
                    initialSelection: selectedPcid,
                    enabled: !isSaving && !isEdit,
                    label: Text(
                      isEdit ? 'Patient (Not changeable)' : 'Patient',
                    ),
                    enableSearch: true,
                    enableFilter: true,
                    menuHeight: 320,
                    inputDecorationTheme: const InputDecorationTheme(
                      border: OutlineInputBorder(),
                    ),
                    dropdownMenuEntries: activePatients
                        .map((p) {
                          final pcid = _toInt(p['pcid']);
                          if (pcid == null) return null;
                          return DropdownMenuEntry<int>(
                            value: pcid,
                            label: '${p['name']} ($pcid)',
                          );
                        })
                        .whereType<DropdownMenuEntry<int>>()
                        .toList(),
                    onSelected: isSaving || isEdit
                        ? null
                        : (value) => setSheetState(() => selectedPcid = value),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    decoration: const InputDecoration(
                      labelText: 'Access Type',
                      border: OutlineInputBorder(),
                    ),
                    items: _accessTypes
                        .map(
                          (t) => DropdownMenuItem<String>(
                            value: t,
                            child: Text(_accessTypeLabel(t)),
                          ),
                        )
                        .toList(),
                    onChanged: isSaving
                        ? null
                        : (value) => setSheetState(() => selectedType = value),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: fullNameCtrl,
                    enabled: !isSaving,
                    decoration: const InputDecoration(
                      labelText: 'Access Full Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  buildHospitalAutocomplete(
                    label: 'Created Hospital',
                    initialValue: createdHospitalValue,
                    onChanged: (value) => createdHospitalValue = value,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isSaving
                              ? null
                              : () async {
                                  final picked = await pickDate(
                                    accessCreationDate,
                                    'Access creation date',
                                  );
                                  if (picked == null) return;
                                  setSheetState(
                                    () => accessCreationDate = picked,
                                  );
                                },
                          icon: const Icon(Icons.event),
                          label: Text(
                            accessCreationDate == null
                                ? 'Set creation date'
                                : _displayDate(accessCreationDate),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Clear date',
                        onPressed: isSaving || accessCreationDate == null
                            ? null
                            : () => setSheetState(
                                () => accessCreationDate = null,
                              ),
                        icon: const Icon(Icons.clear),
                      ),
                    ],
                  ),
                  CheckboxListTile(
                    value: isCurrent,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Set as current access'),
                    onChanged: isSaving
                        ? null
                        : (value) =>
                              setSheetState(() => isCurrent = value ?? false),
                  ),
                  const Divider(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: infectionCountCtrl,
                          enabled: !isSaving,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Infection Count',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: angioplastCountCtrl,
                          enabled: !isSaving,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Angioplasty Count',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      if (selectedType == 'PERM_CATH') const SizedBox(width: 8),
                      if (selectedType == 'PERM_CATH')
                        Expanded(
                          child: TextField(
                            controller: retplaseCountCtrl,
                            enabled: !isSaving,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Re-tPAse Count',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: infectionNoteCtrl,
                    enabled: !isSaving,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Infection Note',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: generalNoteCtrl,
                    enabled: !isSaving,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'General Note',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: lastPlanCtrl,
                    enabled: !isSaving,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Last Plan Note',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: otherHospitalCtrl,
                    enabled: !isSaving,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Other Hospital Needed',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const Divider(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isSaving
                              ? null
                              : () async {
                                  final picked = await pickDate(
                                    nextAppointmentDate,
                                    'Next appointment date',
                                  );
                                  if (picked == null) return;
                                  setSheetState(
                                    () => nextAppointmentDate = picked,
                                  );
                                },
                          icon: const Icon(Icons.calendar_month),
                          label: Text(
                            nextAppointmentDate == null
                                ? 'Set next appointment'
                                : _displayDate(nextAppointmentDate),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Clear date',
                        onPressed: isSaving || nextAppointmentDate == null
                            ? null
                            : () => setSheetState(
                                () => nextAppointmentDate = null,
                              ),
                        icon: const Icon(Icons.clear),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  buildHospitalAutocomplete(
                    label: 'Next Appointment Hospital',
                    initialValue: nextHospitalValue,
                    onChanged: (value) => nextHospitalValue = value,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nextNoteCtrl,
                    enabled: !isSaving,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Next Appointment Note',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: isSaving
                          ? null
                          : () async {
                              final pcid = selectedPcid;
                              if (pcid == null || selectedType == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Patient and access type are required',
                                    ),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                                return;
                              }

                              setSheetState(() => isSaving = true);
                              final navigator = Navigator.of(sheetCtx);
                              final messenger = ScaffoldMessenger.of(context);

                              try {
                                final payload = <String, dynamic>{
                                  'pcid': pcid,
                                  'ac_type': selectedType,
                                  'ac_fullname':
                                      fullNameCtrl.text.trim().isEmpty
                                      ? null
                                      : fullNameCtrl.text.trim(),
                                  'ac_creationdate': accessCreationDate == null
                                      ? null
                                      : _formatDate(accessCreationDate!),
                                  'ac_createdhospital':
                                      createdHospitalValue.trim().isEmpty
                                      ? null
                                      : createdHospitalValue.trim(),
                                  'is_currentaccess': isCurrent,
                                  'infection_count': int.tryParse(
                                    infectionCountCtrl.text.trim(),
                                  ),
                                  'infection_note':
                                      infectionNoteCtrl.text.trim().isEmpty
                                      ? null
                                      : infectionNoteCtrl.text.trim(),
                                  'angioplast_count': int.tryParse(
                                    angioplastCountCtrl.text.trim(),
                                  ),
                                  'retplase_count': selectedType == 'PERM_CATH'
                                      ? int.tryParse(
                                          retplaseCountCtrl.text.trim(),
                                        )
                                      : null,
                                  'general_note':
                                      generalNoteCtrl.text.trim().isEmpty
                                      ? null
                                      : generalNoteCtrl.text.trim(),
                                  'lastplan_note':
                                      lastPlanCtrl.text.trim().isEmpty
                                      ? null
                                      : lastPlanCtrl.text.trim(),
                                  'otherhospitalneeded':
                                      otherHospitalCtrl.text.trim().isEmpty
                                      ? null
                                      : otherHospitalCtrl.text.trim(),
                                  'nextappointment_date':
                                      nextAppointmentDate == null
                                      ? null
                                      : _formatDate(nextAppointmentDate!),
                                  'nextappointment_hospital':
                                      nextHospitalValue.trim().isEmpty
                                      ? null
                                      : nextHospitalValue.trim(),
                                  'nextappointment_note':
                                      nextNoteCtrl.text.trim().isEmpty
                                      ? null
                                      : nextNoteCtrl.text.trim(),
                                };

                                final client = Supabase.instance.client;
                                if (isCurrent) {
                                  var q = client
                                      .from('vascularaccess')
                                      .update({'is_currentaccess': false})
                                      .eq('pcid', pcid);
                                  final currentVasid = _toInt(
                                    existing?['vasid'],
                                  );
                                  if (currentVasid != null) {
                                    q = q.neq('vasid', currentVasid);
                                  }
                                  await q;
                                }

                                if (isEdit) {
                                  final editVasid = _toInt(existing['vasid']);
                                  if (editVasid == null) {
                                    throw Exception(
                                      'Invalid record id for update',
                                    );
                                  }
                                  await client
                                      .from('vascularaccess')
                                      .update(payload)
                                      .eq('vasid', editVasid);
                                } else {
                                  await client
                                      .from('vascularaccess')
                                      .insert(payload);
                                }

                                await _syncPatientVaccess(pcid);
                                await _fetchData();
                                if (!mounted) return;
                                if (navigator.canPop()) navigator.pop();
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      isEdit
                                          ? 'Vascular record updated'
                                          : 'Vascular record created',
                                    ),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              } catch (e) {
                                if (!mounted) return;
                                setSheetState(() => isSaving = false);
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('Save failed: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
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
                        isSaving
                            ? 'Saving...'
                            : (isEdit ? 'Save Changes' : 'Create Record'),
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
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCards(List<Map<String, dynamic>> records) {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final sevenDays = todayOnly.add(const Duration(days: 7));

    final currentCount = records
        .where((r) => r['is_currentaccess'] == true)
        .length;
    final avfCount = records
        .where((r) => r['is_currentaccess'] == true && r['ac_type'] == 'AVF')
        .length;
    final avgCount = records
        .where((r) => r['is_currentaccess'] == true && r['ac_type'] == 'AVG')
        .length;
    final cathCount = records
        .where(
          (r) => r['is_currentaccess'] == true && r['ac_type'] == 'PERM_CATH',
        )
        .length;

    final dueAppointments = records.where((r) {
      final d = _parseDate(r['nextappointment_date']);
      if (d == null) return false;
      final dd = DateTime(d.year, d.month, d.day);
      return !dd.isBefore(todayOnly) && !dd.isAfter(sevenDays);
    }).length;

    Widget card(String title, String value, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [

        const SizedBox(height: 8),
        Row(
          children: [
            card('Current AVF', '$avfCount', Colors.green.shade700),
            const SizedBox(width: 8),
            card('Current AVG', '$avgCount', Colors.indigo.shade700),
            const SizedBox(width: 8),
            card('Current Cath', '$cathCount', Colors.red.shade700),
          ],
        ),
      ],
    );
  }

  Widget _buildTypeChip(String type, bool isCurrent) {
    final color = type == 'AVF'
        ? Colors.green.shade700
        : (type == 'AVG' ? Colors.indigo.shade700 : Colors.red.shade700);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isCurrent ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        _accessTypeLabel(type),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRecords;
    final patients = _patientById;

    final grouped = <int, List<Map<String, dynamic>>>{};
    for (final r in filtered) {
      final pcid = _toInt(r['pcid']);
      if (pcid == null) continue;
      grouped.putIfAbsent(pcid, () => []).add(r);
    }

    final patientIds = grouped.keys.toList()
      ..sort((a, b) {
        final an = (patients[a]?['name'] ?? '').toString().toLowerCase();
        final bn = (patients[b]?['name'] ?? '').toString().toLowerCase();
        return an.compareTo(bn);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vascular Management'),
        backgroundColor: const Color.fromARGB(255, 43, 138, 161),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _fetchData,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('New Record'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  color: Colors.teal.shade50,
                  padding: const EdgeInsets.all(12),
                  child: _buildSummaryCards(filtered),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            labelText: 'Search patient / ID / hospital',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            suffixIcon: _searchController.text.trim().isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () => _searchController.clear(),
                                    icon: const Icon(Icons.clear),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedType,
                          decoration: const InputDecoration(
                            labelText: 'Type',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('All'),
                            ),
                            ..._accessTypes.map(
                              (t) => DropdownMenuItem<String>(
                                value: t,
                                child: Text(_accessTypeLabel(t)),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() => _selectedType = value);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('Current Only'),
                        selected: _currentOnly,
                        onSelected: (v) => setState(() => _currentOnly = v),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            'No vascular records found',
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: patientIds.length,
                          itemBuilder: (context, index) {
                            final pcid = patientIds[index];
                            final rows =
                                grouped[pcid] ?? <Map<String, dynamic>>[];
                            final patientName =
                                (patients[pcid]?['name'] ?? 'Unknown')
                                    .toString();
                            final currentRows = rows
                                .where((r) => r['is_currentaccess'] == true)
                                .length;

                            final nextDates =
                                rows
                                    .map(
                                      (r) =>
                                          _parseDate(r['nextappointment_date']),
                                    )
                                    .whereType<DateTime>()
                                    .toList()
                                  ..sort();
                            final nearestNext = nextDates.isEmpty
                                ? null
                                : nextDates.first;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ExpansionTile(
                                title: Text(
                                  '$patientName ($pcid)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  '${rows.length} record(s) - Current: $currentRows${nearestNext == null ? '' : ' - Next: ${_displayDate(nearestNext)}'}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                children: rows.map((r) {
                                  final isCurrent =
                                      r['is_currentaccess'] == true;
                                  final type = (r['ac_type'] ?? '').toString();
                                  final acName = (r['ac_fullname'] ?? '')
                                      .toString()
                                      .trim();
                                  final acHospital =
                                      (r['ac_createdhospital'] ?? '')
                                          .toString()
                                          .trim();
                                  final createdDate = _parseDate(
                                    r['ac_creationdate'],
                                  );
                                  final nextDate = _parseDate(
                                    r['nextappointment_date'],
                                  );

                                  return Container(
                                    padding: const EdgeInsets.fromLTRB(
                                      14,
                                      8,
                                      14,
                                      10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isCurrent
                                          ? Colors.teal.withValues(alpha: 0.04)
                                          : null,
                                      border: Border(
                                        top: BorderSide(
                                          color: Colors.grey.shade200,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            _buildTypeChip(type, isCurrent),
                                            const SizedBox(width: 8),
                                            if (isCurrent)
                                              const Text(
                                                'CURRENT',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.green,
                                                ),
                                              ),
                                            const Spacer(),
                                            PopupMenuButton<String>(
                                              onSelected: (value) {
                                                if (value == 'edit') {
                                                  _openEditor(existing: r);
                                                } else if (value == 'current') {
                                                  _setAsCurrent(r);
                                                } else if (value == 'delete') {
                                                  _deleteRecord(r);
                                                }
                                              },
                                              itemBuilder: (_) => [
                                                const PopupMenuItem<String>(
                                                  value: 'edit',
                                                  child: Text('Edit'),
                                                ),
                                                if (!isCurrent)
                                                  const PopupMenuItem<String>(
                                                    value: 'current',
                                                    child: Text(
                                                      'Set as Current',
                                                    ),
                                                  ),
                                                const PopupMenuItem<String>(
                                                  value: 'delete',
                                                  child: Text('Delete'),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          acName.isEmpty
                                              ? 'Access Name: -'
                                              : 'Access Name: $acName',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Created: ${_displayDate(createdDate)}${acHospital.isEmpty ? '' : ' - $acHospital'}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Next appointment: ${_displayDate(nextDate)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: nextDate == null
                                                ? Colors.grey.shade700
                                                : Colors.orange.shade800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
