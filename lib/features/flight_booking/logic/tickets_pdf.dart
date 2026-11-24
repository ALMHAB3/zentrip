import 'dart:typed_data';

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/flight_model.dart';
import 'flight_checkout_passenger.dart';

/// One ticket inside the PDF.
class TicketPdfEntry {
  final String passengerName;
  final String typeLabel;
  final String seat;
  final String code;

  const TicketPdfEntry({
    required this.passengerName,
    required this.typeLabel,
    required this.seat,
    required this.code,
  });
}

/// Labels for the PDF (English/Arabic come from the calling screen).
class TicketPdfLabels {
  final String title;
  final String passenger;
  final String seat;
  final String seatClass;
  final String flight;
  final String date;
  final String departure;
  final String arrival;
  final String duration;
  final String reference;
  final String total;

  /// "Ticket" / "التذكرة"; printed before "1/3".
  final String ticket;

  const TicketPdfLabels({
    required this.title,
    required this.passenger,
    required this.seat,
    required this.seatClass,
    required this.flight,
    required this.date,
    required this.departure,
    required this.arrival,
    required this.duration,
    required this.reference,
    required this.total,
    required this.ticket,
  });
}

// Ticket colours come from the app palette (AppColors).
final _navy = PdfColor.fromInt(AppColors.primary.toARGB32());
final _ink = PdfColor.fromInt(AppColors.textPrimary.toARGB32());
final _muted = PdfColor.fromInt(AppColors.textSecondary.toARGB32());
final _line = PdfColor.fromInt(AppColors.border.toARGB32());

/// Fonts are bundled in assets/fonts/pdf (Noto Sans + Noto Sans Arabic) so
/// Arabic names print correctly without internet. If the assets are missing
/// (e.g. in plain Dart tests) it falls back to Google Fonts, then the
/// built-in font.
class _PdfFonts {
  final pw.Font latin, latinBold, arabic, arabicBold;
  const _PdfFonts(this.latin, this.latinBold, this.arabic, this.arabicBold);
}

/// Fonts are bundled in assets/fonts/pdf (Noto Sans + Noto Sans Arabic) so
/// Arabic names print correctly without internet. If the assets are missing
/// it falls back to Google Fonts, then to the built-in font (no Arabic).
Future<_PdfFonts?> _loadFonts() async {
  Future<pw.Font> asset(String name) async =>
      pw.Font.ttf(await rootBundle.load('assets/fonts/pdf/$name.ttf'));
  try {
    return _PdfFonts(
      await asset('NotoSans-Regular'),
      await asset('NotoSans-Bold'),
      await asset('NotoSansArabic-Regular'),
      await asset('NotoSansArabic-Bold'),
    );
  } catch (_) {}
  try {
    return _PdfFonts(
      await PdfGoogleFonts.notoSansRegular(),
      await PdfGoogleFonts.notoSansBold(),
      await PdfGoogleFonts.notoSansArabicRegular(),
      await PdfGoogleFonts.notoSansArabicBold(),
    );
  } catch (_) {
    return null;
  }
}

_PdfFonts? _fonts;

final _arabicChars =
    RegExp(r'[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]');

/// Text whose direction follows its content: Arabic right-to-left, codes,
/// times and Latin names left-to-right (they would print reversed in RTL).
pw.Widget _text(String data, {pw.TextStyle? style}) {
  final arabic = _arabicChars.hasMatch(data);
  final fonts = _fonts;
  // Arabic is shaped correctly only when an Arabic font is the primary font.
  final fontStyle = arabic && fonts != null
      ? pw.TextStyle(
          font: fonts.arabic,
          fontBold: fonts.arabicBold,
          fontFallback: [fonts.latin, fonts.latinBold],
        )
      : null;
  return pw.Builder(
    builder: (context) => pw.Text(
      data,
      style: fontStyle == null ? style : fontStyle.merge(style),
      textDirection: arabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      // Line up with the page (right side on Arabic tickets).
      textAlign: pw.Directionality.of(context) == pw.TextDirection.rtl
          ? pw.TextAlign.right
          : pw.TextAlign.left,
    ),
  );
}

