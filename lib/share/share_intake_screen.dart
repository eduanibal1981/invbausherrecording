import 'dart:io';

import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/login_screen.dart';
import '../vascandecg/ecg_upload_screen.dart';
import '../vascandecg/vascular_upload_screen.dart';

enum ShareTargetType { ecg, vascular }

class ShareIntakeScreen extends StatefulWidget {
  final List<SharedMediaFile> sharedFiles;

  const ShareIntakeScreen({super.key, required this.sharedFiles});

  @override
  State<ShareIntakeScreen> createState() => _ShareIntakeScreenState();
}

class _ShareIntakeScreenState extends State<ShareIntakeScreen> {
  final TextEditingController _searchController = TextEditingController();

  late Future<List<Map<String, dynamic>>> _patientsFuture;
  String? _staffRole;

  List<Map<String, dynamic>> _allPatients = [];
  List<Map<String, dynamic>> _visiblePatients = [];
  Map<String, dynamic>? _selectedPatient;
  ShareTargetType? _selectedType;

  late final List<String> _sharedPaths;

  bool get _isAuthenticated =>
      Supabase.instance.client.auth.currentSession != null;

  @override
  void initState() {
    super.initState();
    _sharedPaths = _extractUniqueExistingPaths(widget.sharedFiles);
    _patientsFuture = _fetchPatients();
    _fetchStaffRole();
    _searchController.addListener(_applySearch);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_applySearch)
      ..dispose();
    super.dispose();
  }

  Future<void> _fetchStaffRole() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final data = await Supabase.instance.client
          .from('staff')
          .select('staffrole')
          .eq('userid', userId)
          .maybeSingle();
      if (!mounted) return;
      setState(() => _staffRole = data?['staffrole']?.toString());
    } catch (_) {
      // Non-blocking: staff role is optional for this flow.
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPatients() async {
    try {
      final response = await Supabase.instance.client
          .from('patients')
          .select()
          .eq('status', 'Active')
          .order('name');
      final patients = List<Map<String, dynamic>>.from(response as List);
      _allPatients = patients;
      _visiblePatients = patients;
      return patients;
    } catch (e) {
      throw Exception('Failed to load patients: $e');
    }
  }

  void _applySearch() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _visiblePatients = _allPatients);
      return;
    }
    final filtered = _allPatients.where((patient) {
      final name = (patient['name'] ?? '').toString().toLowerCase();
      final id = (patient['pcid'] ?? '').toString().toLowerCase();
      return name.contains(query) || id.contains(query);
    }).toList();
    setState(() => _visiblePatients = filtered);
  }

  List<String> _extractUniqueExistingPaths(List<SharedMediaFile> files) {
    final seen = <String>{};
    final paths = <String>[];
    for (final file in files) {
      final path = file.path;
      if (path.isEmpty) continue;
      if (seen.contains(path)) continue;
      // Only accept paths we can actually read.
      if (!File(path).existsSync()) continue;
      seen.add(path);
      paths.add(path);
    }
    return paths;
  }

  void _continue() {
    final patient = _selectedPatient;
    final type = _selectedType;
    if (patient == null || type == null) return;
    if (_sharedPaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No readable shared images found.')),
      );
      return;
    }

    switch (type) {
      case ShareTargetType.ecg:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EcgUploadScreen(
              patient: patient,
              staffRole: _staffRole,
              initialSharedPaths: _sharedPaths,
              entrySourceLabel: 'Shared Images',
            ),
          ),
        );
        break;
      case ShareTargetType.vascular:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VascularUploadScreen(
              patient: patient,
              staffRole: _staffRole,
              initialSharedPaths: _sharedPaths,
              entrySourceLabel: 'Shared Images',
            ),
          ),
        );
        break;
    }
  }

  Future<void> _goToLogin() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    if (!mounted) return;
    setState(() {
      _patientsFuture = _fetchPatients();
    });
    _fetchStaffRole();
  }

  @override
  Widget build(BuildContext context) {
    final sharedCount = _sharedPaths.length;
    return Scaffold(
      appBar: AppBar(
        title: Text('Import Shared Images ($sharedCount)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            tooltip: 'Return to Home',
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ],
      ),
      body: !_isAuthenticated
          ? _buildLoginRequired()
          : FutureBuilder<List<Map<String, dynamic>>>(
              future: _patientsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                return _buildContent();
              },
            ),
    );
  }

  Widget _buildLoginRequired() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 56),
            const SizedBox(height: 16),
            const Text(
              'Login Required',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please log in to attach these shared images to a patient.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _goToLogin,
              icon: const Icon(Icons.login),
              label: const Text('Go To Login'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final canContinue = _selectedPatient != null && _selectedType != null;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.blueGrey.shade50,
          child: Text(
            'Shared items ready: ${_sharedPaths.length}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: 'Search Patient (Name or ID)',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () =>
                      setState(() => _selectedType = ShareTargetType.ecg),
                  icon: const Icon(Icons.monitor_heart_outlined),
                  label: Text(
                    _selectedType == ShareTargetType.ecg ? 'ECG ✓' : 'ECG',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => setState(
                    () => _selectedType = ShareTargetType.vascular,
                  ),
                  icon: const Icon(Icons.monitor_heart),
                  label: Text(
                    _selectedType == ShareTargetType.vascular
                        ? 'Vascular ✓'
                        : 'Vascular',
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _visiblePatients.isEmpty
              ? const Center(child: Text('No patients match your search.'))
              : ListView.separated(
                  itemCount: _visiblePatients.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final patient = _visiblePatients[index];
                    final isSelected =
                        _selectedPatient?['pcid'] == patient['pcid'];
                    return ListTile(
                      selected: isSelected,
                      selectedTileColor: Colors.teal.shade50,
                      title: Text(patient['name']?.toString() ?? 'Unknown'),
                      subtitle: Text('ID: ${patient['pcid']}'),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle, color: Colors.teal)
                          : null,
                      onTap: () => setState(() => _selectedPatient = patient),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: canContinue ? _continue : null,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Continue To Upload'),
            ),
          ),
        ),
      ],
    );
  }
}

