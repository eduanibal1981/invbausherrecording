class BloodWeekModel {
  final int? id;
  final bool needCollect;
  final bool isDrRevBw;
  final Map<String, dynamic> values;

  const BloodWeekModel({
    this.id,
    required this.needCollect,
    required this.isDrRevBw,
    required this.values,
  });

  factory BloodWeekModel.fromMap(
    Map<String, dynamic> map,
    List<String> fields,
  ) {
    return BloodWeekModel(
      id: map['id'] as int?,
      needCollect: map['needcolect'] == true,
      isDrRevBw: map['isdrrevbw'] == true,
      values: {
        for (final f in fields)
          f: map.containsKey(f) && map[f] != null ? map[f] : '',
      },
    );
  }

  /// Optional: create a copy with modified values (future-proof)
  BloodWeekModel copyWith({
    int? id,
    bool? needCollect,
    bool? isDrRevBw,
    Map<String, dynamic>? values,
  }) {
    return BloodWeekModel(
      id: id ?? this.id,
      needCollect: needCollect ?? this.needCollect,
      isDrRevBw: isDrRevBw ?? this.isDrRevBw,
      values: values ?? this.values,
    );
  }
}
