import 'package:flutter/material.dart';
import 'package:invbausherrecording/bloodweek/bloodweek_screen.dart';
import 'parathyroid_screen.dart';
import 'iron_profile_screen.dart';

class PatientDashboardScreenV2 extends StatelessWidget {
  final Map<String, dynamic> patient;
  final String? staffRole;

  const PatientDashboardScreenV2({
    super.key,
    required this.patient,
    this.staffRole,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(patient['name'] ?? 'Unknown'),
            Text(
              'ID: ${patient['pcid']}',
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
            destination: BloodWeekScreen(
              patient: patient,
              staffRole: staffRole,
            ),
          ),
          const SizedBox(height: 16),
          _buildMenuItem(
            context,
            title: 'Parathyroid Investigations',
            icon: Icons.shield_moon_sharp,
            color: Colors.purple.shade100,
            iconColor: Colors.purple.shade900,
            destination: ParathyroidScreen(
              patient: patient,
              staffRole: staffRole,
            ),
          ),
          const SizedBox(height: 16),
          _buildMenuItem(
            context,
            title: 'Iron Profile Investigations',
            icon: Icons.panorama_fish_eye_sharp,
            color: Colors.brown.shade100,
            iconColor: Colors.brown.shade900,
            destination: IronProfileScreen(
              patient: patient,
              staffRole: staffRole,
            ),
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
    required Widget destination,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => destination),
          );
        },
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
