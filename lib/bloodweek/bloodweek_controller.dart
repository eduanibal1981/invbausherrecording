import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'bloodweek_model.dart';

class BloodWeekController extends ChangeNotifier {
  final SupabaseClient supabase = Supabase.instance.client;

  final List<String> fields;
  final Map<String, TextEditingController> controllers = {};

  bool isLoading = false;
  bool hasUnsavedChanges = false;
  bool needCollect = false;
  bool isDrRevBw = false;

  int? existingRecordId;

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

  Future<void> fetchData({
    required int pcid,
    required int year,
    required int month,
  }) async {
    isLoading = true;
    notifyListeners();

    final response = await supabase
        .from('bloodweek')
        .select()
        .eq('pcid', pcid)
        .eq('year', year)
        .eq('month', month)
        .maybeSingle();

    if (response != null) {
      final model = BloodWeekModel.fromMap(response, fields);

      existingRecordId = model.id;
      needCollect = model.needCollect;
      isDrRevBw = model.isDrRevBw;

      // 🔥 CRITICAL OPTIMIZATION
      for (final f in fields) {
        controllers[f]!
          ..removeListener(_onFieldChanged)
          ..text = model.values[f]?.toString() ?? ''
          ..addListener(_onFieldChanged);
      }

      hasUnsavedChanges = false;
    }

    isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }
}
