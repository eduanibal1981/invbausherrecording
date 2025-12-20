import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class ParathyroidScreen extends StatefulWidget {
  final Map<String, dynamic> patient;
  final String? staffRole;

  const ParathyroidScreen({super.key, required this.patient, this.staffRole});

  @override
  State<ParathyroidScreen> createState() => _ParathyroidScreenState();
}

class _ParathyroidScreenState extends State<ParathyroidScreen> {
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
          .from('parathyroid')
          .select()
          .eq('pcid', widget.patient['pcid'])
          .eq('pthyear', _selectedYear)
          .order('pthdate', ascending: false);

      setState(() {
        _records = List<Map<String, dynamic>>.from(response);
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
      text: record?['pthdate'] != null
          ? DateTime.parse(record!['pthdate']).toString().split(' ')[0]
          : DateTime.now().toString().split(' ')[0],
    );
    final resultController = TextEditingController(
      text: record?['pthresult']?.toString() ?? '',
    );
    final noteController = TextEditingController(
      text: record?['treatmentnote']?.toString() ?? '',
    );
    final scanController = TextEditingController(
      text: record?['pthscan']?.toString() ?? '',
    );

    // We store the original date to identify the record for updates if needed, though composite PK updates can be tricky.
    // For simplicity, we will assume Insert/Update semantics based on the primary key (date, pcid).
    // If the user changes the Date, it technically acts as a new record (INSERT) unless we handle deletion of old.
    // Given the request, simple Upsert on the NEW date is safest.

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? 'Edit Parathyroid' : 'New Parathyroid'),
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
                controller: resultController,
                decoration: const InputDecoration(labelText: 'PTH Result'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'Treatment Note'),
                maxLines: 2,
              ),
              TextField(
                controller: scanController,
                decoration: const InputDecoration(labelText: 'PTH Scan'),
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
                result: resultController.text,
                note: noteController.text,
                scan: scanController.text,
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
    required String result,
    required String note,
    required String scan,
  }) async {
    setState(() => _isLoading = true);
    try {
      final dt = DateTime.parse(date);
      final data = {
        'pcid': widget.patient['pcid'],
        'pthdate':
            date, // Timezone issues might apply, using date string usually auto-converts to timestamp
        'pthyear': dt.year,
        'pthresult': double.tryParse(result),
        'treatmentnote': note,
        'pthscan': scan,
      };

      await Supabase.instance.client.from('parathyroid').upsert(data);
      _fetchRecords(); // Refresh list
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
              '           Parathyroid Investigations',
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
                          title: Text(
                            'Date: ${DateFormat('yyyy-MM-dd').format(DateTime.parse(rec['pthdate']))}',
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (rec['pthresult'] != null)
                                Text('Result: ${rec['pthresult']}'),
                              if (rec['treatmentnote'] != null)
                                Text('Note: ${rec['treatmentnote']}'),
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
                                        value: rec['isdrrevpth'] ?? false,
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
      _records[index]['isdrrevpth'] = value;
    });

    try {
      await Supabase.instance.client
          .from('parathyroid')
          .update({'isdrrevpth': value})
          .eq('pcid', record['pcid'])
          .eq('pthdate', record['pthdate']);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating status: $e')));
        // Revert on error
        setState(() {
          _records[index]['isdrrevpth'] = !value;
        });
      }
    }
  }
}
