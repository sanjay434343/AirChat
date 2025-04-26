import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/device.dart';
import '../services/qr_service.dart';

class QRDisplayDialog extends StatelessWidget {
  final Device device;

  const QRDisplayDialog({Key? key, required this.device}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final qrData = QRService.generateQRData(device);
    final screenSize = MediaQuery.of(context).size;
    final qrSize = screenSize.width * 0.6;

    return Material(
      color: Colors.transparent,
      child: Dialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        child: Container(
          width: screenSize.width * 0.8,
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Scan to Connect',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                  ),
                ),
                padding: const EdgeInsets.all(16),
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: qrSize - 32,
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'IP: ${device.ip}',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
