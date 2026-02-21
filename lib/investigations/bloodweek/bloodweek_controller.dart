import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'bloodweek_model.dart';

class BloodWeekController extends ChangeNotifier {
  final SupabaseClient supabase = Supabase.instance.client;

  final List<String> fields;
  final int? medicalStaffId;
  final Map<String, TextEditingController> controllers = {};
  static final Map<String, BloodWeekModel> _cache = {};

  String _cacheKey(int pcid) => '$pcid-$selectedYear-$selectedMonth';

  static const List<String> months = [
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

  int selectedYear = DateTime.now().year;
  String selectedMonth = months[DateTime.now().month - 1];

  bool isLoading = false;
  bool hasUnsavedChanges = false;
  bool needCollect = false;
  bool isDrRevBw = false;
  bool isOfflineData = false;
  String? errorMessage;

  int? existingRecordId;
  BloodWeekModel? previousMonthData;
  String? previousMonthStr;

  /// Public method to set isDrRevBw and mark as unsaved
  void setDrReview(bool value) {
    isDrRevBw = value;
    hasUnsavedChanges = true;
    notifyListeners();
  }

  BloodWeekController(this.fields, {this.medicalStaffId}) {
    for (final f in fields) {
      final c = TextEditingController();
      c.addListener(_onFieldChanged);
      controllers[f] = c;
    }
  }

  void _onFieldChanged() {
    if (!hasUnsavedChanges) {
      hasUnsavedChanges = true;
      notifyListeners();
    }
  }

  Future<void> fetchData(int pcid) async {
    isLoading = true;
    notifyListeners();

    final key = _cacheKey(pcid);

    try {
      final response = await supabase
          .from('bloodweek')
          .select()
          .eq('pcid', pcid)
          .eq('year', selectedYear)
          .eq('month', selectedMonth)
          .maybeSingle();

      isOfflineData = false;
      errorMessage = null;

      if (response != null) {
        final model = BloodWeekModel.fromMap(response, fields);

        _cache[key] = model; // ✅ cache it
        _applyModel(model);
      } else {
        _clearForm();
      }

      await _fetchPreviousMonthData(pcid);
    } catch (e) {
      // 🔥 OFFLINE FALLBACK
      if (_cache.containsKey(key)) {
        isOfflineData = true;
        errorMessage = 'Showing cached data (offline)';
        _applyModel(_cache[key]!);
      } else {
        errorMessage = 'No data available offline';
      }
    }

    isLoading = false;
    notifyListeners();
  }

  Future<void> _fetchPreviousMonthData(int pcid) async {
    int prevYear = selectedYear;
    int currMonthIndex = months.indexOf(selectedMonth);
    int prevMonthIndex;

    if (currMonthIndex == 0) {
      prevMonthIndex = 11;
      prevYear--;
    } else {
      prevMonthIndex = currMonthIndex - 1;
    }

    String prevMonth = months[prevMonthIndex];
    previousMonthStr = prevMonth;
    final String prevKey = '$pcid-$prevYear-$prevMonth';

    if (_cache.containsKey(prevKey)) {
      previousMonthData = _cache[prevKey];
      return;
    }

    try {
      final prevResponse = await supabase
          .from('bloodweek')
          .select()
          .eq('pcid', pcid)
          .eq('year', prevYear)
          .eq('month', prevMonth)
          .maybeSingle();

      if (prevResponse != null) {
        final model = BloodWeekModel.fromMap(prevResponse, fields);
        _cache[prevKey] = model;
        previousMonthData = model;
      } else {
        previousMonthData = null;
      }
    } catch (e) {
      previousMonthData = null;
    }
  }

  /// Saves data to Supabase.
  /// Returns null on success, or an error message on failure.
  Future<String?> saveData(int pcid) async {
    isLoading = true;
    notifyListeners();

    final cbchbValue = controllers['cbchb']?.text ?? '';
    final staffEnterValue = controllers['staffenter']?.text ?? '';

    // Auto-set staffenter if cbchb is entered and staffenter is empty/null
    if (cbchbValue.isNotEmpty &&
        staffEnterValue.isEmpty &&
        medicalStaffId != null) {
      controllers['staffenter']?.text = medicalStaffId.toString();
    }

    final data = {
      'pcid': pcid,
      'year': selectedYear,
      'month': selectedMonth,
      'needcolect': needCollect,
      'isdrrevbw': isDrRevBw,
      for (var f in fields)
        f: f == 'staffenter'
            ? controllers[f]!.text
            : double.tryParse(controllers[f]!.text),
    };

    try {
      if (existingRecordId != null) {
        await supabase
            .from('bloodweek')
            .update(data)
            .eq('id', existingRecordId!);
      } else {
        await supabase.from('bloodweek').insert(data);
      }

      await fetchData(pcid);
      return null; // Success
    } catch (e) {
      isLoading = false;
      notifyListeners();
      return 'Save failed: ${e.toString().contains('SocketException') || e.toString().contains('ClientException') ? 'No internet connection' : e.toString()}';
    }
  }

  void changeYear(int year, int pcid) {
    selectedYear = year;
    fetchData(pcid);
  }

  void changeMonth(String month, int pcid) {
    selectedMonth = month;
    fetchData(pcid);
  }

  void _clearForm() {
    existingRecordId = null;
    isDrRevBw = false;
    needCollect = false;
    isOfflineData = false;
    errorMessage = null;
    previousMonthData = null;
    for (final c in controllers.values) {
      c.clear();
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _applyModel(BloodWeekModel model) {
    existingRecordId = model.id;
    needCollect = model.needCollect;
    isDrRevBw = model.isDrRevBw;

    for (final f in fields) {
      controllers[f]!
        ..removeListener(_onFieldChanged)
        ..text = model.values[f]?.toString() ?? ''
        ..addListener(_onFieldChanged);
    }

    hasUnsavedChanges = false;
  }
}
