import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img_lib;
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:zxing2/qrcode.dart';

import 'theme.dart';
import 'ui_settings.dart';

/// QR scan page: camera scan (mobile_scanner) + decode from a picked image
/// (pure-Dart zxing2, works everywhere). Pops with the scanned URL string.
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  late final MobileScannerController _controller;
  bool _handled = false;
  String? _cameraError;
  bool _decodingImage = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _accept(String? raw) {
    if (_handled || raw == null || raw.trim().isEmpty) return;
    final text = raw.trim();
    _handled = true;
    Navigator.of(context).pop(text);
  }

  Future<void> _pickImage() async {
    if (_decodingImage) return;
    setState(() => _decodingImage = true);
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final text = decodeQrFromImageBytes(bytes);
      if (text != null) {
        _accept(text);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(tr(context, 'devices.scan.decodeFailed'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(trP(context, 'devices.scan.decodeError', ['$e']))),
        );
      }
    } finally {
      if (mounted) setState(() => _decodingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'devices.scan.title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.image_outlined),
            tooltip: tr(context, 'devices.scan.fromGallery'),
            onPressed: _decodingImage ? null : _pickImage,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _cameraError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        trP(context, 'devices.scan.cameraError',
                            [_cameraError!]),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : MobileScanner(
                    controller: _controller,
                    onDetect: (capture) {
                      for (final barcode in capture.barcodes) {
                        _accept(barcode.rawValue);
                        if (_handled) break;
                      }
                    },
                    errorBuilder: (context, error) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && _cameraError == null) {
                          setState(() =>
                              _cameraError = error.errorDetails?.message ??
                                  '${error.errorCode}');
                        }
                      });
                      return Center(
                          child: Text(tr(
                              context, 'devices.scan.cameraInitFailed')));
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              tr(context, 'devices.scan.hint'),
              style: TextStyle(color: ZInk.muted(context), fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// Decodes a QR code from image bytes using the pure-Dart zxing2 reader.
String? decodeQrFromImageBytes(Uint8List bytes) {
  final image = img_lib.decodeImage(bytes);
  if (image == null) return null;
  final width = image.width;
  final height = image.height;
  if (width > 4096 || height > 4096) {
    return null;
  }
  final pixels = Int32List(width * height);
  var i = 0;
  for (final pixel in image) {
    final a = pixel.a.toInt() & 0xFF;
    final r = pixel.r.toInt() & 0xFF;
    final g = pixel.g.toInt() & 0xFF;
    final b = pixel.b.toInt() & 0xFF;
    pixels[i++] = (a << 24) | (r << 16) | (g << 8) | b;
  }
  final source = RGBLuminanceSource(width, height, pixels);
  final bitmap = BinaryBitmap(HybridBinarizer(source));
  try {
    final result = QRCodeReader().decode(bitmap);
    final text = result.text;
    return text.isEmpty ? null : text;
  } catch (_) {
    return null;
  }
}
