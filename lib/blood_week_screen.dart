import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BloodWeekScreen extends StatefulWidget {
  final Map<String, dynamic> patient;
  final String? staffRole;

  const BloodWeekScreen({super.key, required this.patient, this.staffRole});

  @override
  State<BloodWeekScreen> createState() => _BloodWeekScreenState();
}

class _BloodWeekScreenState extends State<BloodWeekScreen> {
  final _formKey = GlobalKey<FormState>();

  // Selectors
  int _selectedYear = DateTime.now().year;
  String _selectedMonth = _getMonthName(DateTime.now().month);

  // Form Fields
  final Map<String, TextEditingController> _controllers = {};
  bool _needCollect = false;
  bool _isDrRevBw = false; // New field
  bool _isLoading = false;
  bool _hasUnsavedChanges = false;
  int? _existingRecordId;

  static const List<String> _months = [
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

  static const List<String> _fields = [
    'cbchb', //cbcplt', 'cbcwbc', // CBC
    'bca', 'bpo4', // Bone
    'ue1k', 'ue1gfr', 'ureapre', 'ureapost', // U&E
    'effurr', 'effktv', // Efficiency
    'ufdone', 'timetaken', 'wtpost', // Dialysis
    'staffenter', // Text
  ];

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
    for (var field in _fields) {
      final controller = TextEditingController();
      controller.addListener(_onFieldChanged);
      _controllers[field] = controller;
    }
    _fetchData();
  }

  void _onFieldChanged() {
    if (!_hasUnsavedChanges) {
      setState(() => _hasUnsavedChanges = true);
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  static String _getMonthName(int month) => _months[month - 1];

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client
          .from('bloodweek')
          .select()
          .eq('pcid', widget.patient['pcid'])
          .eq('year', _selectedYear)
          .eq('month', _selectedMonth)
          .maybeSingle();

      if (response != null) {
        _existingRecordId = response['id'];
        _needCollect = response['needcolect'] ?? false;
        _isDrRevBw = response['isdrrevbw'] ?? false; // Fetch new field
        for (var field in _fields) {
          _controllers[field]?.text = response[field]?.toString() ?? '';
        }
      } else {
        _clearForm();
      }
      if (mounted) setState(() => _hasUnsavedChanges = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _clearForm() {
    _existingRecordId = null;
    _needCollect = false;
    _isDrRevBw = false;
    for (var controller in _controllers.values) {
      controller.clear();
    }
  }

  Future<void> _saveData() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final data = {
        'pcid': widget.patient['pcid'],
        'year': _selectedYear,
        'month': _selectedMonth,
        'needcolect': _needCollect,
        'isdrrevbw': _isDrRevBw, // Save new field
        // Map controllers to double/string
        for (var field in _fields)
          field: field == 'staffenter'
              ? _controllers[field]!.text
              : double.tryParse(_controllers[field]!.text),
      };

      if (_existingRecordId != null) {
        await Supabase.instance.client
            .from('bloodweek')
            .update(data)
            .eq('id', _existingRecordId!);
      } else {
        await Supabase.instance.client.from('bloodweek').insert(data);
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Saved successfully!')));
        _fetchData(); // Refresh to get ID if inserted
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              // CHANGE SIZE HERE: Adjust icon size
              icon: const Icon(Icons.save, size: 20),
              // CHANGE SIZE HERE: Adjust font size
              label: const Text('Save', style: TextStyle(fontSize: 16)),
              style: FilledButton.styleFrom(
                // CHANGE SIZE HERE: Adjust padding to make button larger/smaller
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 0,
                ),
                backgroundColor: _hasUnsavedChanges
                    ? Colors.red
                    : Colors.teal.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: _isLoading ? null : _saveData,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Selectors
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.teal.shade50,
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _selectedYear,
                    decoration: const InputDecoration(labelText: 'Year'),
                    items: List.generate(10, (index) => 2024 + index)
                        .map(
                          (y) => DropdownMenuItem(value: y, child: Text('$y')),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedYear = val);
                        _fetchData();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedMonth,
                    decoration: const InputDecoration(labelText: 'Month'),
                    items: _months
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedMonth = val);
                        _fetchData();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),

          if (_isLoading)
            const LinearProgressIndicator()
          else
            Expanded(
              child: SingleChildScrollView(
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
                            value: _isDrRevBw,
                            thumbColor: WidgetStateProperty.resolveWith((
                              states,
                            ) {
                              if (states.contains(WidgetState.selected)) {
                                return Colors.green;
                              }
                              return null;
                            }),
                            onChanged: (val) => setState(() {
                              _isDrRevBw = val;
                              _hasUnsavedChanges = true;
                            }),
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
              ),
            ),
        ],
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
                  width: 150, // Fixed width for cleaner grid layout
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
      controller: _controllers[key],
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
