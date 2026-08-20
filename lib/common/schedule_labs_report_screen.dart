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

      final now = DateTime.now();
      final currentMonthName = DateFormat('MMMM').format(now).toLowerCase();
      final currentMonthInt = now.month;
      final currentYear = now.year;

      List<Map<String, dynamic>> finalData = [];
      for (var s in schedules) {
        final pcid = s['pcid'] as int;
        final patientName = s['patients']['name'] ?? 'Unknown';
        final labInfo = labsByPcid[pcid] ?? {};

        // Bloodwork month check (HB, K, Ca, PO4, URR, KT/V)
        bool isBwThisMonth = false;
        final bwMonth = (labInfo['bw_month'] ?? '').toString().trim().toLowerCase();
        final bwYear = int.tryParse((labInfo['bw_year'] ?? '').toString());
        if (bwMonth == currentMonthName && (bwYear == null || bwYear == currentYear)) {
          isBwThisMonth = true;
        } else if (labInfo['bw_date'] != null) {
          final dt = DateTime.tryParse(labInfo['bw_date'].toString());
          if (dt != null && dt.month == currentMonthInt && dt.year == currentYear) {
            isBwThisMonth = true;
          }
        }

        // PTH month check
        bool isPthThisMonth = false;
        if (labInfo['pth_date'] != null) {
          final dt = DateTime.tryParse(labInfo['pth_date'].toString());
          if (dt != null && dt.month == currentMonthInt && dt.year == currentYear) {
            isPthThisMonth = true;
          }
        }

        // Iron profile month check (TSAT, Ferritin)
        bool isIronThisMonth = false;
        if (labInfo['iron_date'] != null) {
          final dt = DateTime.tryParse(labInfo['iron_date'].toString());
          if (dt != null && dt.month == currentMonthInt && dt.year == currentYear) {
            isIronThisMonth = true;
          }
        }

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
          'is_bw_this_month': isBwThisMonth,
          'is_pth_this_month': isPthThisMonth,
          'is_iron_this_month': isIronThisMonth,
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

  pw.Widget _buildPdfCell(
    String text, {
    required bool isBold,
    pw.Alignment alignment = pw.Alignment.centerLeft,
  }) {
    final hasValue = text.isNotEmpty && text != '-';
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
      alignment: alignment,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9.5,
          fontWeight:
              (isBold && hasValue) ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: (isBold && hasValue) ? PdfColors.black : PdfColors.grey700,
        ),
      ),
    );
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
    final currentMonthLabel =
        DateFormat('MMMM yyyy').format(DateTime.now());

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

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        header: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Schedule Labs Report',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text('Generated: $dateStr'),
              pw.Text(
                'Filter: '
                'Hall: ${widget.hallName ?? 'All'}, '
                'Day: ${widget.day ?? 'All'}, '
                'Shift: ${widget.shift ?? 'All'}',
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                '* Bold values indicate labs recorded in current month ($currentMonthLabel)',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontStyle: pw.FontStyle.italic,
                  color: PdfColors.grey700,
                ),
              ),
              pw.SizedBox(height: 12),
            ],
          );
        },
        build: (pw.Context context) {
          return [
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(1), // ID
                1: const pw.FlexColumnWidth(2.8), // Name
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
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.teal),
                  children: tableHeaders.map((header) {
                    return pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 3,
                      ),
                      alignment: pw.Alignment.centerLeft,
                      child: pw.Text(
                        header,
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                          fontSize: 10,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                ..._reportData.asMap().entries.map((entry) {
                  final index = entry.key;
                  final data = entry.value;
                  final isBwBold = data['is_bw_this_month'] == true;
                  final isPthBold = data['is_pth_this_month'] == true;
                  final isIronBold = data['is_iron_this_month'] == true;
                  final rowBg =
                      index % 2 == 1 ? PdfColors.grey100 : PdfColors.white;

                  return pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: rowBg,
                      border: const pw.Border(
                        bottom: pw.BorderSide(
                          color: PdfColors.grey300,
                          width: 0.5,
                        ),
                      ),
                    ),
                    children: [
                      _buildPdfCell(
                        data['pcid']?.toString() ?? '',
                        isBold: false,
                      ),
                      _buildPdfCell(
                        data['name']?.toString() ?? '',
                        isBold: false,
                      ),
                      _buildPdfCell(
                        data['cbchb']?.toString() ?? '-',
                        isBold: isBwBold,
                      ),
                      _buildPdfCell(
                        data['ue1k']?.toString() ?? '-',
                        isBold: isBwBold,
                      ),
                      _buildPdfCell(
                        data['bca']?.toString() ?? '-',
                        isBold: isBwBold,
                      ),
                      _buildPdfCell(
                        data['bpo4']?.toString() ?? '-',
                        isBold: isBwBold,
                      ),
                      _buildPdfCell(
                        data['effurr']?.toString() ?? '-',
                        isBold: isBwBold,
                      ),
                      _buildPdfCell(
                        data['effktv']?.toString() ?? '-',
                        isBold: isBwBold,
                      ),
                      _buildPdfCell(
                        data['pthresult']?.toString() ?? '-',
                        isBold: isPthBold,
                      ),
                      _buildPdfCell(
                        data['irontsat']?.toString() ?? '-',
                        isBold: isIronBold,
                      ),
                      _buildPdfCell(
                        data['ironferritin']?.toString() ?? '-',
                        isBold: isIronBold,
                      ),
                    ],
                  );
                }),
              ],
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
