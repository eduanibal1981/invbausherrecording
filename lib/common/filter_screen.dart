import 'package:flutter/material.dart';

class FilterScreen extends StatefulWidget {
  final Map<String, dynamic> initialFilters;

  const FilterScreen({super.key, required this.initialFilters});

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  final _searchController = TextEditingController();
  String? _hallName;
  String? _day;
  String? _shift;
  String? _labFilter; // null = Any, 'has' = Has Labs, 'none' = No Labs
  String? _vascularFilter; // null = Any, 'has' = Has Images, 'none' = No Images
  String? _ecgFilter; // null = Any, 'has' = Has Images, 'none' = No Images
  String? _vaccessFilter; // null = Any, or specific access type
  String?
  _labAbnormalityFilter; // null = Any, 'hb_dropping', 'po4_rising', 'pth_rising'
  bool _outPatientsOnly = false;
  bool _hasSearchText = false;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialFilters['search'] ?? '';
    _hasSearchText = _searchController.text.trim().isNotEmpty;
    _searchController.addListener(_handleSearchChanged);
    _hallName = widget.initialFilters['hallname'];
    _day = widget.initialFilters['day'];
    _shift = widget.initialFilters['shift'];
    _labFilter = widget.initialFilters['labFilter'];
    if (_labFilter == null &&
        widget.initialFilters['showLabNotRecorded'] == true) {
      _labFilter = 'none';
    }
    _vascularFilter = widget.initialFilters['vascularFilter'];
    _ecgFilter = widget.initialFilters['ecgFilter'];
    _vaccessFilter = widget.initialFilters['vaccessFilter'];
    _labAbnormalityFilter = widget.initialFilters['labAbnormalityFilter'];
    _outPatientsOnly = widget.initialFilters['outPatientsOnly'] == true;
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    final hasText = _searchController.text.trim().isNotEmpty;
    if (hasText == _hasSearchText) return;
    setState(() => _hasSearchText = hasText);
  }

  void _apply() {
    Navigator.pop(context, {
      if (_searchController.text.isNotEmpty)
        'search': _searchController.text.trim(),
      if (_hallName != null) 'hallname': _hallName,
      if (_day != null) 'day': _day,
      if (_shift != null) 'shift': _shift,
      if (_labFilter != null) 'labFilter': _labFilter,
      if (_vascularFilter != null) 'vascularFilter': _vascularFilter,
      if (_ecgFilter != null) 'ecgFilter': _ecgFilter,
      if (_vaccessFilter != null) 'vaccessFilter': _vaccessFilter,
      if (_labAbnormalityFilter != null)
        'labAbnormalityFilter': _labAbnormalityFilter,
      if (_outPatientsOnly) 'outPatientsOnly': true,
    });
  }

  void _clear() {
    Navigator.pop(context, <String, dynamic>{});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Filter the Patients')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Search Name or ID',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _hasSearchText
                  ? IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _handleSearchChanged();
                      },
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            title: const Text('? Out patients'),
            subtitle: const Text(
              'Show active patients who are out of position',
            ),
            value: _outPatientsOnly,
            onChanged: (val) {
              setState(() {
                _outPatientsOnly = val ?? false;
              });
            },
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            activeColor: Colors.teal,
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: Colors.teal.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.teal.shade100),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Schedule Filters',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _hallName,
                    decoration: InputDecoration(
                      labelText: 'Hall Name',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 0,
                      ),
                    ),
                    items:
                        [
                              'HALL 1',
                              'HALL 2',
                              'HALL 3',
                              'HALL 4',
                              'HALL 5',
                              'HALL 6',
                              'HALL 7',
                            ]
                            .map(
                              (h) => DropdownMenuItem(value: h, child: Text(h)),
                            )
                            .toList(),
                    onChanged: (val) => setState(() => _hallName = val),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _day,
                          decoration: InputDecoration(
                            labelText: 'Day',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 0,
                            ),
                          ),
                          items:
                              [
                                    'Saturday',
                                    'Sunday',
                                    'Monday',
                                    'Tuesday',
                                    'Wednesday',
                                    'Thursday',
                                  ]
                                  .map(
                                    (d) => DropdownMenuItem(
                                      value: d,
                                      child: Text(d),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (val) => setState(() => _day = val),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _shift,
                          decoration: InputDecoration(
                            labelText: 'Shift',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 0,
                            ),
                          ),
                          items: ['AM', 'PM', 'LPM', 'NIGHT']
                              .map(
                                (s) =>
                                    DropdownMenuItem(value: s, child: Text(s)),
                              )
                              .toList(),
                          onChanged: (val) => setState(() => _shift = val),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: Colors.orange.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.orange.shade100),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Monthly Labs',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _labFilter,
                    decoration: InputDecoration(
                      labelText: 'Filter By',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 0,
                      ),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Any')),
                      const DropdownMenuItem(
                        value: 'has',
                        child: Text('Has Labs'),
                      ),
                      const DropdownMenuItem(
                        value: 'none',
                        child: Text('No Labs'),
                      ),
                      ...[
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
                      ].expand(
                        (m) => [
                          DropdownMenuItem(
                            value: 'has_$m 2026',
                            child: Text('Has Labs ($m 2026)'),
                          ),
                          DropdownMenuItem(
                            value: 'none_$m 2026',
                            child: Text('No Labs ($m 2026)'),
                          ),
                        ],
                      ),
                    ],
                    onChanged: (val) => setState(() => _labFilter = val),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: Colors.brown.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.brown.shade100),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lab Abnormalities',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.brown.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _labAbnormalityFilter,
                    decoration: InputDecoration(
                      labelText: 'Filter By Lab Trends',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 0,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Any')),
                      DropdownMenuItem(
                        value: 'hb_dropping',
                        child: Text('Hb < 10 & Dropped'),
                      ),
                      DropdownMenuItem(
                        value: 'po4_rising',
                        child: Text('Po4 > 1.8 & Rose'),
                      ),
                      DropdownMenuItem(
                        value: 'pth_rising',
                        child: Text('PTH > 59 & Rose'),
                      ),
                    ],
                    onChanged: (val) =>
                        setState(() => _labAbnormalityFilter = val),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: Colors.red.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.red.shade100),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vascular/Doppler Images',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _vascularFilter,
                    decoration: InputDecoration(
                      labelText: 'Filter By',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 0,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Any')),
                      DropdownMenuItem(value: 'has', child: Text('Has Images')),
                      DropdownMenuItem(value: 'none', child: Text('No Images')),
                    ],
                    onChanged: (val) => setState(() => _vascularFilter = val),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: Colors.pink.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.pink.shade100),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ECG Images',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.pink.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _ecgFilter,
                    decoration: InputDecoration(
                      labelText: 'Filter By',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 0,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Any')),
                      DropdownMenuItem(value: 'has', child: Text('Has Images')),
                      DropdownMenuItem(value: 'none', child: Text('No Images')),
                    ],
                    onChanged: (val) => setState(() => _ecgFilter = val),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: Colors.purple.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.purple.shade100),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vascular Access Type',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _vaccessFilter,
                    decoration: InputDecoration(
                      labelText: 'Filter By Access Type',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 0,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Any')),
                      DropdownMenuItem(value: 'AVF', child: Text('AVF')),
                      DropdownMenuItem(value: 'AVG', child: Text('AVG')),
                      DropdownMenuItem(
                        value: 'Perm. Cath',
                        child: Text('Perm. Cath'),
                      ),
                    ],
                    onChanged: (val) => setState(() => _vaccessFilter = val),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _clear,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                  child: const Text('Clear All'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton(
                  onPressed: _apply,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                  child: const Text('Apply Filter'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
