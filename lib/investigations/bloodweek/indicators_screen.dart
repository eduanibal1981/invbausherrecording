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
  bool _useActivePatientsTotal = true;
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
      final rpcName = _useActivePatientsTotal
          ? 'get_bloodweek_indicators_active'
          : 'get_bloodweek_indicators';

      final response = await Supabase.instance.client.rpc(
        rpcName,
        params: {
          'p_year': _selectedYear,
          'p_month': _selectedMonth,
          'p_vaccess': _selectedVAccess,
        },
      );

      setState(() {
        _indicators = List<Map<String, dynamic>>.from(response);
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
          Container(
            color: Colors.teal.shade50,
            child: SwitchListTile(
              title: const Text(
                'Calculate percentage from total ACTIVE patients',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: Text(
                _useActivePatientsTotal
                    ? 'Current: Target Met / All Active Patients'
                    : 'Current: Target Met / Patients Tested',
                style: const TextStyle(fontSize: 12),
              ),
              value: _useActivePatientsTotal,
              activeThumbColor: Colors.teal,
              onChanged: (val) {
                setState(() => _useActivePatientsTotal = val);
                _fetchIndicators();
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

                      Color progressColor;
                      if (percentage >= 80) {
                        progressColor = Colors.green;
                      } else if (percentage >= 50) {
                        progressColor = Colors.orange;
                      } else {
                        progressColor = Colors.red;
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
                                    'Patients meeting target: $met',
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  Text(
                                    (_useActivePatientsTotal &&
                                            name != 'Kt/V >= 1.2' &&
                                            name != 'URR >= 65%')
                                        ? 'Total active: $total'
                                        : 'Total tested: $total',
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
