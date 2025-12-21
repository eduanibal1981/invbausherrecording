import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'bloodweek_controller.dart';

class BloodWeekScreen extends StatefulWidget {
  final Map<String, dynamic> patient;

  const BloodWeekScreen({super.key, required this.patient});

  @override
  State<BloodWeekScreen> createState() => _BloodWeekScreenState();
}

class _BloodWeekScreenState extends State<BloodWeekScreen> {
  late BloodWeekController controller;

  final List<String> _fields = const [
    'hb',
    'wbc',
    'plt',
    // ⬅️ keep your real field list here
  ];

  @override
  void initState() {
    super.initState();
    controller = BloodWeekController(_fields);

    // ✅ fetch AFTER first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.fetchData(
        pcid: widget.patient['id'],
        year: DateTime.now().year,
        month: DateTime.now().month,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: controller,
      child: Consumer<BloodWeekController>(
        builder: (context, c, _) {
          return Scaffold(
            appBar: AppBar(title: const Text('Blood Week')),
            body: Column(
              children: [
                if (c.isLoading) const LinearProgressIndicator(),
                Expanded(child: _buildForm(c)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildForm(BloodWeekController c) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: _fields.map((f) {
          return SizedBox(
            width: 150,
            child: TextFormField(
              controller: c.controllers[f],
              decoration: InputDecoration(labelText: f.toUpperCase()),
            ),
          );
        }).toList(),
      ),
    );
  }
}
