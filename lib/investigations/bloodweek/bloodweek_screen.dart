import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'bloodweek_controller.dart';
import '../medications_screen.dart';

class BloodWeekScreen extends StatefulWidget {
  final Map<String, dynamic> patient;
  final String? staffRole;
  final int? medicalStaffId;

  /// Optional: list of patients for navigation (from filtered list)
  final List<Map<String, dynamic>>? patientList;

  /// Optional: current index in the patient list
  final int? currentIndex;

  const BloodWeekScreen({
    super.key,
    required this.patient,
    this.staffRole,
    this.medicalStaffId,
    this.patientList,
    this.currentIndex,
  });

  @override
  State<BloodWeekScreen> createState() => _BloodWeekScreenState();
}

class _BloodWeekScreenState extends State<BloodWeekScreen> {
  final _formKey = GlobalKey<FormState>();
  late BloodWeekController controller;

  // Current patient (can change via navigation)
  late Map<String, dynamic> _currentPatient;
  late int _currentIndex;

  static const List<String> _fields = [
    'cbchb',
    'bca',
    'bpo4',
    'ue1k',
    'ue1gfr',
    'ureapre',
    'ureapost',
    'effurr',
    'effktv',
    'ufdone',
    'timetaken',
    'wtpost',
    'staffenter',
  ];

  // Custom labels for user-friendly display
  static const Map<String, String> _customLabels = {
    'cbchb': 'HB',
    'bca': 'Ca',
    'bpo4': 'PO4',
    'ue1k': 'K',
    'ue1gfr': 'GFR',
    'ureapre': 'Pre',
    'ureapost': 'Post',
    'effurr': 'URR',
    'effktv': 'Kt/V',
    'ufdone': 'UF Done',
    'timetaken': 'Time Taken',
    'wtpost': 'WT Post',
    'staffenter': 'Staff Enter',
  };

  bool get _hasNavigation =>
      widget.patientList != null && widget.patientList!.length > 1;
  bool get _canGoPrevious => _hasNavigation && _currentIndex > 0;
  bool get _canGoNext =>
      _hasNavigation && _currentIndex < widget.patientList!.length - 1;

