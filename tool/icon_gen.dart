// Zic launcher-icon generator — rasterizes the brand mark (see
// lib/design/zic_logo.dart for the design grid) into:
//   assets/icon/icon.png    1024 master, full squircle + mark
//   assets/icon/icon_fg.png 1024 adaptive foreground, mark only
//
// Run: dart run tool/icon_gen.dart
// The geometry mirrors ZicLogoGeometry; keep both in sync by hand (this
// tool runs outside Flutter, on package:image only).
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart';

final bg = ColorRgba8(0x13, 0x13, 0x13, 0xFF); // ZCode-family ink squircle
final fg = ColorRgba8(0xFF, 0xFF, 0xFF, 0xFF);

// --- ZicLogoGeometry (grid 120x100) — keep in sync with zic_logo.dart ---
const zPolygon = <List<double>>[
  [0, 10], [62, 10], [62, 29], [28, 71], [62, 71], [62, 90],
  [0, 90], [0, 71], [34, 29], [0, 29],
];
const zSlits = <List<List<double>>>[
  [
    [57, 25],
    [43, 42],
  ],
];
const slitWidth = 3.5;
const iStem = [69.0, 57.0, 9.0, 33.0]; // x,y,w,h
const iDot = [69.0, 40.0, 9.0, 9.0];
const cCenter = [98.0, 69.0];
const cRadius = 16.5;
const cStroke = 8.0;
// Arc from -80° sweeping -200° (160° mouth). Keep in sync with zic_logo.dart.
const cStartAngle = -80 * math.pi / 180;
const cSweep = -200 * math.pi / 180;
const gridW = 128.0, gridH = 100.0;

double _sx(double x, double scale, double ox) => x * scale + ox;
double _sy(double y, double scale, double oy) => y * scale + oy;

void paintMark(Image img, Rect box) {
  final scale = math.min(box.width / gridW, box.height / gridH);
  final ox = box.left + (box.width - gridW * scale) / 2;
  final oy = box.top + (box.height - gridH * scale) / 2;

  // Z polygon (even-odd scanline fill).
  final pts = <Point>[
    for (final p in zPolygon)
      Point(_sx(p[0], scale, ox).round(), _sy(p[1], scale, oy).round()),
  ];
  fillPolygon(img, pts, fg);

  // i stem + dot.
  fillRect(
    img,
    x1: _sx(iStem[0], scale, ox).round(),
    y1: _sy(iStem[1], scale, oy).round(),
    x2: _sx(iStem[0] + iStem[2], scale, ox).round(),
    y2: _sy(iStem[1] + iStem[3], scale, oy).round(),
    color: fg,
  );
  fillRect(
    img,
    x1: _sx(iDot[0], scale, ox).round(),
    y1: _sy(iDot[1], scale, oy).round(),
    x2: _sx(iDot[0] + iDot[2], scale, ox).round(),
    y2: _sy(iDot[1] + iDot[3], scale, oy).round(),
    color: fg,
  );

  // c ring: filled as an annular polygon (outer arc out, inner arc back).
  // Stroked segment chains leave visible seams between drawLine stamps;
  // a single even-odd polygon renders solid.
  final ringPts = <Point>[];
  final outerR = cRadius + cStroke / 2;
  final innerR = cRadius - cStroke / 2;
  const steps = 128;
  for (var i = 0; i <= steps; i++) {
    final t = cStartAngle + cSweep * i / steps;
    ringPts.add(Point(
      _sx(cCenter[0] + outerR * math.cos(t), scale, ox).round(),
      _sy(cCenter[1] + outerR * math.sin(t), scale, oy).round(),
    ));
  }
  for (var i = steps; i >= 0; i--) {
    final t = cStartAngle + cSweep * i / steps;
    ringPts.add(Point(
      _sx(cCenter[0] + innerR * math.cos(t), scale, ox).round(),
      _sy(cCenter[1] + innerR * math.sin(t), scale, oy).round(),
    ));
  }
  fillPolygon(img, ringPts, fg);

  // Junction slits, knocked out in the surface color.
  for (final s in zSlits) {
    drawLine(
      img,
      x1: _sx(s[0][0], scale, ox).round(),
      y1: _sy(s[0][1], scale, oy).round(),
      x2: _sx(s[1][0], scale, ox).round(),
      y2: _sy(s[1][1], scale, oy).round(),
      color: bg,
      thickness: (slitWidth * scale).round().clamp(1, 512),
      antialias: true,
    );
  }
}

