import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'bloodweek_model.dart';

class BloodWeekController extends ChangeNotifier {
  final SupabaseClient supabase = Supabase.instance.client;

  final List<String> fields;
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

  int? existingRecordId;

  /// Public method to set isDrRevBw and mark as unsaved
  void setDrReview(bool value) {
    isDrRevBw = value;
    hasUnsavedChanges = true;
    notifyListeners();
  }

  BloodWeekController(this.fields) {
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

      if (response != null) {
        final model = BloodWeekModel.fromMap(response, fields);

        _cache[key] = model; // ✅ cache it
        _applyModel(model);
      } else {
        _clearForm();
      }
    } catch (_) {
      // 🔥 OFFLINE FALLBACK
      if (_cache.containsKey(key)) {
        _applyModel(_cache[key]!);
      }
    }

    isLoading = false;
    notifyListeners();
  }

  /// Saves data to Supabase.
  /// Returns null on success, or an error message on failure.
  Future<String?> saveData(int pcid) async {
    isLoading = true;
    notifyListeners();

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
