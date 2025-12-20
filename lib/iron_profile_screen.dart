import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class IronProfileScreen extends StatefulWidget {
  final Map<String, dynamic> patient;

  final String? staffRole;

  const IronProfileScreen({super.key, required this.patient, this.staffRole});

  @override
  State<IronProfileScreen> createState() => _IronProfileScreenState();
}

class _IronProfileScreenState extends State<IronProfileScreen> {
  int _selectedYear = DateTime.now().year;
  bool _isLoading = false;
  List<Map<String, dynamic>> _records = [];

  @override
  void initState() {
    super.initState();
    _fetchRecords();
  }

  Future<void> _fetchRecords() async {
    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client
          .from('ironprofile')
          .select()
          .eq('pcid', widget.patient['pcid'])
          .eq('ironyear', _selectedYear)
          .order('invdate', ascending: false);

      setState(() {
        _records = List<Map<String, dynamic>>.from(response);
        if (_records.isNotEmpty) {
          print('IronProfile Keys: ${_records.first.keys.toList()}');
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showEditDialog({Map<String, dynamic>? record}) async {
    final isEditing = record != null;
    final dateController = TextEditingController(
      text: record?['invdate'] ?? DateTime.now().toString().split(' ')[0],
    );
    final tsatController = TextEditingController(
      text: record?['irontsat']?.toString() ?? '',
    );
    final ferritinController = TextEditingController(
      text: record?['ironferritin']?.toString() ?? '',
    );
    final medicalController = TextEditingController(
      text: record?['tttmedical']?.toString() ?? '',
    );
    final noteController = TextEditingController(
      text: record?['ironnote']?.toString() ?? '',
    );

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? 'Edit Iron Profile' : 'New Iron Profile'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: dateController,
                decoration: const InputDecoration(
                  labelText: 'Date (YYYY-MM-DD)',
                  icon: Icon(Icons.calendar_today),
                ),
                readOnly: true,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                    initialDate:
                        DateTime.tryParse(dateController.text) ??
                        DateTime.now(),
                  );
                  if (picked != null) {
                    dateController.text = picked.toIso8601String().split(
                      'T',
                    )[0];
                  }
                },
              ),
              TextField(
                controller: tsatController,
                decoration: const InputDecoration(labelText: 'Iron Tsat'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              TextField(
                controller: ferritinController,
                decoration: const InputDecoration(labelText: 'Iron Ferritin'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              TextField(
                controller: medicalController,
                decoration: const InputDecoration(labelText: 'Medical TTT'),
                maxLines: 2,
              ),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'Note'),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              _saveRecord(
                date: dateController.text,
                tsat: tsatController.text,
                ferritin: ferritinController.text,
                medical: medicalController.text,
                note: noteController.text,
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveRecord({
    required String date,
    required String tsat,
    required String ferritin,
    required String medical,
    required String note,
  }) async {
    setState(() => _isLoading = true);
    try {
      final dt = DateTime.parse(date);
      final data = {
        'pcid': widget.patient['pcid'],
        'invdate': date,
        'ironyear': dt.year,
        'irontsat': double.tryParse(tsat),
        'ironferritin': double.tryParse(ferritin),
        'tttmedical': medical,
        'ironnote': note,
      };

      await Supabase.instance.client.from('ironprofile').upsert(data);
      _fetchRecords();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    print('IronProfile StaffRole: ${widget.staffRole}');
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
            const Text(
              '           Iron Profile Investigations',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditDialog(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<int>(
              value: _selectedYear,
              decoration: const InputDecoration(
                labelText: 'Filter by Year',
                border: OutlineInputBorder(),
              ),
              items:
                  List.generate(10, (index) => DateTime.now().year - 5 + index)
                      .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                      .toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedYear = val);
                  _fetchRecords();
                }
              },
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _records.isEmpty
                ? const Center(child: Text('No records found for this year.'))
                : ListView.builder(
                    itemCount: _records.length,
                    itemBuilder: (context, index) {
                      final rec = _records[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: ListTile(
                          title: Text('Date: ${rec['invdate']}'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (rec['irontsat'] != null)
                                Text('Tsat: ${rec['irontsat']}'),
                              if (rec['ironferritin'] != null)
                                Text('Ferritin: ${rec['ironferritin']}'),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.staffRole == 'Dr')
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text(
                                      'Review',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    SizedBox(
                                      height: 30,
                                      child: Switch(
                                        value: rec['isdrreviron'] ?? false,
                                        activeColor: Colors.green,
                                        onChanged: (val) =>
                                            _updateStatus(rec, val, index),
                                      ),
                                    ),
                                  ],
                                ),
                              if (widget.staffRole == 'Dr')
                                const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => _showEditDialog(record: rec),
                              ),
                            ],
                          ),
                          onTap: () => _showEditDialog(record: rec),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateStatus(
    Map<String, dynamic> record,
    bool value,
    int index,
  ) async {
    // Optimistic update
    setState(() {
      _records[index]['isdrreviron'] = value;
    });

    try {
      await Supabase.instance.client
          .from('ironprofile')
          .update({'isdrreviron': value})
          .eq('pcid', record['pcid'])
          .eq('invdate', record['invdate']);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating status: $e')));
        // Revert on error
        setState(() {
          _records[index]['isdrreviron'] = !value;
        });
      }
    }
  }
}
