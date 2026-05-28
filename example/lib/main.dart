import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:widget_utilities/widget_utilities.dart';

void main() => runApp(const AppRoot());

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      supportedLocales: const [Locale('en', 'US'), Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _textScannerController = TextEditingController();
  final TextEditingController _barcodeScannerController =
      TextEditingController();
  final TextEditingController _hybridScannerController =
      TextEditingController();

  @override
  void dispose() {
    _textScannerController.dispose();
    _barcodeScannerController.dispose();
    _hybridScannerController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    await Future.delayed(const Duration(seconds: 2));
  }

  Widget _buildScannerField({
    required TextEditingController controller,
    required String label,
    required String tooltip,
    required IconData icon,
    required ScannerMode mode,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: TextField(
        controller: controller,
        textCapitalization: TextCapitalization.characters,
        contextMenuBuilder: ScannerTextInput.contextMenuBuilder(
          mode: mode,
          onTextScanned: (scannedValue) {
            controller.text = scannedValue;
          },
        ),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: tooltip,
            icon: Icon(icon),
            onPressed: () => ScannerTextInput.open(
              context,
              mode: mode,
              onTextScanned: (scannedValue) {
                controller.text = scannedValue;
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDatePicker(BuildContext context) async {
    final date = await DatePickerUniversal.show(
      context,
      locale: const Locale('pt', 'BR'),
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      addButtonToday: true,
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Selecionado: $date')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('widget_utilities Example')),
      body: RefreshUniversal(
        onRefresh: _onRefresh,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Puxe para atualizar 🚀'),
              const SizedBox(height: 20),
              _buildScannerField(
                controller: _textScannerController,
                label: 'OCR de texto',
                tooltip: 'Escanear texto',
                icon: Icons.document_scanner_outlined,
                mode: ScannerMode.text,
              ),
              const SizedBox(height: 12),
              _buildScannerField(
                controller: _barcodeScannerController,
                label: 'Código de barras / QR',
                tooltip: 'Escanear código',
                icon: Icons.qr_code_scanner_outlined,
                mode: ScannerMode.barcode,
              ),
              const SizedBox(height: 12),
              _buildScannerField(
                controller: _hybridScannerController,
                label: 'Texto ou código',
                tooltip: 'Escanear texto ou código',
                icon: Icons.center_focus_strong_outlined,
                mode: ScannerMode.textAndBarcode,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _showDatePicker(context),
                child: const Text('Abrir DatePickerUniversal'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
