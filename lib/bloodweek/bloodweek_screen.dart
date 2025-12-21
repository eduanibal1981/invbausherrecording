import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'bloodweek_controller.dart';

class BloodWeekScreen extends StatefulWidget {
  final Map<String, dynamic> patient;
  final String? staffRole;

  const BloodWeekScreen({super.key, required this.patient, this.staffRole});

  @override
  State<BloodWeekScreen> createState() => _BloodWeekScreenState();
}

class _BloodWeekScreenState extends State<BloodWeekScreen> {
  final _formKey = GlobalKey<FormState>();
  late BloodWeekController controller;

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

  @override
  void initState() {
    super.initState();
    controller = BloodWeekController(_fields);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.fetchData(widget.patient['pcid']);
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
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
                Navigator.of(context).pop();
              }
            },
            child: Scaffold(
              appBar: AppBar(
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.patient['name'] ?? 'Unknown'),
                    Text(
                      'ID: ${widget.patient['pcid']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                actions: [
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
                            : Colors.teal.shade700,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: c.isLoading
                          ? null
                          : () async {
                              if (_formKey.currentState!.validate()) {
                                final error = await c.saveData(
                                  widget.patient['pcid'],
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
              'effurr',
              'effktv',
              'ufdone',
              'timetaken',
              'wtpost',
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
                  width: 150,
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
    return TextFormField(
      controller: controller.controllers[key],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      keyboardType: key == 'staffenter'
          ? TextInputType.text
          : const TextInputType.numberWithOptions(decimal: true),
    );
  }
}
