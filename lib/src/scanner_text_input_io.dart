import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Define o que o scanner deve reconhecer.
///
/// - [text]: apenas OCR de texto (comportamento padrão e legado).
/// - [barcode]: apenas códigos de barra 1D/2D e QR Code.
/// - [textAndBarcode]: ambos no mesmo painel; códigos de barra/QR têm
///   prioridade quando aparecem em paralelo com texto, por serem mais
///   determinísticos.
///
/// Quando vários códigos estão simultaneamente no enquadramento, o ML Kit
/// não garante uma ordem específica de retorno. Para evitar leituras
/// ambíguas, prefira mirar em um código por vez.
enum ScannerMode { text, barcode, textAndBarcode }

/// Utilitário para integrar leitura por câmera em qualquer
/// [TextField]/[TextFormField] via `contextMenuBuilder`.
///
/// O long press exibe a opção configurada, por padrão "Scannear etiqueta".
/// Ao tocar, abre um modal inferior com a câmera e entrega o texto/código
/// reconhecido em [onTextScanned]. Suporta OCR de texto e/ou leitura de
/// códigos de barra/QR Code conforme [ScannerMode]. A câmera é suportada em
/// Android e iOS.
class ScannerTextInput {
  ScannerTextInput._();

  static const String _defaultMenuLabel = 'Scannear etiqueta';
  static const String _unsupportedPlatformMessage =
      'ScannerTextInput é suportado apenas no Android e iOS.';
  static const double _modalHeightFraction = 0.45;

  /// Retorna um [EditableTextContextMenuBuilder] que insere a opção de scanner
  /// no menu de contexto do campo de texto.
  ///
  /// O parâmetro [mode] controla o que será reconhecido. Por padrão lê apenas
  /// texto (`ScannerMode.text`), mantendo compatibilidade com versões
  /// anteriores. Para ler códigos de barra/QR Code use `ScannerMode.barcode`
  /// ou `ScannerMode.textAndBarcode`.
  ///
  /// Quando [autoConfirmBarcode] é `true` (padrão), a leitura de um código
  /// de barras/QR fecha o modal automaticamente e entrega o valor — útil em
  /// fluxos de digitalização rápida. Para texto, o usuário sempre confirma
  /// tocando em "Inserir".
  ///
  /// Exemplo:
  ///
  /// ```dart
  /// TextField(
  ///   contextMenuBuilder: ScannerTextInput.contextMenuBuilder(
  ///     mode: ScannerMode.textAndBarcode,
  ///     onTextScanned: (text) => controller.text = text,
  ///   ),
  /// )
  /// ```
  static EditableTextContextMenuBuilder contextMenuBuilder({
    required ValueChanged<String> onTextScanned,
    String menuLabel = _defaultMenuLabel,
    ScannerMode mode = ScannerMode.text,
    bool autoConfirmBarcode = true,
  }) {
    return (menuContext, editableTextState) {
      final contextMenuItems = List<ContextMenuButtonItem>.from(
        editableTextState.contextMenuButtonItems,
      );
      contextMenuItems.insert(
        0,
        ContextMenuButtonItem(
          onPressed: () {
            ContextMenuController.removeAny();
            open(
              menuContext,
              onTextScanned: onTextScanned,
              mode: mode,
              autoConfirmBarcode: autoConfirmBarcode,
            );
          },
          label: menuLabel,
        ),
      );
      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: editableTextState.contextMenuAnchors,
        buttonItems: contextMenuItems,
      );
    };
  }

  /// Abre o painel da câmera diretamente, sem depender do menu de contexto.
  ///
  /// Útil para acionar o scanner via botão custom ou ícone do [TextField].
  /// Veja [contextMenuBuilder] para o significado de [mode] e
  /// [autoConfirmBarcode].
  static Future<void> open(
    BuildContext context, {
    required ValueChanged<String> onTextScanned,
    ScannerMode mode = ScannerMode.text,
    bool autoConfirmBarcode = true,
  }) async {
    FocusScope.of(context).unfocus();

    if (!Platform.isAndroid && !Platform.isIOS) {
      _showUnsupportedPlatformMessage(context);
      return;
    }

    final scannedText = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withAlpha(64),
      builder: (modalContext) {
        final modalHeight =
            MediaQuery.of(modalContext).size.height * _modalHeightFraction;
        return SizedBox(
          height: modalHeight,
          child: _ScannerPanel(
            mode: mode,
            autoConfirmBarcode: autoConfirmBarcode,
            onClose: () => Navigator.of(modalContext).pop(),
            onInsert: (recognizedText) =>
                Navigator.of(modalContext).pop(recognizedText),
          ),
        );
      },
    );

    if (scannedText != null) {
      onTextScanned(scannedText);
    }
  }

  static void _showUnsupportedPlatformMessage(BuildContext context) {
    final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
    if (scaffoldMessenger == null) return;

    scaffoldMessenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text(_unsupportedPlatformMessage)),
      );
  }
}

