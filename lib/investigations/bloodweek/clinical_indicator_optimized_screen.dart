import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'bloodweek_controller.dart';
import 'indicators_screen.dart';

class ClinicalIndicatorOptimizedScreen extends StatefulWidget {
  const ClinicalIndicatorOptimizedScreen({super.key});

  @override
  State<ClinicalIndicatorOptimizedScreen> createState() =>
      _ClinicalIndicatorOptimizedScreenState();
}

class _IndicatorModel {
  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color themeColor;
  final String rpcName;
  final bool isAdequacy;
  final String? adequacyKey; // 'urr', 'ktv', 'ocm_ktv'

  bool hasResultThisMonth = true;
  int testedCount = 0;
  int metCount = 0;
  int totalActive = 0;
  double percentage = 0.0;
  Set<int> affectedPcids = {};

  // For adequacy indicators with no results in selected month
  String? lastResultMonth;
  int? lastResultYear;
  double? lastResultPercentage;
  int? lastResultMetCount;
  int? lastResultTestedCount;
  bool isNeverRecorded = false;

  _IndicatorModel({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.themeColor,
    required this.rpcName,
    this.isAdequacy = false,
    this.adequacyKey,
  });
}

class _ClinicalIndicatorOptimizedScreenState
    extends State<ClinicalIndicatorOptimizedScreen> {
  int _selectedYear = DateTime.now().year;
  String _selectedMonth = BloodWeekController.months[DateTime.now().month - 1];
  String _selectedVAccess = 'All';

  bool _isLoading = false;
  String? _errorMessage;
  List<_IndicatorModel> _indicators = [];
  Map<int, Map<String, dynamic>> _activePatientsMap = {};

  @override
  void initState() {
    super.initState();
    _initIndicators();
    _fetchData();
  }

  void _initIndicators() {
    _indicators = [
      _IndicatorModel(
        key: 'hb_dropping',
        title: 'HB < 10 & Dropped',
        subtitle: 'Hemoglobin below 10 g/dL and dropping',
        icon: Icons.water_drop,
        themeColor: Colors.red.shade700,
        rpcName: 'get_patients_with_dropping_hb',
      ),
      _IndicatorModel(
        key: 'ca_high',
        title: 'Ca > 2.6',
        subtitle: 'High serum calcium (≥ 2.6 mmol/L)',
        icon: Icons.arrow_upward,
        themeColor: Colors.deepOrange.shade600,
        rpcName: 'get_patients_with_high_ca',
      ),
      _IndicatorModel(
        key: 'ca_low',
        title: 'Ca < 2.1',
        subtitle: 'Low serum calcium (< 2.1 mmol/L)',
        icon: Icons.arrow_downward,
        themeColor: Colors.amber.shade800,
        rpcName: 'get_patients_with_low_ca',
      ),
      _IndicatorModel(
        key: 'po4_rising',
        title: 'Po4 > 1.8 and Rose',
        subtitle: 'Elevated phosphate (> 1.8 mmol/L) & rising',
        icon: Icons.trending_up,
        themeColor: Colors.purple.shade600,
        rpcName: 'get_patients_with_rising_po4',
      ),
      _IndicatorModel(
        key: 'urr_dropping',
        title: 'URR < 65 & Dropped',
        subtitle: 'Inadequate urea reduction ratio (≤ 65%) & dropped',
        icon: Icons.percent,
        themeColor: Colors.teal.shade700,
        rpcName: 'get_patients_with_dropping_urr',
        isAdequacy: true,
        adequacyKey: 'urr',
      ),
      _IndicatorModel(
        key: 'ktv_dropping',
        title: 'KT/V < 1.2 and Dropped',
        subtitle: 'Lab dialysis dose (≤ 1.2) & dropped',
        icon: Icons.science,
        themeColor: Colors.indigo.shade600,
        rpcName: 'get_patients_with_dropping_ktv',
        isAdequacy: true,
        adequacyKey: 'ktv',
      ),
      _IndicatorModel(
        key: 'pth_rising',
        title: 'PTH > 59 and Rose',
        subtitle: 'Intact parathyroid hormone (> 59 pmol/L) & rose',
        icon: Icons.health_and_safety,
        themeColor: Colors.brown.shade600,
        rpcName: 'get_patients_with_rising_pth',
      ),
      _IndicatorModel(
        key: 'ocm_ktv_dropping',
        title: 'OCM KT/V < 1.2 and Dropped',
        subtitle: 'Machine online clearance dose (≤ 1.2) & dropped',
        icon: Icons.monitor_heart,
        themeColor: Colors.blueGrey.shade700,
        rpcName: 'get_patients_with_dropping_ocm_ktv',
        isAdequacy: true,
        adequacyKey: 'ocm_ktv',
      ),
    ];
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final client = Supabase.instance.client;

      // 1. Fetch active patients
      final patientsResponse = await client
          .from('patients')
          .select('pcid, name, vaccess, hall_main, day_main, shift_main, status')
          .eq('status', 'Active');

      final allPatients = (patientsResponse as List)
          .cast<Map<String, dynamic>>();

      final filteredPatients = allPatients.where((p) {
        if (_selectedVAccess == 'All') return true;
        return p['vaccess'] == _selectedVAccess;
      }).toList();

      final activePcids = filteredPatients.map((p) => p['pcid'] as int).toSet();
      final totalActive = activePcids.length;

      _activePatientsMap = {
        for (final p in filteredPatients) p['pcid'] as int: p,
      };

      // 2. Query Bloodweek rows for current month to calculate test counts
      final bwResponse = await client
          .from('bloodweek')
          .select('pcid, cbchb, bca, bpo4, effurr, effktv, machine_ktv')
          .eq('month', _selectedMonth)
          .eq('year', _selectedYear);

      final bwList = (bwResponse as List).cast<Map<String, dynamic>>();
      final bwActiveList = bwList.where((r) => activePcids.contains(r['pcid'])).toList();

      final hbTestedCount = bwActiveList.where((r) => r['cbchb'] != null).length;
      final caTestedCount = bwActiveList.where((r) => r['bca'] != null).length;
      final po4TestedCount = bwActiveList.where((r) => r['bpo4'] != null).length;

      // 3. Process each indicator concurrently
      final futures = _indicators.map((ind) async {
        ind.totalActive = totalActive;

        if (ind.isAdequacy && ind.adequacyKey != null) {
          // Check testing status for adequacy indicators
          final statusRes = await client.rpc(
            'get_indicator_testing_status',
            params: {
              'p_indicator': ind.adequacyKey,
              'p_month': _selectedMonth,
              'p_year': _selectedYear,
            },
          );

          final statusMap = (statusRes is Map) ? statusRes : <String, dynamic>{};
          final bool hasResult = statusMap['has_result_this_month'] == true;
          final int testedThisMonth = (statusMap['this_month_tested'] as num?)?.toInt() ?? 0;

          if (hasResult) {
            ind.hasResultThisMonth = true;
            ind.testedCount = testedThisMonth;
            ind.isNeverRecorded = false;

            final rpcRes = await client.rpc(
              ind.rpcName,
              params: {
                'target_month': _selectedMonth,
                'target_year': _selectedYear,
              },
            );

            final listRes = (rpcRes as List?) ?? [];
            final matched = listRes.map((e) {
              if (e is Map) return int.parse(e.values.first.toString());
              return int.parse(e.toString());
            }).toSet().intersection(activePcids);

            ind.metCount = matched.length;
            ind.affectedPcids = matched;
            ind.percentage = totalActive > 0 ? (matched.length / totalActive) * 100 : 0.0;
          } else {
            // No result this month: lookup historical previous result
            ind.hasResultThisMonth = false;
            ind.testedCount = 0;
            ind.metCount = 0;
            ind.affectedPcids = {};
            ind.percentage = 0.0;

            final lastMonth = statusMap['last_month'] as String?;
            final lastYear = (statusMap['last_year'] as num?)?.toInt();
            final lastTested = (statusMap['last_tested'] as num?)?.toInt() ?? 0;

            if (lastMonth != null && lastYear != null) {
              ind.isNeverRecorded = false;
              ind.lastResultMonth = lastMonth;
              ind.lastResultYear = lastYear;
              ind.lastResultTestedCount = lastTested;

              // Run RPC for the historical month to get exact percentage
              final histRpcRes = await client.rpc(
                ind.rpcName,
                params: {
                  'target_month': lastMonth,
                  'target_year': lastYear,
                },
              );

              final histList = (histRpcRes as List?) ?? [];
              final histMatched = histList.map((e) {
                if (e is Map) return int.parse(e.values.first.toString());
                return int.parse(e.toString());
              }).toSet().intersection(activePcids);

              ind.lastResultMetCount = histMatched.length;
              ind.lastResultPercentage = totalActive > 0
                  ? (histMatched.length / totalActive) * 100
                  : 0.0;
            } else {
              ind.isNeverRecorded = true;
              ind.lastResultMonth = null;
              ind.lastResultYear = null;
              ind.lastResultPercentage = null;
            }
          }
        } else {
          // Standard indicators
          if (ind.key == 'hb_dropping') ind.testedCount = hbTestedCount;
          if (ind.key == 'ca_high' || ind.key == 'ca_low') ind.testedCount = caTestedCount;
          if (ind.key == 'po4_rising') ind.testedCount = po4TestedCount;

          final rpcRes = await client.rpc(
            ind.rpcName,
            params: {
              'target_month': _selectedMonth,
              'target_year': _selectedYear,
            },
          );

          final listRes = (rpcRes as List?) ?? [];
          final matched = listRes.map((e) {
            if (e is Map) return int.parse(e.values.first.toString());
            return int.parse(e.toString());
          }).toSet().intersection(activePcids);

          ind.metCount = matched.length;
          ind.affectedPcids = matched;
          ind.hasResultThisMonth = ind.testedCount > 0 || matched.isNotEmpty;
          ind.percentage = totalActive > 0 ? (matched.length / totalActive) * 100 : 0.0;
        }
      });

      await Future.wait(futures);

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _showAffectedPatientsDialog(_IndicatorModel indicator) {
    if (indicator.affectedPcids.isEmpty) return;

    final affectedList = indicator.affectedPcids
        .map((id) => _activePatientsMap[id])
        .whereType<Map<String, dynamic>>()
        .toList();

    affectedList.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filtered = affectedList.where((p) {
              if (searchQuery.isEmpty) return true;
              final name = (p['name'] ?? '').toString().toLowerCase();
              final pcid = (p['pcid'] ?? '').toString();
              return name.contains(searchQuery.toLowerCase()) ||
                  pcid.contains(searchQuery);
            }).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.75,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 8, bottom: 4),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: indicator.themeColor.withValues(alpha: 0.15),
                              child: Icon(indicator.icon, color: indicator.themeColor),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    indicator.title,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '${affectedList.length} affected patient${affectedList.length == 1 ? '' : 's'} ($_selectedMonth $_selectedYear)',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'Search patient name or ID...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onChanged: (val) {
                            setSheetState(() => searchQuery = val);
                          },
                        ),
                      ),
                      const Divider(height: 20),
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(child: Text('No matching patients'))
                            : ListView.separated(
                                controller: scrollController,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                itemCount: filtered.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final p = filtered[index];
                                  final name = p['name'] ?? 'Unknown';
                                  final pcid = p['pcid'];
                                  final hall = p['hall_main'] ?? '-';
                                  final shift = p['shift_main'] ?? '-';
                                  final day = p['day_main'] ?? '-';
                                  final access = p['vaccess'] ?? '-';

                                  return Card(
                                    elevation: 0,
                                    color: Colors.grey.shade50,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: BorderSide(
                                        color: Colors.grey.shade200,
                                      ),
                                    ),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: Colors.teal.shade50,
                                        child: Text(
                                          '${index + 1}',
                                          style: TextStyle(
                                            color: Colors.teal.shade800,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      title: Text(
                                        name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Text(
                                        'ID: $pcid  •  $hall • $day $shift  •  Access: $access',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Color _getProgressColor(double percentage) {
    if (percentage >= 50) return Colors.red;
    if (percentage >= 25) return Colors.orange;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinical Indicator Optimized'),
        backgroundColor: const Color(0xFF1E5669),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Classic Clinical Indicators',
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const IndicatorsScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.home),
            tooltip: 'Return to Home',
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Header Bar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              border: Border(bottom: BorderSide(color: Colors.teal.shade100)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: DropdownButtonFormField<int>(
                        initialValue: _selectedYear,
                        decoration: InputDecoration(
                          labelText: 'Year',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        items: List.generate(10, (i) => 2024 + i)
                            .map(
                              (y) => DropdownMenuItem(
                                value: y,
                                child: Text('$y'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _selectedYear = v);
                            _fetchData();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 5,
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedMonth,
                        decoration: InputDecoration(
                          labelText: 'Month',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        items: BloodWeekController.months
                            .map(
                              (m) => DropdownMenuItem(
                                value: m,
                                child: Text(m),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _selectedMonth = v);
                            _fetchData();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 5,
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedVAccess,
                        decoration: InputDecoration(
                          labelText: 'Vascular Access',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        items: ['All', 'AVF', 'AVG', 'Perm. Cath']
                            .map(
                              (m) => DropdownMenuItem(
                                value: m,
                                child: Text(m),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _selectedVAccess = v);
                            _fetchData();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (_isLoading)
            const LinearProgressIndicator(color: Colors.teal, minHeight: 3),

          if (_errorMessage != null)
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Error: $_errorMessage',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                  TextButton(
                    onPressed: _fetchData,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),

          Expanded(
            child: RefreshIndicator(
              onRefresh: _fetchData,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _indicators.length,
                itemBuilder: (context, index) {
                  final indicator = _indicators[index];
                  return _buildIndicatorCard(indicator);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndicatorCard(_IndicatorModel indicator) {
    final bool isAdequacyEmpty =
        indicator.isAdequacy && !indicator.hasResultThisMonth;

    final progressColor = _getProgressColor(indicator.percentage);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isAdequacyEmpty
              ? Colors.orange.shade200
              : Colors.grey.shade200,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: indicator.metCount > 0
            ? () => _showAffectedPatientsDialog(indicator)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row: Title & Percentage
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: indicator.themeColor.withValues(alpha: 0.12),
                    child: Icon(
                      indicator.icon,
                      color: indicator.themeColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          indicator.title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E5669),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          indicator.subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isAdequacyEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.orange.shade300),
                      ),
                      child: Text(
                        'No results in $_selectedMonth',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    )
                  else
                    Text(
                      '${indicator.percentage.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: progressColor,
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: isAdequacyEmpty
                      ? 0.0
                      : (indicator.totalActive > 0
                          ? indicator.percentage / 100
                          : 0.0),
                  minHeight: 8,
                  backgroundColor: Colors.grey.shade200,
                  color: isAdequacyEmpty ? Colors.grey : progressColor,
                ),
              ),

              const SizedBox(height: 12),

              // Historical Fallback Line (For URR, KT/V, OCM KT/V when no results)
              if (isAdequacyEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blueGrey.shade100),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        indicator.isNeverRecorded
                            ? Icons.info_outline
                            : Icons.history,
                        size: 16,
                        color: indicator.isNeverRecorded
                            ? Colors.grey.shade600
                            : Colors.teal.shade800,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          indicator.isNeverRecorded
                              ? 'Never recorded'
                              : 'Last result was ${indicator.lastResultPercentage?.toStringAsFixed(1)}% (${indicator.lastResultMonth} ${indicator.lastResultYear})',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: indicator.isNeverRecorded
                                ? Colors.grey.shade700
                                : Colors.teal.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // Footer Stats Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        'Affected: ${isAdequacyEmpty ? 0 : indicator.metCount}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: indicator.metCount > 0 && !isAdequacyEmpty
                              ? Colors.red.shade700
                              : Colors.grey.shade700,
                        ),
                      ),
                      if (indicator.testedCount > 0 && !isAdequacyEmpty) ...[
                        Text(
                          '  (Tested: ${indicator.testedCount})',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        'Total active: ${indicator.totalActive}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      if (indicator.metCount > 0 && !isAdequacyEmpty) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: Colors.teal.shade700,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

