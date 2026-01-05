import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        backgroundColor: const Color.fromARGB(255, 43, 138, 161),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 32),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.shield_moon,
                  size: 60,
                  color: Color.fromARGB(255, 43, 138, 161),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'InvBausher Recording',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color.fromARGB(255, 43, 138, 161),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Version 1.0.0',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 24),
              const Text(
                'About This App',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                'This application is designed for medical staff to efficiently manage patient records, track schedules, and monitor treatment progress. It simplifies the workflow for nurses and doctors, ensuring better patient care.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[800],
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 24),
              _buildInfoRow(
                Icons.business,
                'Developed By Dr Abdalla Khalaf Gomaa -- Bausher RDC',
              ),
              const SizedBox(height: 16),
              _buildInfoRow(Icons.phone, '93990492'),
              const SizedBox(height: 16),
              _buildInfoRow(
                Icons.copyright,
                '${DateTime.now().year} All Rights Reserved',
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(fontSize: 16, color: Colors.grey[700])),
      ],
    );
  }
}