class _ScannerPanel extends StatefulWidget {
  const _ScannerPanel({
    required this.mode,
    required this.autoConfirmBarcode,
    required this.onClose,
    required this.onInsert,
  });

  final ScannerMode mode;
  final bool autoConfirmBarcode;
  final VoidCallback onClose;
  final ValueChanged<String> onInsert;

  @override
  State<_ScannerPanel> createState() => _ScannerPanelState();
}

class _ScannerPanelState extends State<_ScannerPanel>
    with WidgetsBindingObserver {
  static const Map<DeviceOrientation, int> _deviceOrientationDegrees = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  CameraController? _cameraController;
  CameraDescription? _activeCamera;
  bool _isInitializing = true;
  String? _initializationError;
  late final _ScannerViewModel _viewModel;
  bool _hasAutoConfirmed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _viewModel = _ScannerViewModel(
      recognitionServices: _buildRecognitionServices(widget.mode),
    );
    _viewModel.addListener(_handleViewModelChanged);
    unawaited(_initializeCameraController());
  }

  List<_FrameRecognitionService> _buildRecognitionServices(ScannerMode mode) {
    switch (mode) {
      case ScannerMode.text:
        return [_MlKitTextRecognitionService()];
      case ScannerMode.barcode:
        return [_MlKitBarcodeRecognitionService()];
      case ScannerMode.textAndBarcode:
        return [
          _MlKitBarcodeRecognitionService(),
          _MlKitTextRecognitionService(),
        ];
    }
  }

  void _handleViewModelChanged() {
    if (!mounted || _hasAutoConfirmed) return;
    if (!widget.autoConfirmBarcode) return;
    final latestResult = _viewModel.latestResult;
    if (latestResult == null || !latestResult.isBarcode) return;
    final trimmedValue = latestResult.value.trim();
    if (trimmedValue.isEmpty) return;
    _hasAutoConfirmed = true;
    widget.onInsert(trimmedValue);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.resumed) {
      unawaited(_startImageStreamSafely(controller));
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_stopImageStreamSafely(controller));
    }
  }

  Future<void> _initializeCameraController() async {
    try {
      final availableCamerasList = await availableCameras();
      if (availableCamerasList.isEmpty) {
        if (!mounted) return;
        setState(() {
          _isInitializing = false;
          _initializationError = 'Nenhuma câmera disponível neste dispositivo.';
        });
        return;
      }

      final backCamera = availableCamerasList.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => availableCamerasList.first,
      );

      final controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      _cameraController = controller;
      _activeCamera = backCamera;
      setState(() => _isInitializing = false);
      await _startImageStreamSafely(controller);
    } on CameraException catch (cameraException) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _initializationError = _humanizeCameraError(cameraException);
      });
    }
  }

  String _humanizeCameraError(CameraException cameraException) {
    final errorCode = cameraException.code;
    if (errorCode == 'CameraAccessDenied' ||
        errorCode == 'CameraAccessDeniedWithoutPrompt' ||
        errorCode == 'CameraAccessRestricted') {
      return 'Permissão de câmera negada. Habilite o acesso nas configurações do aparelho.';
    }
    return 'Não foi possível inicializar a câmera. Tente novamente.';
  }

  Future<void> _startImageStreamSafely(CameraController controller) async {
    if (controller.value.isStreamingImages) return;
    try {
      await controller.startImageStream(_handleCameraImage);
    } on CameraException {
      // Falhas transitórias de lifecycle serão resolvidas no próximo resume.
    }
  }

  Future<void> _stopImageStreamSafely(CameraController controller) async {
    if (!controller.value.isStreamingImages) return;
    try {
      await controller.stopImageStream();
    } on CameraException {
      // Falhas transitórias de lifecycle não devem derrubar o scanner.
    }
  }

  void _handleCameraImage(CameraImage cameraImage) {
    final activeCamera = _activeCamera;
    if (activeCamera == null) return;

    final inputImage = _buildInputImageFromCameraImage(
      cameraImage,
      activeCamera,
    );
    if (inputImage == null) return;
    unawaited(_viewModel.processFrame(inputImage));
  }

  InputImage? _buildInputImageFromCameraImage(
    CameraImage cameraImage,
    CameraDescription camera,
  ) {
    final controller = _cameraController;
    if (controller == null) return null;

    InputImageRotation? imageRotation;
    if (Platform.isIOS) {
      imageRotation = InputImageRotationValue.fromRawValue(
        camera.sensorOrientation,
      );
    } else if (Platform.isAndroid) {
      final lockedOrientation = controller.value.lockedCaptureOrientation;
      final deviceOrientation =
          lockedOrientation ?? controller.value.deviceOrientation;
      final deviceRotationDegrees =
          _deviceOrientationDegrees[deviceOrientation];
      if (deviceRotationDegrees == null) return null;
      final compensatedRotation =
          (camera.sensorOrientation - deviceRotationDegrees + 360) % 360;
      imageRotation = InputImageRotationValue.fromRawValue(compensatedRotation);
    }
    if (imageRotation == null) return null;

    final inputImageFormat = InputImageFormatValue.fromRawValue(
      cameraImage.format.raw,
    );
    if (inputImageFormat == null) return null;
    if (Platform.isAndroid && inputImageFormat != InputImageFormat.nv21) {
      return null;
    }
    if (Platform.isIOS && inputImageFormat != InputImageFormat.bgra8888) {
      return null;
    }

    if (cameraImage.planes.length != 1) return null;
    final firstPlane = cameraImage.planes.first;

    return InputImage.fromBytes(
      bytes: firstPlane.bytes,
      metadata: InputImageMetadata(
        size: Size(
          cameraImage.width.toDouble(),
          cameraImage.height.toDouble(),
        ),
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: firstPlane.bytesPerRow,
      ),
    );
  }

  void _handleInsertPressed() {
    final previewText = _viewModel.previewText;
    if (previewText == null || previewText.trim().isEmpty) return;
    widget.onInsert(previewText.trim());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _viewModel.removeListener(_handleViewModelChanged);
    final controller = _cameraController;
    if (controller != null) {
      unawaited(controller.dispose());
    }
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildCameraLayer(),
            if (_showFocusFrame) const Center(child: _FocusFrameOverlay()),
            const Positioned(
              top: 6,
              left: 0,
              right: 0,
              child: _DragHandle(),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: _CloseButton(onPressed: widget.onClose),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: _PreviewAndInsertSection(
                viewModel: _viewModel,
                onInsertPressed: _handleInsertPressed,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _showFocusFrame {
    if (_isInitializing || _initializationError != null) return false;
    final controller = _cameraController;
    return controller != null && controller.value.isInitialized;
  }

  Widget _buildCameraLayer() {
    if (_isInitializing) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    final errorMessage = _initializationError;
    if (errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            errorMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
        ),
      );
    }

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    return CameraPreview(controller);
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 44,
        height: 5,
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(191),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

class _FocusFrameOverlay extends StatelessWidget {
  const _FocusFrameOverlay();

  static const Color _frameColor = Color(0xFFFFD400);
  static const double _frameWidthFraction = 0.72;
  static const double _frameAspectRatio = 1.6;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final frameWidth = constraints.maxWidth * _frameWidthFraction;
        final frameHeight = frameWidth / _frameAspectRatio;
        return IgnorePointer(
          child: CustomPaint(
            size: Size(frameWidth, frameHeight),
            painter: _FocusFramePainter(color: _frameColor),
          ),
        );
      },
    );
  }
}

