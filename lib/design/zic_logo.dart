import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Zic mark geometry — single source of truth for the brand glyph.
///
/// Wordmark-style "Zic": a bold single-cut Z (the cut echoes ZCode's
/// forward slant) followed by a LARGE lowercase "ic" — 62% of the Z's
/// cap height — so the mark reads "Zic" even at 17px header sizes.
/// Pure geometry, no font dependency; the same coordinates drive this
/// painter and the rasterized launcher icons (tool/icon_gen.dart
/// re-implements the shapes on `package:image`).
///
/// Design grid: 128 × 100. The Z occupies x 0..62, the "ic" x 69..119;
/// the block spans y 10..90.
class ZicLogoGeometry {
  ZicLogoGeometry._();

  /// Z outline, clockwise. Bars are 19 units thick; the diagonal band runs
  /// from the top-right junction down to the bottom-left junction.
  static const zPolygon = <Offset>[
    Offset(0, 10), // top-left
    Offset(62, 10), // top-right
    Offset(62, 29), // top bar bottom-right (before slit)
    Offset(28, 71), // diagonal lower edge, bottom end
    Offset(62, 71), // bottom bar top-right
    Offset(62, 90), // bottom-right
    Offset(0, 90), // bottom-left
    Offset(0, 71), // diagonal upper edge, bottom end
    Offset(34, 29), // top bar bottom edge, diagonal side
    Offset(0, 29), // top bar bottom-left
  ];

  /// ONE thin slit (stroked in the surface color over the Z), parallel to
  /// the diagonal direction (−34, +42), cutting only the top-right
  /// junction. One cut keeps the letterform legible at small sizes —
  /// two cuts fragment it.
  static const zSlits = <(Offset, Offset)>[
    (Offset(57, 25), Offset(43, 42)), // top-right junction
  ];
  static const double slitWidth = 3.5;

  // "ic" — geometric lowercase at 62% of the Z's cap height,
  // baseline-aligned, wordmark-tight after the Z.
  static const iStem = Rect.fromLTWH(69, 57, 9, 33);
  static const iDot = Rect.fromLTWH(69, 40, 9, 9);

  /// The "c" is an open ring; the gap faces right (out of the reading
  /// direction, mirroring the mark's forward slant).
  static const cCenter = Offset(98, 69);
  static const double cRadius = 16.5;
  static const double cStroke = 8;
  /// Start at −80° (upper-right gap edge) and sweep −200°: a 160° mouth.
  /// Header sizes are small; a narrower opening, or a stroke that closes
  /// the arc, reads as a circle instead of a "c".
  static const double cStartAngle = -80 * math.pi / 180;
  static const double cSweep = -200 * math.pi / 180;

  static const gridSize = Size(128, 100);
}

/// Scales grid-space coordinates into a paint box, preserving aspect and
/// centering. Returns (offset, scale).
(Offset, double) zicFitIn(Size box) {
  final scale = math.min(box.width / ZicLogoGeometry.gridSize.width,
      box.height / ZicLogoGeometry.gridSize.height);
  final offset = Offset(
    (box.width - ZicLogoGeometry.gridSize.width * scale) / 2,
    (box.height - ZicLogoGeometry.gridSize.height * scale) / 2,
  );
  return (offset, scale);
}

Offset _p(Offset p, Offset o, double s) => Offset(p.dx * s + o.dx, p.dy * s + o.dy);

Rect _r(Rect r, Offset o, double s) =>
    Rect.fromLTWH(r.left * s + o.dx, r.top * s + o.dy, r.width * s, r.height * s);

/// The glyph (Z + i + c ring) as a fill path — everything except the slits.
Path zicGlyphPath(Offset o, double s) => Path()
  ..addPolygon([for (final p in ZicLogoGeometry.zPolygon) _p(p, o, s)], true)
  ..addRect(_r(ZicLogoGeometry.iStem, o, s))
  ..addRect(_r(ZicLogoGeometry.iDot, o, s));

/// The "c" as a filled open ring. The mouth faces right.
///
/// Do not stroke a closed arc here: [Path.close] draws the chord across
/// the opening, and at header size that chord seals the letter so it
/// reads as a circle instead of a "c".
Path zicRingPath(Offset o, double s) {
  final c = _p(ZicLogoGeometry.cCenter, o, s);
  final outer = (ZicLogoGeometry.cRadius + ZicLogoGeometry.cStroke / 2) * s;
  final inner = (ZicLogoGeometry.cRadius - ZicLogoGeometry.cStroke / 2) * s;
  final start = ZicLogoGeometry.cStartAngle;
  final sweep = ZicLogoGeometry.cSweep;
  final end = start + sweep;
  return Path()
    ..moveTo(c.dx + outer * math.cos(start), c.dy + outer * math.sin(start))
    ..arcTo(Rect.fromCircle(center: c, radius: outer), start, sweep, false)
    ..lineTo(c.dx + inner * math.cos(end), c.dy + inner * math.sin(end))
    ..arcTo(Rect.fromCircle(center: c, radius: inner), end, -sweep, false)
    ..close();
}

/// The slits as a stroked path (stroke width: slitWidth × s).
Path zicSlitsPath(Offset o, double s) {
  final path = Path();
  for (final (a, b) in ZicLogoGeometry.zSlits) {
    path.moveTo(_p(a, o, s).dx, _p(a, o, s).dy);
    path.lineTo(_p(b, o, s).dx, _p(b, o, s).dy);
  }
  return path;
}

/// The brand glyph painter: "Zic" in [color] with the junction slits knocked
/// out in [surfaceColor]. Used on the login header, empty states and about.
class ZicMark extends StatelessWidget {
  final double size;
  final Color color;
  final Color surfaceColor;

  const ZicMark({
    super.key,
    required this.size,
    required this.color,
    required this.surfaceColor,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _ZicMarkPainter(color: color, surfaceColor: surfaceColor),
    );
  }
}

class _ZicMarkPainter extends CustomPainter {
  final Color color;
  final Color surfaceColor;

  const _ZicMarkPainter({required this.color, required this.surfaceColor});

  @override
  void paint(Canvas canvas, Size size) {
    final (o, s) = zicFitIn(size);
    final fill = Paint()..style = PaintingStyle.fill..color = color;
    canvas.drawPath(zicGlyphPath(o, s), fill);
    canvas.drawPath(zicRingPath(o, s), fill);

    final slit = Paint()
      ..color = surfaceColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = ZicLogoGeometry.slitWidth * s
      ..strokeCap = StrokeCap.butt;
    canvas.drawPath(zicSlitsPath(o, s), slit);
  }

  @override
  bool shouldRepaint(covariant _ZicMarkPainter old) =>
      old.color != color || old.surfaceColor != surfaceColor;
}
