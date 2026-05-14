import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MedicationsScreen extends StatefulWidget {
  final Map<String, dynamic> patient;

  const MedicationsScreen({super.key, required this.patient});

  @override
  State<MedicationsScreen> createState() => _MedicationsScreenState();
}

class _MedicationsScreenState extends State<MedicationsScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isSaving = false;
  int? _existingRecordId;

  final _medicBoneController = TextEditingController();
  final _medicHbController = TextEditingController();
  final _medicOtherController = TextEditingController();
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchMedications();
  }

  @override
  void dispose() {
    _medicBoneController.dispose();
    _medicHbController.dispose();
    _medicOtherController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _fetchMedications() async {
    setState(() => _isLoading = true);

    try {
      final result = await Supabase.instance.client
          .from('medicationstb')
          .select()
          .eq('pcid', widget.patient['pcid'])
          .maybeSingle();

      if (result != null) {
        _existingRecordId = result['id'];
        _medicBoneController.text = result['medicbone'] ?? '';
        _medicHbController.text = result['medicHb'] ?? '';
        _medicOtherController.text = result['medicOther'] ?? '';
        _noteController.text = result['note'] ?? '';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading medications: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveMedications() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final data = {
        'pcid': widget.patient['pcid'],
        'medicbone': _medicBoneController.text.trim(),
        'medicHb': _medicHbController.text.trim(),
        'medicOther': _medicOtherController.text.trim(),
        'note': _noteController.text.trim(),
      };

      if (_existingRecordId != null) {
        // Update existing record
        await Supabase.instance.client
            .from('medicationstb')
            .update(data)
            .eq('id', _existingRecordId!);
      } else {
        // Insert new record
        final result = await Supabase.instance.client
            .from('medicationstb')
            .insert(data)
            .select('id')
            .single();
        _existingRecordId = result['id'];
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Medications saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving medications: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Medications', style: TextStyle(fontSize: 16)),
            Text(
              '${widget.patient['name']} (ID: ${widget.patient['pcid']})',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        backgroundColor: const Color.fromARGB(255, 43, 138, 161),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            tooltip: 'Return to Home',
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilledButton.icon(
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save, size: 20),
              label: Text(_isSaving ? 'Saving...' : 'Save'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 6, 107, 95),
                foregroundColor: Colors.white,
              ),
              onPressed: _isSaving ? null : _saveMedications,
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildMedicationCard(
                      title: 'Bone Medication',
                      icon: Icons.healing,
                      iconColor: Colors.orange,
                      controller: _medicBoneController,
                      hintText: 'Enter bone medication details...',
                    ),
                    const SizedBox(height: 16),
                    _buildMedicationCard(
                      title: 'HB Medication',
                      icon: Icons.bloodtype,
                      iconColor: Colors.red,
                      controller: _medicHbController,
                      hintText: 'Enter HB medication details...',
                    ),
                    const SizedBox(height: 16),
                    _buildMedicationCard(
                      title: 'Other Medications',
                      icon: Icons.medication,
                      iconColor: Colors.blue,
                      controller: _medicOtherController,
                      hintText: 'Enter other medication details...',
                    ),
                    const SizedBox(height: 16),
                    _buildMedicationCard(
                      title: 'Notes',
                      icon: Icons.note_alt_outlined,
                      iconColor: Colors.teal,
                      controller: _noteController,
                      hintText: 'Additional notes...',
                      maxLines: 4,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildMedicationCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required TextEditingController controller,
    required String hintText,
    int maxLines = 2,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 24),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: controller,
              maxLines: maxLines,
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: TextStyle(color: Colors.grey.shade400),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