class _FocusFramePainter extends CustomPainter {
  const _FocusFramePainter({required this.color});

  final Color color;

  static const double _cornerLength = 28;
  static const double _strokeWidth = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final cornerLength = _cornerLength.clamp(0.0, size.shortestSide / 2);

    // Canto superior esquerdo.
    canvas.drawLine(
      const Offset(0, 0),
      Offset(cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      const Offset(0, 0),
      Offset(0, cornerLength),
      paint,
    );

    // Canto superior direito.
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width - cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width, cornerLength),
      paint,
    );

    // Canto inferior esquerdo.
    canvas.drawLine(
      Offset(0, size.height),
      Offset(cornerLength, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height),
      Offset(0, size.height - cornerLength),
      paint,
    );

    // Canto inferior direito.
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width - cornerLength, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width, size.height - cornerLength),
      paint,
    );
  }

  @override
  bool shouldRepaint(_FocusFramePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withAlpha(115),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.close, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _PreviewAndInsertSection extends StatelessWidget {
  const _PreviewAndInsertSection({
    required this.viewModel,
    required this.onInsertPressed,
  });

  final _ScannerViewModel viewModel;
  final VoidCallback onInsertPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: viewModel,
      builder: (context, _) {
        final hasText = viewModel.hasRecognizedText;
        final previewText = viewModel.previewText ?? '';

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasText)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(140),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  previewText,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: hasText ? onInsertPressed : null,
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  disabledBackgroundColor: Colors.black.withAlpha(115),
                  disabledForegroundColor: Colors.white70,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: const Text(
                  'Inserir',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RecognitionResult {
  const _RecognitionResult({required this.value, required this.isBarcode});

  final String value;
  final bool isBarcode;
}

abstract class _FrameRecognitionService {
  bool get producesBarcodes;
  Future<List<String>> recognize(InputImage image);
  Future<void> dispose();
}

class _MlKitTextRecognitionService implements _FrameRecognitionService {
  _MlKitTextRecognitionService()
    : _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _textRecognizer;

  @override
  bool get producesBarcodes => false;

  @override
  Future<List<String>> recognize(InputImage image) async {
    final recognitionResult = await _textRecognizer.processImage(image);
    final recognizedLines = <String>[];
    for (final block in recognitionResult.blocks) {
      for (final line in block.lines) {
        recognizedLines.add(line.text);
      }
    }
    return recognizedLines;
  }

  @override
  Future<void> dispose() => _textRecognizer.close();
}

class _MlKitBarcodeRecognitionService implements _FrameRecognitionService {
  _MlKitBarcodeRecognitionService() : _barcodeScanner = BarcodeScanner();

  final BarcodeScanner _barcodeScanner;

  @override
  bool get producesBarcodes => true;

  @override
  Future<List<String>> recognize(InputImage image) async {
    final detectedBarcodes = await _barcodeScanner.processImage(image);
    final decodedValues = <String>[];
    for (final barcode in detectedBarcodes) {
      final rawValue = barcode.rawValue ?? barcode.displayValue;
      if (rawValue == null) continue;
      final trimmedValue = rawValue.trim();
      if (trimmedValue.isEmpty) continue;
      decodedValues.add(trimmedValue);
    }
    return decodedValues;
  }

  @override
  Future<void> dispose() => _barcodeScanner.close();
}

class _ScannerViewModel extends ChangeNotifier {
  _ScannerViewModel({
    required List<_FrameRecognitionService> recognitionServices,
  }) : _recognitionServices = recognitionServices;

  final List<_FrameRecognitionService> _recognitionServices;

  bool _isDisposed = false;
  bool _isProcessingFrame = false;
  String? _previewText;
  _RecognitionResult? _latestResult;

  String? get previewText => _previewText;
  _RecognitionResult? get latestResult => _latestResult;
  bool get hasRecognizedText =>
      _previewText != null && _previewText!.trim().isNotEmpty;

  Future<void> processFrame(InputImage cameraInputImage) async {
    if (_isDisposed || _isProcessingFrame) return;
    _isProcessingFrame = true;
    try {
      for (final service in _recognitionServices) {
        if (_isDisposed) return;
        final candidates = await service.recognize(cameraInputImage);
        final bestCandidate = service.producesBarcodes
            ? _pickFirstNonEmpty(candidates)
            : _pickLongestCandidate(candidates);
        if (bestCandidate == null) continue;
        if (_isDisposed) return;
        final previousResult = _latestResult;
        final hasChanged =
            previousResult == null ||
            previousResult.value != bestCandidate ||
            previousResult.isBarcode != service.producesBarcodes;
        if (!hasChanged) return;
        _latestResult = _RecognitionResult(
          value: bestCandidate,
          isBarcode: service.producesBarcodes,
        );
        _previewText = bestCandidate;
        notifyListeners();
        return;
      }
    } catch (_) {
      // Frames inválidos ou erros transitórios do ML Kit não interrompem a câmera.
    } finally {
      _isProcessingFrame = false;
    }
  }

  String? _pickLongestCandidate(List<String> candidates) {
    String? bestCandidate;
    var bestNonWhitespaceLength = 0;
    for (final rawCandidate in candidates) {
      final trimmedCandidate = rawCandidate.trim();
      if (trimmedCandidate.isEmpty) continue;
      final nonWhitespaceLength = trimmedCandidate
          .replaceAll(RegExp(r'\s+'), '')
          .length;
      if (nonWhitespaceLength > bestNonWhitespaceLength) {
        bestCandidate = trimmedCandidate;
        bestNonWhitespaceLength = nonWhitespaceLength;
      }
    }
    return bestCandidate;
  }

  String? _pickFirstNonEmpty(List<String> candidates) {
    for (final rawCandidate in candidates) {
      final trimmedCandidate = rawCandidate.trim();
      if (trimmedCandidate.isNotEmpty) return trimmedCandidate;
    }
    return null;
  }

  @override
  void dispose() {
    _isDisposed = true;
    for (final service in _recognitionServices) {
      unawaited(_disposeServiceSafely(service));
    }
    super.dispose();
  }

  Future<void> _disposeServiceSafely(_FrameRecognitionService service) async {
    try {
      await service.dispose();
    } catch (_) {
      // Falhas ao fechar o detector não devem propagar como uncaught
      // async exception após o painel ter sido desmontado.
    }
  }
}
