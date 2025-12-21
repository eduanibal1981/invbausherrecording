class BloodWeekModel {
  final int id;
  final bool needCollect;
  final bool isDrRevBw;
  final Map<String, dynamic> values;

  BloodWeekModel({
    required this.id,
    required this.needCollect,
    required this.isDrRevBw,
    required this.values,
  });

  factory BloodWeekModel.fromMap(
    Map<String, dynamic> map,
    List<String> fields,
  ) {
    return BloodWeekModel(
      id: map['id'],
      needCollect: map['needcolect'] ?? false,
      isDrRevBw: map['isdrrevbw'] ?? false,
      values: {for (final f in fields) f: map[f]},
    );
  }
}
