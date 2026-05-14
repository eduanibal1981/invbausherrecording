import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StaffOnLeaveScreen extends StatefulWidget {
  const StaffOnLeaveScreen({super.key});

  @override
  State<StaffOnLeaveScreen> createState() => _StaffOnLeaveScreenState();
}

class _StaffOnLeaveScreenState extends State<StaffOnLeaveScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  List<Map<String, dynamic>> _staffOnLeave = [];

  @override
  void initState() {
    super.initState();
    _fetchStaffOnLeave();
  }

  Future<void> _fetchStaffOnLeave() async {
    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client
          .from('staff')
          .select('medicalstaffid, name, staffrole, is_on_leave')
          .order('is_on_leave', ascending: false)
          .order('name');

      setState(() {
        _staffOnLeave = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching staff on leave: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleLeaveStatus(int staffId, String name, bool currentlyOnLeave) async {
    final newStatus = !currentlyOnLeave;
    final actionText = newStatus ? 'mark $name as on leave' : 'mark $name as returned from leave';
    final titleText = newStatus ? 'Mark On Leave' : 'Mark as Returned';
    final buttonText = newStatus ? 'Set Leave' : 'Mark Returned';
    final buttonColor = newStatus ? Colors.orange : Colors.green;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titleText),
        content: Text('Are you sure you want to $actionText?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: buttonColor,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(buttonText),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSaving = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      String changedBy = 'Unknown';
      if (userId != null) {
        try {
          final staffData = await Supabase.instance.client
              .from('staff')
              .select('name')
              .eq('userid', userId)
              .maybeSingle();
          if (staffData != null && staffData['name'] != null) {
            changedBy = staffData['name'];
          }
        } catch (_) {}
      }

      await Supabase.instance.client
          .from('staff')
          .update({'is_on_leave': newStatus, 'changby': changedBy})
          .eq('medicalstaffid', staffId);

      await _fetchStaffOnLeave();

      if (mounted) {
        final successText = newStatus ? '$name marked as on leave.' : '$name has been marked as returned.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successText),
            backgroundColor: buttonColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating status: $e'),
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
        title: const Text('Staff on Leave'),
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchStaffOnLeave,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _staffOnLeave.isEmpty
          ? const Center(
              child: Text(
                'No staff members found.',
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
            )
          : Stack(
              children: [
                ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _staffOnLeave.length,
                  itemBuilder: (context, index) {
                    final staff = _staffOnLeave[index];
                    final staffId = staff['medicalstaffid'] as int;
                    final name = staff['name'] as String? ?? 'Unknown';
                    final role = staff['staffrole'] as String? ?? 'Staff';
                    final isOnLeave = staff['is_on_leave'] == true;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: isOnLeave ? Colors.orange.shade700 : Colors.green.shade700,
                          child: Icon(isOnLeave ? Icons.beach_access : Icons.work, color: Colors.white),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Text(role),
                        trailing: OutlinedButton.icon(
                          onPressed: () => _toggleLeaveStatus(staffId, name, isOnLeave),
                          icon: Icon(isOnLeave ? Icons.check : Icons.beach_access, size: 18),
                          label: Text(isOnLeave ? 'Return' : 'Set Leave'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isOnLeave ? Colors.green.shade700 : Colors.orange.shade700,
                            side: BorderSide(color: isOnLeave ? Colors.green.shade700 : Colors.orange.shade700),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                if (_isSaving)
                  Container(
                    color: Colors.black26,
                    child: const Center(
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('Saving...'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
