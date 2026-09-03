import 'dart:typed_data';

import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'formatters.dart';

/// Dựng và in bảng lương.
///
/// Khổ A4 dọc: bảng nhiều cột nhưng chủ yếu là số, đứng dọc vẫn vừa và xếp
/// được nhiều người trên một trang. Bảng lương là thứ đưa cho người ta xem rồi
/// ký nhận, nên phải in được ra giấy chứ không chỉ xem trên màn hình.
abstract final class PayrollPrinter {
  static pw.ThemeData? _theme;

  /// Nạp font Roboto một lần rồi dùng lại: font mặc định của thư viện PDF
  /// không có dấu tiếng Việt, in ra sẽ mất dấu hết.
  static Future<pw.ThemeData> _loadTheme() async {
    final cached = _theme;
    if (cached != null) return cached;
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    final theme = pw.ThemeData.withFont(base: regular, bold: bold);
    _theme = theme;
    return theme;
  }

  // ------------------------------------------------------- bảng lương tháng

  static Future<void> printMonth(MonthReport report, {String? companyName}) async {
    final document = await buildMonth(report, companyName: companyName);
    await Printing.layoutPdf(
      onLayout: (_) => document,
      name: 'Bang-luong-${report.monthKey}',
    );
  }

  static Future<void> shareMonth(MonthReport report, {String? companyName}) async {
    final document = await buildMonth(report, companyName: companyName);
    await Printing.sharePdf(
      bytes: document,
      filename: 'Bang-luong-${report.monthKey}.pdf',
    );
  }