  @override
  void initState() {
    super.initState();
    _currentPatient = widget.patient;
    _currentIndex = widget.currentIndex ?? 0;
    controller = BloodWeekController(
      _fields,
      medicalStaffId: widget.medicalStaffId,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.fetchData(_currentPatient['pcid']);
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  /// Navigate to another patient in the list
  void _navigateToPatient(int newIndex) {
    if (controller.hasUnsavedChanges) {
      _showUnsavedChangesDialog(() {
        _doNavigate(newIndex);
      });
    } else {
      _doNavigate(newIndex);
    }
  }

  void _doNavigate(int newIndex) {
    setState(() {
      _currentIndex = newIndex;
      _currentPatient = widget.patientList![newIndex];
    });
    controller.fetchData(_currentPatient['pcid']);
  }

  void _showUnsavedChangesDialog(VoidCallback onDiscard) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text(
          'You have unsaved changes. Do you want to discard them?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDiscard();
            },
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: controller,
      child: Consumer<BloodWeekController>(
        builder: (_, c, __) {
          return PopScope(
            canPop: !controller.hasUnsavedChanges,
            onPopInvokedWithResult: (didPop, result) async {
              if (didPop) return;

              final shouldPop = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Unsaved changes'),
                  content: const Text(
                    'You have unsaved changes. Do you want to discard them?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Discard'),
                    ),
                  ],
                ),
              );

              if (shouldPop == true && context.mounted) {
                Navigator.of(context).pop(_currentIndex);
              }
            },
            child: Scaffold(
              appBar: AppBar(
                leading: _hasNavigation
                    ? IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () {
                          if (controller.hasUnsavedChanges) {
                            _showUnsavedChangesDialog(() {
                              Navigator.of(context).pop(_currentIndex);
                            });
                          } else {
                            Navigator.of(context).pop(_currentIndex);
                          }
                        },
                      )
                    : null,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentPatient['name'] ?? 'Unknown',
                      style: const TextStyle(fontSize: 16),
                    ),
                    Row(
                      children: [
                        Text(
                          'ID: ${_currentPatient['pcid']}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        if (_hasNavigation) ...[
                          const SizedBox(width: 8),
                          Text(
                            '(${_currentIndex + 1}/${widget.patientList!.length})',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color.fromARGB(179, 97, 118, 240),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                actions: [
                  // Navigation buttons (only if patientList is provided)
                  if (_hasNavigation) ...[
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios),
                      onPressed: _canGoPrevious
                          ? () => _navigateToPatient(_currentIndex - 1)
                          : null,
                      tooltip: 'Previous Patient',
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_ios),
                      onPressed: _canGoNext
                          ? () => _navigateToPatient(_currentIndex + 1)
                          : null,
                      tooltip: 'Next Patient',
                    ),
                  ],
                  // Save button
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: FilledButton.icon(
                      icon: const Icon(Icons.save, size: 20),
                      label: const Text('Save', style: TextStyle(fontSize: 16)),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 0,
                        ),
                        backgroundColor: c.hasUnsavedChanges
                            ? Colors.red
                            : const Color.fromARGB(255, 6, 107, 95),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: c.isLoading
                          ? null
                          : () async {
                              if (_formKey.currentState!.validate()) {
                                final error = await c.saveData(
                                  _currentPatient['pcid'],
                                );
                                if (!context.mounted) return;

                                if (error != null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(error),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Saved successfully!'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              }
                            },
                    ),
                  ),
                ],
              ),
              body: Column(
                children: [
                  _buildSelectors(c),
                  if (c.isLoading) const LinearProgressIndicator(),
                  if (c.isOfflineData || c.errorMessage != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      color: c.isOfflineData
                          ? Colors.orange.shade100
                          : Colors.red.shade100,
                      child: Row(
                        children: [
                          Icon(
                            c.isOfflineData
                                ? Icons.cloud_off
                                : Icons.error_outline,
                            color: c.isOfflineData
                                ? Colors.orange.shade800
                                : Colors.red.shade800,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              c.errorMessage ?? 'Offline mode',
                              style: TextStyle(
                                color: c.isOfflineData
                                    ? Colors.orange.shade900
                                    : Colors.red.shade900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (c.isOfflineData)
                            TextButton(
                              onPressed: () =>
                                  c.fetchData(_currentPatient['pcid']),
                              child: const Text('Retry'),
                            ),
                        ],
                      ),
                    ),
                  Expanded(child: _buildForm(c)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSelectors(BloodWeekController c) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.teal.shade50,
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              value: c.selectedYear,
              decoration: const InputDecoration(labelText: 'Year'),
              items: List.generate(10, (i) => 2024 + i)
                  .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                  .toList(),
              onChanged: (v) =>
                  v != null ? c.changeYear(v, widget.patient['pcid']) : null,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: c.selectedMonth,
              decoration: const InputDecoration(labelText: 'Month'),
              items: BloodWeekController.months
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) =>
                  v != null ? c.changeMonth(v, widget.patient['pcid']) : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(BloodWeekController c) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.staffRole == 'Dr')
              _buildSection('Doctor Review', [
                ListTile(
                  leading: const Icon(
                    Icons.medication_outlined,
                    color: Colors.orange,
                  ),
                  title: const Text('Medications'),
                  subtitle: const Text('View/Edit patient medications'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            MedicationsScreen(patient: _currentPatient),
                      ),
                    );
                  },
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Reviewed by Dr'),
                  value: c.isDrRevBw,
                  thumbColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.green;
                    }
                    return null;
                  }),
                  onChanged: (val) => c.setDrReview(val),
                ),
              ]),
            _buildSection('CBC', ['cbchb']),
            _buildSection('Bone Profile', ['bca', 'bpo4']),
            _buildSection('Renal & Urea', [
              'ue1k',
              'ue1gfr',
              'ureapre',
              'ureapost',
            ]),
            _buildSection('Dialysis Efficiency', [
              'ufdone',
              'timetaken',
              'wtpost',
              'effurr',
              'effktv',
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<dynamic> fields) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
            const Divider(),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: fields.map((f) {
                if (f is Widget) return f;
                return SizedBox(
                  width: 175,
                  child: _buildTextField(
                    _customLabels[f] ?? f.toUpperCase(),
                    f,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, String key) {
    // Auto-calculated fields (read-only)
    final isReadOnly = key == 'effurr' || key == 'effktv';

    String? prevText;
    if (controller.previousMonthData != null &&
        controller.previousMonthData!.values[key] != null &&
        controller.previousMonthData!.values[key].toString().isNotEmpty &&
        key != 'staffenter') {
      prevText =
          '${controller.previousMonthStr?.substring(0, 3)}: ${controller.previousMonthData!.values[key]}';
    }

    // Define validation ranges for medical values
    String? validator(String? value) {
      if (value == null || value.isEmpty) return null;
      if (key == 'staffenter') return null; // Skip validation for text field
      if (isReadOnly) return null; // Skip validation for read-only fields

      final num = double.tryParse(value);
      if (num == null) return 'Enter valid number';

      // Medical value ranges
      final ranges = {
        'cbchb': (0.0, 20.0), // HB: 0-20 g/dL
        'bca': (0.0, 20.0), // Calcium: 0-20 mg/dL
        'bpo4': (0.0, 15.0), // Phosphorus: 0-15 mg/dL
        'ue1k': (0.0, 10.0), // Potassium: 0-10 mEq/L
        'ue1gfr': (0.0, 150.0), // GFR: 0-150 mL/min
        'ureapre': (0.0, 300.0), // Urea Pre: 0-300 mg/dL
        'ureapost': (0.0, 300.0), // Urea Post: 0-300 mg/dL
        'effurr': (0.0, 100.0), // URR: 0-100%
        'effktv': (0.0, 3.0), // Kt/V: 0-3
        'ufdone': (0.0, 10.0), // UF Done: 0-10 L
        'timetaken': (0.0, 600.0), // Time: 0-600 min
        'wtpost': (0.0, 200.0), // Weight: 0-200 kg
      };

      if (ranges.containsKey(key)) {
        final (min, max) = ranges[key]!;
        if (num < min || num > max) {
          return '$min-$max range';
        }
      }
      return null;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextFormField(
            controller: controller.controllers[key],
            readOnly: isReadOnly,
            decoration: InputDecoration(
              labelText: isReadOnly ? '$label (Auto)' : label,
              border: const OutlineInputBorder(),
              isDense: true,
              filled: isReadOnly,
              fillColor: isReadOnly ? Colors.yellow.shade100 : null,
            ),
            keyboardType: key == 'staffenter'
                ? TextInputType.text
                : const TextInputType.numberWithOptions(decimal: true),
            validator: validator,
          ),
        ),
        if (prevText != null) ...[
          const SizedBox(width: 8),
          Text(
            prevText,
            style: TextStyle(
              fontSize: 12,
              color: Colors.blueGrey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}
