import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _lido = false;

  void _onDetect(BarcodeCapture capture) {
    if (_lido) return;
    final valor = capture.barcodes.isNotEmpty
        ? capture.barcodes.first.rawValue
        : null;
    if (valor == null || valor.isEmpty) return;
    _lido = true;
    Navigator.of(context).pop(valor);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear QR do ramal')),
      body: MobileScanner(onDetect: _onDetect),
    );
  }
}
