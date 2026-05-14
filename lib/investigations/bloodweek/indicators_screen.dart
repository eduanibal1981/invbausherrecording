import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'bloodweek_controller.dart'; // To get months list

class IndicatorsScreen extends StatefulWidget {
  const IndicatorsScreen({super.key});

  @override
  State<IndicatorsScreen> createState() => _IndicatorsScreenState();
}

class _IndicatorsScreenState extends State<IndicatorsScreen> {
  int _selectedYear = DateTime.now().year;
  String _selectedMonth = BloodWeekController.months[DateTime.now().month - 1];
  String _selectedVAccess = 'All';

  bool _isLoading = false;
  List<Map<String, dynamic>> _indicators = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchIndicators();
  }

  Future<void> _fetchIndicators() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Fetch active patients with the selected vaccess
      final patientsResponse = await Supabase.instance.client
          .from('patients')
          .select('pcid, vaccess')
          .eq('status', 'Active');
          
      final activePcids = (patientsResponse as List)
          .where((p) => _selectedVAccess == 'All' || p['vaccess'] == _selectedVAccess)
          .map((p) => p['pcid'] as int)
          .toSet();
          
      final totalActive = activePcids.length;

      // Define the single source of truth RPCs
      final rpcs = [
        {'name': 'get_patients_with_abnormal_ca', 'title': 'Abnormal Ca (< 2.1 or > 2.6)'},
        {'name': 'get_patients_with_rising_po4', 'title': 'Po4 > 1.8 and rose'},
        {'name': 'get_patients_with_dropping_ktv', 'title': 'Kt/V < 1.2 and dropped'},
        {'name': 'get_patients_with_dropping_urr', 'title': 'URR < 65 and dropped'},
        {'name': 'get_patients_with_dropping_hb', 'title': 'Hb < 10 and dropped'},
      ];

      final List<Map<String, dynamic>> newIndicators = [];

      for (final rpc in rpcs) {
        final response = await Supabase.instance.client.rpc(
          rpc['name']!,
          params: {
            'target_year': _selectedYear,
            'target_month': _selectedMonth,
          },
        );
        
        // Some RPCs might return null if empty, so handle safely
        final listResponse = (response as List?) ?? [];
        final pcids = listResponse.map((e) {
          if (e is Map) return int.parse(e.values.first.toString());
          return int.parse(e.toString());
        }).toSet();
        final metCount = pcids.intersection(activePcids).length;
        
        final percentage = totalActive > 0 ? (metCount / totalActive) * 100 : 0.0;
        
        newIndicators.add({
          'indicator_name': rpc['title'],
          'total_tested': totalActive,
          'target_met': metCount,
          'percentage': double.parse(percentage.toStringAsFixed(2)),
        });
      }

      final pthResponse = await Supabase.instance.client.rpc('get_pth_summary');

      setState(() {
        _indicators = newIndicators;

        if (pthResponse != null && (pthResponse as List).isNotEmpty) {
          final data = pthResponse[0];
          _indicators.insert(0, {
            'indicator_name': 'Parathyroid (> 81)',
            'total_tested': data['total_active'],
            'target_met': data['high_pth_count'],
            'percentage': data['percentage'],
            'is_pth': true,
          });
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinical Indicators'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            tooltip: 'Return to Home',
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ],
        backgroundColor: const Color.fromARGB(255, 43, 138, 161),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.teal.shade50,
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _selectedYear,
                    decoration: const InputDecoration(
                      labelText: 'Year',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    items: List.generate(10, (i) => 2024 + i)
                        .map(
                          (y) => DropdownMenuItem(value: y, child: Text('$y')),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _selectedYear = v);
                        _fetchIndicators();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedMonth,
                    decoration: const InputDecoration(
                      labelText: 'Month',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    items: BloodWeekController.months
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _selectedMonth = v);
                        _fetchIndicators();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.teal.shade50,
            child: DropdownButtonFormField<String>(
              initialValue: _selectedVAccess,
              decoration: const InputDecoration(
                labelText: 'Vascular Access',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              items: [
                'All',
                'AVF',
                'AVG',
                'Perm. Cath',
              ].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() => _selectedVAccess = v);
                  _fetchIndicators();
                }
              },
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Error: $_errorMessage',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          Expanded(
            child: _indicators.isEmpty && !_isLoading
                ? const Center(child: Text('No data found for this period.'))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _indicators.length,
                    itemBuilder: (context, index) {
                      final item = _indicators[index];
                      final name = item['indicator_name'];
                      final total = item['total_tested'];
                      final met = item['target_met'];
                      final percentage = (item['percentage'] as num).toDouble();

                      final isPth = item['is_pth'] == true;

                      Color progressColor;
                      // All indicators now represent abnormalities (worse/dropping), so lower percentage is better
                      if (percentage >= 50) {
                        progressColor = Colors.red;
                      } else if (percentage >= 25) {
                        progressColor = Colors.orange;
                      } else {
                        progressColor = Colors.green;
                      }

                      return Card(
                        elevation: 3,
                        margin: const EdgeInsets.only(bottom: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.teal,
                                    ),
                                  ),
                                  Text(
                                    '$percentage%',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: progressColor,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: total > 0 ? (percentage / 100) : 0,
                                  minHeight: 10,
                                  backgroundColor: Colors.grey.shade200,
                                  color: progressColor,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Affected patients: $met',
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  Text(
                                    isPth
                                        ? 'Total active: $total'
                                        : 'Total active: $total',
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
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
