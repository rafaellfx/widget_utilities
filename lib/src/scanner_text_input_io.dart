import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

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
    unawaited(
      _viewModel.processFrame(
        inputImage,
        lensDirection: activeCamera.lensDirection,
      ),
    );
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
            if (_showFocusFrame)
              Positioned.fill(child: _FocusOverlay(viewModel: _viewModel)),
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

    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return CameraPreview(controller);
    }

    // O bottom sheet é exibido em retrato; a prévia precisa cobrir o painel
    // com o mesmo cover usado pelo overlay para que os colchetes fiquem
    // alinhados com a imagem real.
    final uprightDisplaySize = previewSize.width >= previewSize.height
        ? Size(previewSize.height, previewSize.width)
        : previewSize;

    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: uprightDisplaySize.width,
          height: uprightDisplaySize.height,
          child: CameraPreview(controller),
        ),
      ),
    );
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

const Color _focusFrameColor = Color(0xFFFFD400);

/// Overlay que acompanha o view model: desenha colchetes amarelos ao redor da
/// palavra focada (a mais próxima do centro) e, quando não há palavra no
/// quadro, exibe o quadro central estático como guia de enquadramento.
class _FocusOverlay extends StatelessWidget {
  const _FocusOverlay({required this.viewModel});

  final _ScannerViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: viewModel,
        builder: (context, _) {
          return CustomPaint(
            size: Size.infinite,
            painter: _FocusFramePainter(
              color: _focusFrameColor,
              focusedWord: viewModel.focusedWord,
            ),
          );
        },
      ),
    );
  }
}

/// Dimensões da imagem já rotacionada para a orientação de exibição.
Size _uprightImageSize(Size imageSize, InputImageRotation rotation) {
  if (rotation == InputImageRotation.rotation90deg ||
      rotation == InputImageRotation.rotation270deg) {
    return Size(imageSize.height, imageSize.width);
  }
  return imageSize;
}

/// Converte uma caixa em coordenadas do buffer (convenção ML Kit, rotation=0)
/// para o espaço "upright" (imagem já rotacionada para exibição).
Rect _bufferRectToUprightRect(
  Rect boundingBox,
  Size imageSize,
  InputImageRotation rotation,
  CameraLensDirection lensDirection,
) {
  final bufferWidth = imageSize.width;
  final bufferHeight = imageSize.height;

  Offset mapPoint(double bufferX, double bufferY) {
    switch (rotation) {
      case InputImageRotation.rotation90deg:
        return Offset(bufferHeight - bufferY, bufferX);
      case InputImageRotation.rotation270deg:
        return Offset(bufferY, bufferWidth - bufferX);
      case InputImageRotation.rotation180deg:
        return Offset(bufferWidth - bufferX, bufferHeight - bufferY);
      case InputImageRotation.rotation0deg:
        return Offset(bufferX, bufferY);
    }
  }

  final corners = <Offset>[
    mapPoint(boundingBox.left, boundingBox.top),
    mapPoint(boundingBox.right, boundingBox.top),
    mapPoint(boundingBox.right, boundingBox.bottom),
    mapPoint(boundingBox.left, boundingBox.bottom),
  ];

  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;
  for (final corner in corners) {
    minX = math.min(minX, corner.dx);
    minY = math.min(minY, corner.dy);
    maxX = math.max(maxX, corner.dx);
    maxY = math.max(maxY, corner.dy);
  }
  var uprightRect = Rect.fromLTRB(minX, minY, maxX, maxY);

  // Câmera frontal espelha horizontalmente.
  if (lensDirection == CameraLensDirection.front) {
    final uprightWidth = _uprightImageSize(imageSize, rotation).width;
    uprightRect = Rect.fromLTRB(
      uprightWidth - uprightRect.right,
      uprightRect.top,
      uprightWidth - uprightRect.left,
      uprightRect.bottom,
    );
  }
  return uprightRect;
}

/// Aplica cover-fit uniforme de [uprightRect] (no espaço de [uprightSize]) para
/// o painel de tamanho [panelSize], igual ao usado na prévia da câmera.
Rect _coverRectToPanel(Rect uprightRect, Size uprightSize, Size panelSize) {
  final scale = math.max(
    panelSize.width / uprightSize.width,
    panelSize.height / uprightSize.height,
  );
  final offsetX = (panelSize.width - uprightSize.width * scale) / 2;
  final offsetY = (panelSize.height - uprightSize.height * scale) / 2;
  return Rect.fromLTRB(
    offsetX + uprightRect.left * scale,
    offsetY + uprightRect.top * scale,
    offsetX + uprightRect.right * scale,
    offsetY + uprightRect.bottom * scale,
  );
}

