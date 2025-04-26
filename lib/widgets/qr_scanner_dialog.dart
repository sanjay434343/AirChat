import 'package:airchat/models/profile.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/qr_service.dart';
import '../models/device.dart';

class QRScannerDialog extends StatelessWidget {
  final Function(Device) onDeviceScanned;
  final Profile myProfile;

  const QRScannerDialog({
    Key? key, 
    required this.onDeviceScanned,
    required this.myProfile,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.85,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Scan QR Code',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              ),
              Container(
                height: 300,
                margin: EdgeInsets.all(16),
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                  ),
                ),
                child: Stack(
                  children: [
                    MobileScanner(
                      controller: MobileScannerController(
                        detectionSpeed: DetectionSpeed.normal,
                        facing: CameraFacing.back,
                        torchEnabled: false,
                      ),
                      onDetect: (capture) {
                        final List<Barcode> barcodes = capture.barcodes;
                        for (final barcode in barcodes) {
                          final device = QRService.parseQRData(barcode.rawValue ?? '');
                          if (device != null && device.profile.name != myProfile.name) {
                            Navigator.pop(context);
                            onDeviceScanned(device);
                            break;
                          }
                        }
                      },
                    ),
                    Center(
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: Text(
                  'Align QR code within the frame',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.secondary,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
