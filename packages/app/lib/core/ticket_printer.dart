import 'dart:typed_data';

import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'formatters.dart';

/// Dựng và in phiếu cân.
///
/// Xuất ra PDF khổ A5 ngang — vừa một nửa tờ A4, in hai liên (một cho khách,
/// một lưu kho) mà không tốn giấy. Cùng một mã nguồn chạy được trên web
/// (mở hộp thoại in của trình duyệt), Windows và Android.
abstract final class TicketPrinter {
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

  /// Mở hộp thoại in của hệ điều hành/trình duyệt.
  static Future<void> print(WeighTicket ticket, {String? companyName}) async {
    final document = await build(ticket, companyName: companyName);
    await Printing.layoutPdf(
      onLayout: (_) => document,
      name: 'Phieu-can-${ticket.ticketNo}',
    );
  }

  /// Chia sẻ/lưu file PDF — hữu ích trên điện thoại khi cần gửi phiếu cho khách.
  static Future<void> share(WeighTicket ticket, {String? companyName}) async {
    final document = await build(ticket, companyName: companyName);
    await Printing.sharePdf(bytes: document, filename: 'Phieu-can-${ticket.ticketNo}.pdf');
  }

  static Future<Uint8List> build(WeighTicket ticket, {String? companyName}) async {
    final theme = await _loadTheme();
    final document = pw.Document(theme: theme, title: 'Phiếu cân ${ticket.ticketNo}');

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5.landscape,
        margin: const pw.EdgeInsets.all(20),
        build: (context) => _body(ticket, companyName),
      ),
    );
    return document.save();
  }

  static pw.Widget _body(WeighTicket ticket, String? companyName) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    (companyName ?? '').isEmpty ? 'PHIẾU CÂN XE' : companyName!.toUpperCase(),
                    style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text('Kho: ${ticket.stationCode}', style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('PHIẾU CÂN XE',
                    style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.Text('Số: ${ticket.ticketNo}', style: const pw.TextStyle(fontSize: 10)),
                pw.Text('${ticket.direction.label} • ${formatDateTime(ticket.createdAt)}',
                    style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Divider(thickness: 1),
        pw.SizedBox(height: 6),

        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _field('Khách hàng', ticket.customerName),
                  _field('Biển số xe', ticket.plateNo),
                  _field('Tài xế', ticket.driverName ?? ''),
                ],
              ),
            ),
            pw.SizedBox(width: 16),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _field('Loại hàng', ticket.goodsName),
                  _field('Tỷ lệ thành phẩm', formatPercent(ticket.yieldRatio)),
                  _field('Trạng thái', ticket.status.label),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 10),

        _weighTable(ticket),
        pw.SizedBox(height: 10),

        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(width: 1.2),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: _total('KHỐI LƯỢNG HÀNG', '${formatWeight(ticket.netWeight)} kg', 15),
              ),
              pw.Container(width: 1, height: 26, color: PdfColors.grey400),
              pw.Expanded(
                child: _total(
                    'KL THÀNH PHẨM QUY ĐỔI', '${formatWeight(ticket.productWeight)} kg', 13),
              ),
            ],
          ),
        ),

        if ((ticket.note ?? '').isNotEmpty) ...[
          pw.SizedBox(height: 6),
          pw.Text('Ghi chú: ${ticket.note}', style: const pw.TextStyle(fontSize: 9)),
        ],

        pw.Spacer(),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: [
            _signature('Người cân', ticket.createdBy ?? ''),
            _signature('Tài xế', ticket.driverName ?? ''),
            _signature('Khách hàng', ticket.customerName),
          ],
        ),
      ],
    );
  }

  static pw.Widget _weighTable(WeighTicket ticket) {
    pw.Widget cell(String text, {bool header = false, bool right = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: pw.Text(
            text,
            textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(
              fontSize: header ? 9 : 10.5,
              fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        );

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.6),
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(1.6),
        2: pw.FlexColumnWidth(2.2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            cell('Lần cân', header: true),
            cell('Khối lượng (kg)', header: true, right: true),
            cell('Thời điểm', header: true),
          ],
        ),
        pw.TableRow(children: [
          cell('Cân lần 1'),
          cell(formatWeight(ticket.firstWeight), right: true),
          cell(formatDateTime(ticket.firstWeightAt)),
        ]),
        pw.TableRow(children: [
          cell('Cân lần 2'),
          cell(formatWeight(ticket.secondWeight), right: true),
          cell(formatDateTime(ticket.secondWeightAt)),
        ]),
        pw.TableRow(children: [
          cell('KL tổng / KL bì'),
          cell('${formatWeight(ticket.grossWeight)} / ${formatWeight(ticket.tareWeight)}',
              right: true),
          cell(''),
        ]),
      ],
    );
  }

  static pw.Widget _field(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 82,
              child: pw.Text('$label:', style: const pw.TextStyle(fontSize: 9.5)),
            ),
            pw.Expanded(
              child: pw.Text(
                value.isEmpty ? '.....................' : value,
                style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
              ),
            ),
          ],
        ),
      );

  static pw.Widget _total(String label, String value, double size) => pw.Column(
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
          pw.SizedBox(height: 2),
          pw.Text(value, style: pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold)),
        ],
      );

  static pw.Widget _signature(String role, String name) => pw.Column(
        children: [
          pw.Text(role, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.Text('(ký, ghi rõ họ tên)', style: const pw.TextStyle(fontSize: 7)),
          pw.SizedBox(height: 28),
          pw.Text(name, style: const pw.TextStyle(fontSize: 9)),
        ],
      );
}