class _FocusFramePainter extends CustomPainter {
  const _FocusFramePainter({required this.color, this.focusedWord});

  final Color color;
  final _FocusedWord? focusedWord;

  static const double _cornerLength = 28;
  static const double _strokeWidth = 4;
  // Quadro central de fallback quando nenhuma palavra está focada.
  static const double _centerFrameWidthFraction = 0.72;
  static const double _centerFrameAspectRatio = 1.6;
  // Folga ao redor da palavra focada.
  static const double _wordPadding = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final targetRect = _resolveTargetRect(size);
    if (targetRect == null) return;
    _drawCornerBrackets(canvas, targetRect);
  }

  Rect? _resolveTargetRect(Size panelSize) {
    final word = focusedWord;
    if (word == null) {
      final frameWidth = panelSize.width * _centerFrameWidthFraction;
      final frameHeight = frameWidth / _centerFrameAspectRatio;
      return Rect.fromLTWH(
        (panelSize.width - frameWidth) / 2,
        (panelSize.height - frameHeight) / 2,
        frameWidth,
        frameHeight,
      );
    }

    final uprightSize = _uprightImageSize(word.imageSize, word.rotation);
    if (uprightSize.width <= 0 || uprightSize.height <= 0) return null;
    final uprightRect = _bufferRectToUprightRect(
      word.boundingBoxInImage,
      word.imageSize,
      word.rotation,
      word.lensDirection,
    );
    final panelRect = _coverRectToPanel(uprightRect, uprightSize, panelSize);
    return panelRect.inflate(_wordPadding);
  }

  void _drawCornerBrackets(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final cornerLength = _cornerLength.clamp(0.0, rect.shortestSide / 2);

    // Canto superior esquerdo.
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(cornerLength, 0), paint);
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(0, cornerLength), paint);
    // Canto superior direito.
    canvas.drawLine(
      rect.topRight,
      rect.topRight + Offset(-cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      rect.topRight,
      rect.topRight + Offset(0, cornerLength),
      paint,
    );
    // Canto inferior esquerdo.
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + Offset(cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + Offset(0, -cornerLength),
      paint,
    );
    // Canto inferior direito.
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight + Offset(-cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight + Offset(0, -cornerLength),
      paint,
    );
  }

  @override
  bool shouldRepaint(_FocusFramePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.focusedWord != focusedWord;
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

/// Um item reconhecido em um quadro: texto e a caixa delimitadora em
/// coordenadas do buffer da imagem (convenção do ML Kit, rotation=0).
class _RecognizedItem {
  const _RecognizedItem({required this.text, required this.boundingBox});

  final String text;
  final Rect boundingBox;
}

/// Palavra atualmente focada (mais próxima do centro), com a geometria
/// necessária para o overlay projetá-la na tela.
class _FocusedWord {
  const _FocusedWord({
    required this.text,
    required this.boundingBoxInImage,
    required this.imageSize,
    required this.rotation,
    required this.lensDirection,
  });

  final String text;
  final Rect boundingBoxInImage;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection lensDirection;
}

abstract class _FrameRecognitionService {
  bool get producesBarcodes;
  Future<List<_RecognizedItem>> recognize(InputImage image);
  Future<void> dispose();
}

class _MlKitTextRecognitionService implements _FrameRecognitionService {
  _MlKitTextRecognitionService()
    : _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _textRecognizer;

  @override
  bool get producesBarcodes => false;

  @override
  Future<List<_RecognizedItem>> recognize(InputImage image) async {
    final recognitionResult = await _textRecognizer.processImage(image);
    final recognizedWords = <_RecognizedItem>[];
    for (final block in recognitionResult.blocks) {
      for (final line in block.lines) {
        for (final element in line.elements) {
          final wordText = element.text.trim();
          if (wordText.isEmpty) continue;
          recognizedWords.add(
            _RecognizedItem(text: wordText, boundingBox: element.boundingBox),
          );
        }
      }
    }
    return recognizedWords;
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
  Future<List<_RecognizedItem>> recognize(InputImage image) async {
    final detectedBarcodes = await _barcodeScanner.processImage(image);
    final decodedValues = <_RecognizedItem>[];
    for (final barcode in detectedBarcodes) {
      final rawValue = barcode.rawValue ?? barcode.displayValue;
      if (rawValue == null) continue;
      final trimmedValue = rawValue.trim();
      if (trimmedValue.isEmpty) continue;
      decodedValues.add(
        _RecognizedItem(
          text: trimmedValue,
          boundingBox: barcode.boundingBox,
        ),
      );
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

  // Ignora caixas minúsculas (ruído) na escolha da palavra central.
  static const double _minWordAreaFraction = 0.0005;

  bool _isDisposed = false;
  bool _isProcessingFrame = false;
  String? _previewText;
  _RecognitionResult? _latestResult;
  _FocusedWord? _focusedWord;

  String? get previewText => _previewText;
  _RecognitionResult? get latestResult => _latestResult;
  _FocusedWord? get focusedWord => _focusedWord;
  bool get hasRecognizedText =>
      _previewText != null && _previewText!.trim().isNotEmpty;

  Future<void> processFrame(
    InputImage cameraInputImage, {
    required CameraLensDirection lensDirection,
  }) async {
    if (_isDisposed || _isProcessingFrame) return;
    _isProcessingFrame = true;
    try {
      for (final service in _recognitionServices) {
        if (_isDisposed) return;
        final recognizedItems = await service.recognize(cameraInputImage);
        if (_isDisposed) return;
        if (service.producesBarcodes) {
          if (_applyBarcodeResult(recognizedItems)) return;
          continue;
        }
        if (_applyFocusedWord(recognizedItems, cameraInputImage, lensDirection)) {
          return;
        }
      }
    } catch (_) {
      // Frames inválidos ou erros transitórios do ML Kit não interrompem a câmera.
    } finally {
      _isProcessingFrame = false;
    }
  }

  bool _applyBarcodeResult(List<_RecognizedItem> recognizedItems) {
    final firstValue = _pickFirstNonEmpty(recognizedItems);
    if (firstValue == null) return false;
    final previousResult = _latestResult;
    final hasChanged =
        previousResult == null ||
        previousResult.value != firstValue ||
        !previousResult.isBarcode;
    if (hasChanged) {
      _latestResult = _RecognitionResult(value: firstValue, isBarcode: true);
      _previewText = firstValue;
      _focusedWord = null;
      notifyListeners();
    }
    return true;
  }

  bool _applyFocusedWord(
    List<_RecognizedItem> recognizedItems,
    InputImage cameraInputImage,
    CameraLensDirection lensDirection,
  ) {
    final imageSize = cameraInputImage.metadata?.size;
    final rotation = cameraInputImage.metadata?.rotation;
    if (imageSize == null || rotation == null) return false;

    final nearestWord = _pickWordNearestCenter(recognizedItems, imageSize);
    if (nearestWord == null) {
      // Sem palavra no quadro: limpa só o overlay e preserva o previewText
      // para o botão "Inserir" continuar utilizável.
      if (_focusedWord != null) {
        _focusedWord = null;
        notifyListeners();
      }
      return false;
    }

    final hasChanged =
        _focusedWord == null ||
        _focusedWord!.boundingBoxInImage != nearestWord.boundingBox ||
        _focusedWord!.text != nearestWord.text;
    if (hasChanged) {
      _focusedWord = _FocusedWord(
        text: nearestWord.text,
        boundingBoxInImage: nearestWord.boundingBox,
        imageSize: imageSize,
        rotation: rotation,
        lensDirection: lensDirection,
      );
      _latestResult = _RecognitionResult(
        value: nearestWord.text,
        isBarcode: false,
      );
      _previewText = nearestWord.text;
      notifyListeners();
    }
    return true;
  }

  _RecognizedItem? _pickWordNearestCenter(
    List<_RecognizedItem> recognizedItems,
    Size imageSize,
  ) {
    final imageCenter = Offset(imageSize.width / 2, imageSize.height / 2);
    final minWordArea =
        imageSize.width * imageSize.height * _minWordAreaFraction;
    _RecognizedItem? nearestWord;
    var smallestDistance = double.infinity;
    for (final item in recognizedItems) {
      final boundingBox = item.boundingBox;
      if (boundingBox.width <= 0 || boundingBox.height <= 0) continue;
      if (boundingBox.width * boundingBox.height < minWordArea) continue;
      final distanceToCenter = (boundingBox.center - imageCenter).distance;
      if (distanceToCenter < smallestDistance) {
        smallestDistance = distanceToCenter;
        nearestWord = item;
      }
    }
    return nearestWord;
  }

  String? _pickFirstNonEmpty(List<_RecognizedItem> recognizedItems) {
    for (final item in recognizedItems) {
      final trimmedValue = item.text.trim();
      if (trimmedValue.isNotEmpty) return trimmedValue;
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