/// Even-odd scanline polygon fill (handles the Z's concave notch).
void fillPolygon(Image img, List<Point> pts, Color color) {
  if (pts.length < 3) return;
  var minY = pts.first.y.toInt(), maxY = pts.first.y.toInt();
  for (final p in pts) {
    if (p.y < minY) minY = p.y.toInt();
    if (p.y > maxY) maxY = p.y.toInt();
  }
  final xs = List<double>.filled(pts.length, 0);
  var totalSpans = 0;
  for (var y = minY; y <= maxY; y++) {
    var n = 0;
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      if ((a.y <= y && b.y > y) || (b.y <= y && a.y > y)) {
        xs[n++] = a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y);
      }
    }
    // Sort a COPY and read spans from that copy: sorting `xs.sublist()`
    // alone leaves the source list unsorted, and crossings can arrive in
    // descending order (edge-visit order), silently dropping every span.
    final row = xs.sublist(0, n)..sort();
    for (var k = 0; k + 1 < row.length; k += 2) {
      final x1 = row[k].round();
      final x2 = row[k + 1].round();
      if (x2 >= x1) {
        totalSpans++;
        fillRect(img, x1: x1, y1: y, x2: x2, y2: y, color: color);
      }
    }
  }
  if (totalSpans == 0) {
    // ignore: avoid_print
    print('poly WARNING: 0 spans');
  }
}

void fillSquircle(Image img, int size, Color color) {
  // 22.6% corner radius, iOS-squircle feel.
  final r = (size * 0.226).round();
  fillRect(img, x1: 0, y1: r, x2: size - 1, y2: size - 1 - r, color: color);
  fillRect(img, x1: r, y1: 0, x2: size - 1 - r, y2: size - 1, color: color);
  fillCircle(img, x: r, y: r, radius: r, color: color);
  fillCircle(img, x: size - 1 - r, y: r, radius: r, color: color);
  fillCircle(img, x: r, y: size - 1 - r, radius: r, color: color);
  fillCircle(img, x: size - 1 - r, y: size - 1 - r, radius: r, color: color);
}

void main() {
  final size = 1024;
  Directory('assets/icon').createSync(recursive: true);

  // Full master: squircle + mark at ~64%.
  final master = Image(width: size, height: size, numChannels: 4);
  fillSquircle(master, size, bg);
  paintMark(
      master,
      Rect.fromCenter(
          center: Point(size / 2, size / 2), width: 656, height: 656));
  File('assets/icon/icon.png').writeAsBytesSync(encodePng(master, level: 9));

  // Adaptive foreground: transparent canvas, mark inside the 66% safe
  // zone. Slits paint in #131313 — identical to adaptive_icon_background,
  // so they read as knockouts on the launcher.
  final fgImg = Image(width: size, height: size, numChannels: 4);
  paintMark(
      fgImg,
      Rect.fromCenter(
          center: Point(size / 2, size / 2), width: 600, height: 600));
  File('assets/icon/icon_fg.png').writeAsBytesSync(encodePng(fgImg, level: 9));

  print('icons written: assets/icon/icon.png, assets/icon/icon_fg.png');
}

class Rect {
  final double left, top, width, height;
  Rect.fromCenter({
    required this.center,
    required this.width,
    required this.height,
  })  : left = center.x - width / 2,
        top = center.y - height / 2;
  final Point center;
}