/// Builds one PDF with a page per traveler and the booking total on every
/// page footer (so each printed page is complete on its own).
Future<Uint8List> buildTicketsPdf({
  required FlightModel flight,
  required String reference,
  required String seatClassLabel,
  required String totalText,
  required List<TicketPdfEntry> tickets,
  required TicketPdfLabels labels,
  required bool rtl,
  String locale = 'en',
}) async {
  await initializeDateFormatting(locale);
  final fonts = _fonts = await _loadFonts();
  final theme = fonts == null
      ? pw.ThemeData.base()
      : pw.ThemeData.withFont(
          base: fonts.latin,
          bold: fonts.latinBold,
          fontFallback: [fonts.arabic, fonts.arabicBold],
        );
  final doc = pw.Document(
    title: '${labels.title} $reference',
    author: 'Zentrip',
    theme: theme,
  );
  final dateText = DateFormat.yMMMEd(locale).format(flight.departureTime);
  String clock(DateTime t) => DateFormat.Hm(locale).format(t);
  final duration =
      '${flight.durationMinutes ~/ 60}h ${flight.durationMinutes % 60}m';

  for (var i = 0; i < tickets.length; i++) {
    final ticket = tickets[i];
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(28),
        textDirection: rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: pw.BoxDecoration(
                color: _navy,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(12)),
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: _text(
                      flight.airline,
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  // Word and number are separate pieces: the PDF engine
                  // drops the space between Arabic text and digits.
                  _text(
                    labels.ticket,
                    style: const pw.TextStyle(
                        color: PdfColors.white, fontSize: 10),
                  ),
                  pw.SizedBox(width: 4),
                  _text(
                    '${i + 1}/${tickets.length}',
                    style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 18),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _airport(flight.originCode, flight.originCity,
                    clock(flight.departureTime)),
                pw.Column(children: [
                  _text(duration,
                      style: pw.TextStyle(color: _muted, fontSize: 9)),
                  _text(rtl ? '<-' : '->',
                      style: pw.TextStyle(
                          color: _navy,
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold)),
                ]),
                _airport(flight.destinationCode, flight.destinationCity,
                    clock(flight.arrivalTime),
                    end: true),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Divider(color: _line),
            pw.SizedBox(height: 8),
            _row(labels.passenger, ticket.passengerName, labels.seat,
                ticket.seat),
            _row('', ticket.typeLabel, labels.seatClass, seatClassLabel),
            _row(labels.flight, flight.flightNumber, labels.date, dateText),
            _row(labels.departure, clock(flight.departureTime), labels.arrival,
                clock(flight.arrivalTime)),
            pw.SizedBox(height: 10),
            pw.Divider(color: _line, borderStyle: pw.BorderStyle.dashed),
            pw.SizedBox(height: 10),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _text(labels.reference,
                          style: pw.TextStyle(color: _muted, fontSize: 9)),
                      _text(reference,
                          style: pw.TextStyle(
                              color: _ink,
                              fontSize: 16,
                              fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 4),
                      _text(ticket.code,
                          style: pw.TextStyle(color: _muted, fontSize: 9)),
                    ],
                  ),
                ),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: ticket.code,
                  width: 78,
                  height: 78,
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.BarcodeWidget(
              barcode: pw.Barcode.code128(),
              data: ticket.code,
              height: 42,
              drawText: false,
            ),
            pw.Spacer(),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _line),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: _text(labels.total,
                        style: pw.TextStyle(color: _muted, fontSize: 9)),
                  ),
                  _text(totalText,
                      style: pw.TextStyle(
                          color: _navy,
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  return doc.save();
}

pw.Widget _airport(String code, String city, String time, {bool end = false}) =>
    pw.Column(
      crossAxisAlignment:
          end ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
      children: [
        _text(code,
            style: pw.TextStyle(
                color: _ink, fontSize: 26, fontWeight: pw.FontWeight.bold)),
        _text(city, style: pw.TextStyle(color: _muted, fontSize: 9)),
        _text(time,
            style: pw.TextStyle(
                color: _ink, fontSize: 12, fontWeight: pw.FontWeight.bold)),
      ],
    );

pw.Widget _row(String l1, String v1, String l2, String v2) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: _cell(l1, v1)),
          pw.SizedBox(width: 10),
          pw.Expanded(child: _cell(l2, v2, end: true)),
        ],
      ),
    );

pw.Widget _cell(String label, String value, {bool end = false}) => pw.Column(
      crossAxisAlignment:
          end ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty)
          _text(label.toUpperCase(),
              style: pw.TextStyle(color: _muted, fontSize: 8)),
        _text(value.isEmpty ? '-' : value,
            style: pw.TextStyle(
                color: _ink, fontSize: 11, fontWeight: pw.FontWeight.bold)),
      ],
    );

/// Saves/shares the PDF: download on web, share sheet (Files, WhatsApp…)
/// on phones.
Future<void> shareTicketsPdf(Uint8List bytes, String reference) =>
    Printing.sharePdf(bytes: bytes, filename: 'zentrip-tickets-$reference.pdf');

/// Ticket entries from the travelers (one per person, own code).
List<TicketPdfEntry> ticketEntries({
  required String reference,
  required List<FlightCheckoutPassenger> travelers,
  required List<String> fallbackSeats,
  required String Function(FlightTravelerType) typeLabel,
  required String onLap,
  String? fallbackName,
}) {
  if (travelers.length <= 1) {
    final traveler = travelers.isEmpty ? null : travelers.first;
    return [
      TicketPdfEntry(
        passengerName: traveler?.name.isNotEmpty == true
            ? traveler!.name
            : (fallbackName ?? ''),
        typeLabel: typeLabel(traveler?.type ?? FlightTravelerType.adult),
        seat: traveler?.seat ??
            (fallbackSeats.isEmpty ? '-' : fallbackSeats.join(', ')),
        code: reference,
      ),
    ];
  }
  return [
    for (var i = 0; i < travelers.length; i++)
      TicketPdfEntry(
        passengerName: travelers[i].name,
        typeLabel: typeLabel(travelers[i].type),
        seat: travelers[i].seat ??
            (travelers[i].type == FlightTravelerType.infant ? onLap : '-'),
        code: '$reference-${i + 1}',
      ),
  ];
}
