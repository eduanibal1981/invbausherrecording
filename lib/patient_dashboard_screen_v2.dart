import 'package:flutter/material.dart';
import 'package:invbausherrecording/bloodweek/bloodweek_screen.dart';
import 'parathyroid_screen.dart';
import 'iron_profile_screen.dart';

class PatientDashboardScreenV2 extends StatefulWidget {
  final Map<String, dynamic> patient;
  final String? staffRole;
  final int? medicalStaffId;
  final List<Map<String, dynamic>>? patientList;
  final int? currentIndex;

  const PatientDashboardScreenV2({
    super.key,
    required this.patient,
    this.staffRole,
    this.medicalStaffId,
    this.patientList,
    this.currentIndex,
  });

  @override
  State<PatientDashboardScreenV2> createState() =>
      _PatientDashboardScreenV2State();
}

class _PatientDashboardScreenV2State extends State<PatientDashboardScreenV2> {
  late Map<String, dynamic> _currentPatient;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentPatient = widget.patient;
    _currentIndex = widget.currentIndex ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_currentPatient['name'] ?? 'Unknown'),
            Text(
              'ID: ${_currentPatient['pcid']}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildMenuItem(
            context,
            title: 'Blood Week Investigations',
            icon: Icons.water_drop_sharp,
            color: Colors.red.shade100,
            iconColor: Colors.red.shade900,
            onTap: () async {
              final newIndex = await Navigator.push<int>(
                context,
                MaterialPageRoute(
                  builder: (_) => BloodWeekScreen(
                    patient: _currentPatient,
                    staffRole: widget.staffRole,
                    medicalStaffId: widget.medicalStaffId,
                    patientList: widget.patientList,
                    currentIndex: _currentIndex,
                  ),
                ),
              );

              if (newIndex != null && newIndex != _currentIndex && mounted) {
                setState(() {
                  _currentIndex = newIndex;
                  _currentPatient = widget.patientList![newIndex];
                });
              }
            },
          ),
          const SizedBox(height: 16),
          _buildMenuItem(
            context,
            title: 'Parathyroid Investigations',
            icon: Icons.shield_moon_sharp,
            color: Colors.purple.shade200,
            iconColor: Colors.purple.shade900,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ParathyroidScreen(
                    patient: _currentPatient,
                    staffRole: widget.staffRole,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          _buildMenuItem(
            context,
            title: 'Iron Profile Investigations',
            icon: Icons.panorama_fish_eye_sharp,
            color: Colors.brown.shade100,
            iconColor: Colors.brown.shade900,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => IronProfileScreen(
                    patient: _currentPatient,
                    staffRole: widget.staffRole,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, size: 32, color: iconColor),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward_ios, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
