import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class ScheduleLabsReportScreen extends StatefulWidget {
  final String? hallName;
  final String? day;
  final String? shift;

  const ScheduleLabsReportScreen({
    super.key,
    this.hallName,
    this.day,
    this.shift,
  });

  @override
  State<ScheduleLabsReportScreen> createState() =>
      _ScheduleLabsReportScreenState();
}

class _ScheduleLabsReportScreenState extends State<ScheduleLabsReportScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _reportData = [];
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchReportData();
  }

  Future<void> _fetchReportData() async {
    try {
      var query = Supabase.instance.client
          .from('schedules')
          .select('pcid, hallname, day, shift, patients!inner(name, status)');

      if (widget.hallName != null) {
        query = query.eq('hallname', widget.hallName!);
      }
      if (widget.day != null) {
        query = query.eq('day', widget.day!);
      }
      if (widget.shift != null) {
        query = query.eq('shift', widget.shift!);
      }

      final schedules = await query.eq('patients.status', 'Active');

      final pcids = (schedules as List).map((e) => e['pcid'] as int).toList();

      if (pcids.isEmpty) {
        setState(() {
          _reportData = [];
          _isLoading = false;
        });
        return;
      }

      final labsResponse =
          await Supabase.instance.client.rpc('get_all_latest_labs');
      final labsList = List<Map<String, dynamic>>.from(labsResponse);

      final Map<int, Map<String, dynamic>> labsByPcid = {};
      for (var lab in labsList) {
        labsByPcid[lab['pcid'] as int] = lab;
      }

      List<Map<String, dynamic>> finalData = [];
      for (var s in schedules) {
        final pcid = s['pcid'] as int;
        final patientName = s['patients']['name'] ?? 'Unknown';
        final labInfo = labsByPcid[pcid] ?? {};

        finalData.add({
          'pcid': pcid,
          'name': patientName,
          'cbchb': labInfo['cbchb'],
          'ue1k': labInfo['ue1k'],
          'bca': labInfo['bca'],
          'bpo4': labInfo['bpo4'],
          'effktv': labInfo['effktv'],
          'effurr': labInfo['effurr'],
          'pthresult': labInfo['pthresult'],
          'irontsat': labInfo['irontsat'],
          'ironferritin': labInfo['ironferritin'],
        });
      }

      // Sort by name since we don't have schedule columns anymore
      finalData.sort((a, b) {
        return (a['name'] ?? '').compareTo(b['name'] ?? '');
      });

      setState(() {
        _reportData = finalData;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<Uint8List> _generatePdf(PdfPageFormat format) async {
    final font = await PdfGoogleFonts.cairoRegular();
    final fontBold = await PdfGoogleFonts.cairoBold();
    
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: font,
        bold: fontBold,
      ),
    );

    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    // Create chunks of data for pagination if necessary
    // pw.Table can handle some automatic pagination, but it's good to keep it simple.
    
    // Convert data to table rows
    final tableHeaders = [
      'ID',
      'Name',
      'HB',
      'K',
      'Ca',
      'PO4',
      'URR',
      'KT/V',
      'PTH',
      'TSAT',
      'Ferritin'
    ];

    final tableData = _reportData.map((data) {
      return [
        data['pcid'].toString(),
        data['name'].toString(),
        data['cbchb']?.toString() ?? '-',
        data['ue1k']?.toString() ?? '-',
        data['bca']?.toString() ?? '-',
        data['bpo4']?.toString() ?? '-',
        data['effurr']?.toString() ?? '-',
        data['effktv']?.toString() ?? '-',
        data['pthresult']?.toString() ?? '-',
        data['irontsat']?.toString() ?? '-',
        data['ironferritin']?.toString() ?? '-',
      ];
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        header: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Schedule Labs Report',
                  style: pw.TextStyle(
                      fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Text('Generated: $dateStr'),
              pw.Text('Filter: '
                  'Hall: ${widget.hallName ?? 'All'}, '
                  'Day: ${widget.day ?? 'All'}, '
                  'Shift: ${widget.shift ?? 'All'}'),
              pw.SizedBox(height: 16),
            ],
          );
        },
        build: (pw.Context context) {
          return [
            pw.TableHelper.fromTextArray(
              headers: tableHeaders,
              data: tableData,
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.teal,
              ),
              cellAlignment: pw.Alignment.centerLeft,
              cellStyle: const pw.TextStyle(fontSize: 10),
              rowDecoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                ),
              ),
              oddRowDecoration: const pw.BoxDecoration(
                color: PdfColors.grey100,
              ),
              columnWidths: {
                0: const pw.FlexColumnWidth(1), // ID
                1: const pw.FlexColumnWidth(3), // Name
                2: const pw.FlexColumnWidth(1), // HB
                3: const pw.FlexColumnWidth(1), // K
                4: const pw.FlexColumnWidth(1), // Ca
                5: const pw.FlexColumnWidth(1), // PO4
                6: const pw.FlexColumnWidth(1), // URR
                7: const pw.FlexColumnWidth(1), // KT/V
                8: const pw.FlexColumnWidth(1), // PTH
                9: const pw.FlexColumnWidth(1), // TSAT
                10: const pw.FlexColumnWidth(1.2), // Ferritin
              },
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule Labs Report'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.red)))
              : _reportData.isEmpty
                  ? const Center(child: Text('No patients found for this schedule filter.'))
                  : PdfPreview(
                      build: (format) => _generatePdf(format),
                      allowPrinting: true,
                      allowSharing: true,
                      canChangeOrientation: false,
                      canChangePageFormat: false,
                    ),
    );
  }
}