  static Future<Uint8List> buildMonth(MonthReport report,
      {String? companyName}) async {
    final theme = await _loadTheme();
    final document = pw.Document(
      theme: theme,
      title: 'Bảng lương ${report.month}/${report.year}',
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (context) => _header(
          companyName: companyName,
          title: 'BẢNG LƯƠNG THÁNG ${report.month}/${report.year}',
          subtitle: 'Đoàn: ${report.crewName}',
          page: context.pageNumber,
        ),
        footer: _footer,
        build: (context) => [
          _monthTable(report),
          pw.SizedBox(height: 14),
          if (report.byStation.isNotEmpty) _stationBox(report.byStation),
          pw.SizedBox(height: 18),
          _signatures(),
        ],
      ),
    );
    return document.save();
  }

  static pw.Widget _monthTable(MonthReport report) {
    final headers = [
      'TT',
      'Họ tên',
      'Kho',
      'Công',
      'Lương',
      'Tăng ca',
      'Phụ cấp',
      'Trừ',
      'Thu nhập',
      'Đã ứng',
      'Còn lại',
    ];

    return pw.TableHelper.fromTextArray(
      headers: headers,
      headerStyle: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellStyle: const pw.TextStyle(fontSize: 7.5),
      cellHeight: 16,
      headerAlignment: pw.Alignment.center,
      // Tên căn trái, mọi cột số căn phải — đọc cột số căn giữa rất khó soát.
      cellAlignments: {
        0: pw.Alignment.center,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.center,
        for (var i = 3; i <= 10; i++) i: pw.Alignment.centerRight,
      },
      columnWidths: {
        0: const pw.FixedColumnWidth(18),
        1: const pw.FlexColumnWidth(2.6),
        2: const pw.FixedColumnWidth(34),
      },
      data: [
        for (var i = 0; i < report.rows.length; i++)
          _monthRow(i + 1, report.rows[i]),
        [
          '',
          'TỔNG',
          '',
          formatDecimal(report.totalWorkUnits),
          formatMoney(report.totalWage),
          formatMoney(report.totalOvertime),
          formatMoney(report.totalAllowance),
          formatMoney(report.totalDeduction),
          formatMoney(report.totalIncome),
          formatMoney(report.totalAdvanced),
          formatMoney(report.totalRemaining),
        ],
      ],
    );
  }

  static List<String> _monthRow(int index, MonthReportRow row) => [
        '$index',
        row.name,
        row.stationCode ?? '—',
        formatDecimal(row.month.workUnits),
        formatMoney(row.month.wageEarned),
        formatMoney(row.month.overtime),
        formatMoney(row.month.allowance),
        formatMoney(row.month.deduction),
        formatMoney(row.month.income),
        formatMoney(row.month.advanced),
        formatMoney(row.remaining),
      ];

  // ---------------------------------------------------------- báo cáo mùa

  static Future<void> printSeason(SeasonReport report, {String? companyName}) async {
    final document = await buildSeason(report, companyName: companyName);
    await Printing.layoutPdf(
      onLayout: (_) => document,
      name: 'Quyet-toan-${report.crewName}',
    );
  }

  static Future<void> shareSeason(SeasonReport report, {String? companyName}) async {
    final document = await buildSeason(report, companyName: companyName);
    await Printing.sharePdf(
      bytes: document,
      filename: 'Quyet-toan-${report.crewName}.pdf',
    );
  }

  static Future<Uint8List> buildSeason(SeasonReport report,
      {String? companyName}) async {
    final theme = await _loadTheme();
    final document = pw.Document(theme: theme, title: 'Quyết toán ${report.crewName}');

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (context) => _header(
          companyName: companyName,
          title: 'BẢNG QUYẾT TOÁN CUỐI MÙA',
          subtitle: [
            'Đoàn: ${report.crewName}',
            if (report.season.isNotEmpty) 'Niên vụ: ${report.season}',
            if (report.months.isNotEmpty)
              'Từ ${report.months.first} đến ${report.months.last}',
          ].join('   •   '),
          page: context.pageNumber,
        ),
        footer: _footer,
        build: (context) => [
          _seasonTable(report),
          pw.SizedBox(height: 14),
          if (report.byStation.isNotEmpty) _stationBox(report.byStation),
          if (report.negativeCount > 0) ...[
            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.7)),
              child: pw.Text(
                'Lưu ý: ${report.negativeCount} người đã nhận nhiều hơn công đã làm '
                '(số dư âm) — phần này phải thu lại, không phải trả thêm.',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
          ],
          pw.SizedBox(height: 18),
          _signatures(),
        ],
      ),
    );
    return document.save();
  }

  static pw.Widget _seasonTable(SeasonReport report) => pw.TableHelper.fromTextArray(
        headers: const [
          'TT',
          'Họ tên',
          'Kho',
          'Công',
          'Lương',
          'Tăng ca',
          'Phụ cấp',
          'Trừ',
          'Thu nhập',
          'Đã ứng',
          'Đã trả',
          'Còn lại',
        ],
        headerStyle: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
        cellStyle: const pw.TextStyle(fontSize: 7.5),
        cellHeight: 16,
        headerAlignment: pw.Alignment.center,
        cellAlignments: {
          0: pw.Alignment.center,
          1: pw.Alignment.centerLeft,
          2: pw.Alignment.center,
          for (var i = 3; i <= 11; i++) i: pw.Alignment.centerRight,
        },
        columnWidths: {
          0: const pw.FixedColumnWidth(18),
          1: const pw.FlexColumnWidth(2.4),
          2: const pw.FixedColumnWidth(32),
        },
        data: [
          for (var i = 0; i < report.rows.length; i++)
            _seasonRow(i + 1, report.rows[i]),
          [
            '',
            'TỔNG',
            '',
            formatDecimal(report.totalWorkUnits),
            '',
            '',
            '',
            '',
            formatMoney(report.totalEarned),
            formatMoney(report.totalAdvanced),
            formatMoney(report.totalPaid),
            formatMoney(report.totalBalance),
          ],
        ],
      );

  static List<String> _seasonRow(int index, SeasonReportRow row) => [
        '$index',
        row.name,
        row.stationCode ?? '—',
        formatDecimal(row.workUnits),
        formatMoney(row.wageEarned),
        formatMoney(row.overtime),
        formatMoney(row.allowance),
        formatMoney(row.deduction),
        formatMoney(row.balance.totalEarned),
        formatMoney(row.balance.totalAdvanced),
        formatMoney(row.balance.totalPaid),
        formatMoney(row.balance.balance),
      ];

  // ------------------------------------------------------------ phần chung

  static pw.Widget _header({
    required String? companyName,
    required String title,
    required String subtitle,
    required int page,
  }) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          if (page == 1) ...[
            if (companyName != null && companyName.isNotEmpty)
              pw.Text(companyName.toUpperCase(),
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(title,
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 2),
            pw.Center(child: pw.Text(subtitle, style: const pw.TextStyle(fontSize: 9))),
            pw.SizedBox(height: 10),
          ] else ...[
            pw.Text('$title (tiếp)',
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
          ],
        ],
      );

  static pw.Widget _footer(pw.Context context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('In lúc ${formatDateTime(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
          pw.Text('Trang ${context.pageNumber}/${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
        ],
      );

  /// Tiền công mà từng kho phải gánh.
  ///
  /// Mỗi ngày chấm công đã ghi kho tại thời điểm đó, nên người chuyển kho giữa
  /// mùa vẫn chia được — đây là con số để hai kho đối chiếu với nhau.
  static pw.Widget _stationBox(Map<String, double> byStation) {
    final keys = byStation.keys.toList()..sort();
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.7)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Tiền công theo kho',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          for (final kho in keys)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Row(
                children: [
                  pw.Expanded(
                      child: pw.Text(kho, style: const pw.TextStyle(fontSize: 8.5))),
                  pw.Text('${formatMoney(byStation[kho])} đ',
                      style: pw.TextStyle(
                          fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static pw.Widget _signatures() => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          for (final vai in ['Người lập bảng', 'Kế toán', 'Chủ đoàn'])
            pw.Column(
              children: [
                pw.Text(vai, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 34),
                pw.Text('.........................',
                    style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
        ],
      );
}
