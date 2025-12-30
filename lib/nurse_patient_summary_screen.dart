import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NursePatientSummaryScreen extends StatefulWidget {
  const NursePatientSummaryScreen({super.key});

  @override
  State<NursePatientSummaryScreen> createState() =>
      _NursePatientSummaryScreenState();
}

class _NursePatientSummaryScreenState extends State<NursePatientSummaryScreen> {
  late Future<List<Map<String, dynamic>>> _summaryFuture;

  @override
  void initState() {
    super.initState();
    _summaryFuture = _fetchSummary();
  }

  Future<List<Map<String, dynamic>>> _fetchSummary() async {
    try {
      final response = await Supabase.instance.client
          .from('nurse_patient_summary')
          .select();

      // Sort logic if needed, but assuming database/view might return in order or we sort manually
      // We want TOTAL at the top if possible, rest by percentage or name
      final List<Map<String, dynamic>> data = List<Map<String, dynamic>>.from(
        response as List,
      );

      // Optional: Sort so TOTAL is first, then others by percentage descending
      data.sort((a, b) {
        if (a['nurse_name'] == 'TOTAL') return -1;
        if (b['nurse_name'] == 'TOTAL') return 1;
        // Compare by percentage descending
        final double? pctA = double.tryParse(a['bw_percentage'].toString());
        final double? pctB = double.tryParse(b['bw_percentage'].toString());
        if (pctA != null && pctB != null) {
          return pctB.compareTo(pctA);
        }
        return 0;
      });

      return data;
    } catch (e) {
      throw Exception('Error loading summary: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nurse Patient Summary'),
        backgroundColor: const Color.fromARGB(255, 43, 138, 161),
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _summaryFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: SelectableText(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No data found'));
          }

          final data = snapshot.data!;

          return SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: DataTable(
                  headingRowColor: MaterialStateProperty.all(
                    Colors.teal.shade50,
                  ),
                  dataRowColor: MaterialStateProperty.resolveWith<Color?>((
                    Set<MaterialState> states,
                  ) {
                    return null; // Default
                  }),
                  border: TableBorder.all(
                    color: Colors.grey.shade300,
                    width: 1,
                    borderRadius: BorderRadius.circular(8),
                    style: BorderStyle.none,
                  ),
                  columns: const [
                    DataColumn(
                      label: Text(
                        'Nurse',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'Total Patients',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      numeric: true,
                    ),
                    DataColumn(
                      label: Text(
                        'BW Entered',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      numeric: true,
                    ),
                    DataColumn(
                      label: Text(
                        'Percentage',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      numeric: true,
                    ),
                  ],
                  rows: data.asMap().entries.map((entry) {
                    final index = entry.key;
                    final row = entry.value;
                    final bool isTotal = row['nurse_name'] == 'TOTAL';

                    // Style for TOTAL row
                    final TextStyle textStyle = isTotal
                        ? const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.black,
                          )
                        : const TextStyle(fontSize: 14);

                    final Color? rowColor = isTotal
                        ? Colors.amber.shade100
                        : (index % 2 == 0 ? Colors.grey.shade50 : Colors.white);

                    return DataRow(
                      color: MaterialStateProperty.all(rowColor),
                      cells: [
                        DataCell(
                          Text(
                            row['nurse_name']?.toString() ?? '-',
                            style: textStyle,
                          ),
                        ),
                        DataCell(
                          Text(
                            row['total_patients']?.toString() ?? '0',
                            style: textStyle,
                          ),
                        ),
                        DataCell(
                          Text(
                            row['bw_entered_this_month']?.toString() ?? '0',
                            style: textStyle,
                          ),
                        ),
                        DataCell(
                          _buildPercentageCell(
                            row['bw_percentage'],
                            textStyle,
                            isTotal,
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPercentageCell(dynamic value, TextStyle style, bool isTotal) {
    if (value == null) return Text('-', style: style);

    final double? pct = double.tryParse(value.toString());
    if (pct == null) return Text(value.toString(), style: style);

    // Color coding for percentage
    Color textColor = style.color ?? Colors.black;
    if (!isTotal) {
      if (pct >= 80)
        textColor = Colors.green.shade700;
      else if (pct >= 50)
        textColor = Colors.orange.shade800;
      else
        textColor = Colors.red.shade700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: isTotal
          ? null
          : BoxDecoration(
              color: textColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
      child: Text(
        '${pct.toStringAsFixed(1)}%',
        style: style.copyWith(
          color: isTotal ? null : textColor,
          fontWeight: isTotal ? null : FontWeight.bold,
        ),
      ),
    );
  }
}
