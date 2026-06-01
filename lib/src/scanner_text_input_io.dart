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
  static const double _modalHeightFraction = 0.34;

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
  /// fluxos de digitalização rápida.
  ///
  /// No modo texto, a frase (linha de texto) sob a mira preenche o campo ao
  /// vivo: cada leitura estável dispara [onTextScanned] em tempo real, sem
  /// etapa de confirmação. O usuário encerra tocando em "Concluir" ou fechando
  /// o painel, e o último valor entregue permanece no campo.
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

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // O painel controla a própria altura e é redimensionável arrastando o
      // puxador; desabilitamos o arraste do bottom sheet para que o gesto
      // vertical ajuste o tamanho da câmera em vez de fechar o painel.
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withAlpha(64),
      builder: (modalContext) {
        return _ScannerPanel(
          mode: mode,
          autoConfirmBarcode: autoConfirmBarcode,
          initialHeightFraction: _modalHeightFraction,
          onTextRecognized: onTextScanned,
          onClose: () => Navigator.of(modalContext).pop(),
        );
      },
    );
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
    required this.initialHeightFraction,
    required this.onTextRecognized,
    required this.onClose,
  });

  final ScannerMode mode;
  final bool autoConfirmBarcode;

  /// Fração da altura da tela usada quando o painel abre. O usuário pode
  /// aumentar/diminuir arrastando o puxador no topo.
  final double initialHeightFraction;

  /// Chamado em tempo real a cada frase/código estável reconhecido, para
  /// preencher o campo de origem ao vivo.
  final ValueChanged<String> onTextRecognized;

  /// Encerra o painel mantendo o último valor já entregue.
  final VoidCallback onClose;

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

  // Limites de redimensionamento do painel ao arrastar o puxador: nunca
  // menor que a altura inicial nem maior que quase a tela inteira.
  static const double _minHeightFraction = 0.34;
  static const double _maxHeightFraction = 0.94;

  CameraController? _cameraController;
  CameraDescription? _activeCamera;
  bool _isInitializing = true;
  String? _initializationError;
  late final _ScannerViewModel _viewModel;
  bool _hasAutoConfirmed = false;
  String? _lastEmittedText;

  /// Fração corrente da altura da tela ocupada pelo painel. Ajustada ao vivo
  /// pelo arraste vertical do puxador.
  late double _heightFraction;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _heightFraction = widget.initialHeightFraction.clamp(
      _minHeightFraction,
      _maxHeightFraction,
    );
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
    if (!mounted) return;
    final latestResult = _viewModel.latestResult;
    if (latestResult == null) return;
    final recognizedValue = latestResult.value.trim();
    if (recognizedValue.isEmpty) return;

    // Preenche o campo de origem ao vivo, sem aguardar confirmação.
    if (recognizedValue != _lastEmittedText) {
      _lastEmittedText = recognizedValue;
      widget.onTextRecognized(recognizedValue);
    }

    // Código de barras/QR encerra o painel automaticamente após entregar.
    if (widget.autoConfirmBarcode &&
        latestResult.isBarcode &&
        !_hasAutoConfirmed) {
      _hasAutoConfirmed = true;
      widget.onClose();
    }
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
    final screenHeight = MediaQuery.of(context).size.height;
    return SizedBox(
      height: screenHeight * _heightFraction,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        child: Container(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildCameraLayer(),
              if (_showFocusFrame)
                Positioned.fill(child: _FocusOverlay(viewModel: _viewModel)),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: _handleResizeDrag,
                  child: const Padding(
                    padding: EdgeInsets.only(top: 6, bottom: 12),
                    child: _DragHandle(),
                  ),
                ),
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
                child: _LivePreviewSection(
                  viewModel: _viewModel,
                  onDone: widget.onClose,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Ajusta a altura do painel conforme o arraste vertical do puxador:
  /// arrastar para cima aumenta a câmera, para baixo diminui.
  void _handleResizeDrag(DragUpdateDetails details) {
    final screenHeight = MediaQuery.of(context).size.height;
    if (screenHeight <= 0) return;
    setState(() {
      final nextFraction = _heightFraction - details.delta.dy / screenHeight;
      _heightFraction = nextFraction.clamp(
        _minHeightFraction,
        _maxHeightFraction,
      );
    });
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

/// Overlay que acompanha o view model: desenha colchetes amarelos ao redor do
/// item focado e volta ao quadro central quando ainda não há foco estável.
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
              focusedItem: viewModel.focusedItem,
            ),
          );
        },
      ),
    );
  }
}

/// Largura/altura da imagem na orientação de exibição (upright).
///
/// O ML Kit já devolve os bounding boxes nesse espaço orientado. No Android o
/// buffer chega em paisagem, então com rotação de 90°/270° as dimensões ficam
/// trocadas em relação ao upright; no iOS o tamanho informado já corresponde
/// ao upright.
Size _orientedImageSize(Size imageSize, InputImageRotation rotation) {
  final rotatedOnAndroid =
      !Platform.isIOS &&
      (rotation == InputImageRotation.rotation90deg ||
          rotation == InputImageRotation.rotation270deg);
  return rotatedOnAndroid
      ? Size(imageSize.height, imageSize.width)
      : imageSize;
}

/// Projeta uma caixa do ML Kit — já no espaço orientado de [orientedSize] —
/// sobre o painel de tamanho [panelSize], replicando o mesmo `BoxFit.cover` da
/// prévia da câmera.
///
/// Não há troca de eixos: o ML Kit entrega as caixas já orientadas, então uma
/// linha de texto horizontal permanece horizontal. Apenas espelhamos no eixo X
/// quando a câmera é frontal ou a rotação é de 270°.
Rect _orientedRectToPanel(
  Rect orientedRect,
  Size orientedSize,
  Size panelSize,
  InputImageRotation rotation,
  CameraLensDirection lensDirection,
) {
  final coverScale = math.max(
    panelSize.width / orientedSize.width,
    panelSize.height / orientedSize.height,
  );
  final offsetX = (panelSize.width - orientedSize.width * coverScale) / 2;
  final offsetY = (panelSize.height - orientedSize.height * coverScale) / 2;

  final mirrorX =
      (lensDirection == CameraLensDirection.front) ^
      (rotation == InputImageRotation.rotation270deg);

  double mapX(double orientedX) {
    final adjustedX = mirrorX ? orientedSize.width - orientedX : orientedX;
    return offsetX + adjustedX * coverScale;
  }

  double mapY(double orientedY) => offsetY + orientedY * coverScale;

  final firstX = mapX(orientedRect.left);
  final secondX = mapX(orientedRect.right);
  final top = mapY(orientedRect.top);
  final bottom = mapY(orientedRect.bottom);
  return Rect.fromLTRB(
    math.min(firstX, secondX),
    top,
    math.max(firstX, secondX),
    bottom,
  );
}

class _FocusFramePainter extends CustomPainter {
  const _FocusFramePainter({required this.color, this.focusedItem});

  final Color color;
  final _FocusedItem? focusedItem;

  static const double _cornerLength = 28;
  static const double _strokeWidth = 3;
  // Raio da dobra arredondada dos cantos.
  static const double _cornerRadius = 6;
  // Opacidade do traço.
  static const double _strokeOpacity = 0.85;
  // Quadro central de fallback quando nenhum item está focado.
  static const double _centerFrameWidthFraction = 0.72;
  static const double _centerFrameAspectRatio = 1.6;
  // Folga ao redor do item focado.
  static const double _itemPadding = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final targetRect = _resolveTargetRect(size);
    if (targetRect == null) return;
    _drawCornerBrackets(canvas, targetRect);
  }

  Rect? _resolveTargetRect(Size panelSize) {
    final item = focusedItem;
    if (item == null) {
      final frameWidth = panelSize.width * _centerFrameWidthFraction;
      final frameHeight = frameWidth / _centerFrameAspectRatio;
      return Rect.fromLTWH(
        (panelSize.width - frameWidth) / 2,
        (panelSize.height - frameHeight) / 2,
        frameWidth,
        frameHeight,
      );
    }

    final orientedSize = _orientedImageSize(item.imageSize, item.rotation);
    if (orientedSize.width <= 0 || orientedSize.height <= 0) return null;
    final panelRect = _orientedRectToPanel(
      item.boundingBoxInImage,
      orientedSize,
      panelSize,
      item.rotation,
      item.lensDirection,
    );
    return panelRect.inflate(_itemPadding);
  }

  void _drawCornerBrackets(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = color.withValues(alpha: _strokeOpacity)
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final armLength = _cornerLength.clamp(0.0, rect.shortestSide / 2);

    canvas.drawPath(_buildCornerPath(rect.topLeft, 1, 1, armLength), paint);
    canvas.drawPath(_buildCornerPath(rect.topRight, -1, 1, armLength), paint);
    canvas.drawPath(
      _buildCornerPath(rect.bottomLeft, 1, -1, armLength),
      paint,
    );
    canvas.drawPath(
      _buildCornerPath(rect.bottomRight, -1, -1, armLength),
      paint,
    );
  }

  /// Desenha um canto em "L" com a dobra arredondada. [horizontalDirection] e
  /// [verticalDirection] valem +1/-1 conforme o sentido de cada braço.
  Path _buildCornerPath(
    Offset corner,
    double horizontalDirection,
    double verticalDirection,
    double armLength,
  ) {
    final clampedRadius = _cornerRadius.clamp(0.0, armLength);
    return Path()
      ..moveTo(corner.dx + horizontalDirection * armLength, corner.dy)
      ..lineTo(corner.dx + horizontalDirection * clampedRadius, corner.dy)
      ..quadraticBezierTo(
        corner.dx,
        corner.dy,
        corner.dx,
        corner.dy + verticalDirection * clampedRadius,
      )
      ..lineTo(corner.dx, corner.dy + verticalDirection * armLength);
  }

  @override
  bool shouldRepaint(_FocusFramePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.focusedItem != focusedItem;
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

/// Mostra a frase reconhecida sob a mira (que já está sendo escrita no campo
/// de origem ao vivo) e oferece o botão "Concluir" para encerrar o painel.
class _LivePreviewSection extends StatelessWidget {
  const _LivePreviewSection({required this.viewModel, required this.onDone});

  final _ScannerViewModel viewModel;
  final VoidCallback onDone;

  static const double _controlHeight = 44;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: viewModel,
      builder: (context, _) {
        final recognizedSentence = viewModel.previewText?.trim() ?? '';
        final hasSentence = recognizedSentence.isNotEmpty;

        return Row(
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: _controlHeight),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(140),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  hasSentence
                      ? recognizedSentence
                      : 'Aponte a câmera para o texto',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hasSentence ? Colors.white : Colors.white60,
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: hasSentence
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: _controlHeight,
              child: FilledButton(
                onPressed: onDone,
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: const Text(
                  'Concluir',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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

/// Um item reconhecido em um quadro: texto e a caixa delimitadora no espaço
/// já orientado da imagem, conforme o ML Kit entrega após aplicar a rotação.
class _RecognizedItem {
  const _RecognizedItem({required this.text, required this.boundingBox});

  final String text;
  final Rect boundingBox;
}

/// Item atualmente focado, com a geometria necessária para o overlay
/// projetá-lo na tela.
class _FocusedItem {
  const _FocusedItem({
    required this.text,
    required this.isBarcode,
    required this.boundingBoxInImage,
    required this.imageSize,
    required this.rotation,
    required this.lensDirection,
  });

  final String text;
  final bool isBarcode;
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
    final recognizedSentences = <_RecognizedItem>[];
    // Cada linha de texto (TextLine) é tratada como uma frase candidata, para
    // que o foco prenda exatamente a linha sob a mira em vez do parágrafo todo.
    for (final block in recognitionResult.blocks) {
      for (final line in block.lines) {
        final sentence = line.text.trim();
        if (sentence.isEmpty) continue;
        final lineBoundingBox = line.boundingBox;
        if (lineBoundingBox.width <= 0 || lineBoundingBox.height <= 0) {
          continue;
        }
        recognizedSentences.add(
          _RecognizedItem(text: sentence, boundingBox: lineBoundingBox),
        );
      }
    }
    return recognizedSentences;
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

  // Ignora caixas minúsculas (ruído) na escolha da linha central.
  static const double _minRecognizedAreaFraction = 0.0008;
  static const double _centerHitSlopFraction = 0.035;
  // Leve preferência por linhas mais longas para descartar fragmentos soltos,
  // sem sobrepor a proximidade da linha sob a mira.
  static const double _largerItemBias = 0.2;
  static const int _stableFrameThreshold = 2;
  static const int _clearFocusAfterMissedFrames = 3;

  bool _isDisposed = false;
  bool _isProcessingFrame = false;
  _RecognitionResult? _latestResult;
  _FocusedItem? _focusedItem;
  String? _pendingCandidateValue;
  bool? _pendingCandidateIsBarcode;
  Rect? _pendingCandidateBoundingBox;
  int _pendingCandidateFrameCount = 0;
  int _missedCandidateFrameCount = 0;

  String? get previewText => _latestResult?.value;
  _RecognitionResult? get latestResult => _latestResult;
  _FocusedItem? get focusedItem => _focusedItem;

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
        if (_applyRecognizedResult(
          recognizedItems,
          cameraInputImage,
          lensDirection,
          isBarcode: service.producesBarcodes,
        )) {
          return;
        }
      }
      _handleMissingCandidate();
    } catch (_) {
      _handleMissingCandidate();
      // Frames inválidos ou erros transitórios do ML Kit não interrompem a câmera.
    } finally {
      _isProcessingFrame = false;
    }
  }

  bool _applyRecognizedResult(
    List<_RecognizedItem> recognizedItems,
    InputImage cameraInputImage,
    CameraLensDirection lensDirection, {
    required bool isBarcode,
  }) {
    final imageSize = cameraInputImage.metadata?.size;
    final rotation = cameraInputImage.metadata?.rotation;
    if (imageSize == null || rotation == null) return false;

    final candidate = _pickItemNearestCenter(
      recognizedItems,
      imageSize,
      rotation,
    );
    if (candidate == null) return false;

    final candidateValue = candidate.text.trim();
    if (candidateValue.isEmpty) return false;
    _missedCandidateFrameCount = 0;
    if (!_isStableCandidate(
      candidateValue,
      isBarcode,
      candidate.boundingBox,
    )) {
      return true;
    }

    final focusedCandidate = _FocusedItem(
      text: candidateValue,
      isBarcode: isBarcode,
      boundingBoxInImage: candidate.boundingBox,
      imageSize: imageSize,
      rotation: rotation,
      lensDirection: lensDirection,
    );
    final previousResult = _latestResult;
    final resultHasChanged =
        previousResult == null ||
        previousResult.value != candidateValue ||
        previousResult.isBarcode != isBarcode;
    final focusHasChanged = _shouldUpdateFocusedItem(focusedCandidate);
    if (resultHasChanged || focusHasChanged) {
      if (focusHasChanged) {
        _focusedItem = focusedCandidate;
      }
      if (resultHasChanged) {
        _latestResult = _RecognitionResult(
          value: candidateValue,
          isBarcode: isBarcode,
        );
      }
      notifyListeners();
    }
    return true;
  }

  bool _shouldUpdateFocusedItem(_FocusedItem candidate) {
    final current = _focusedItem;
    if (current == null ||
        current.text != candidate.text ||
        current.isBarcode != candidate.isBarcode) {
      return true;
    }

    return current.boundingBoxInImage != candidate.boundingBoxInImage ||
        current.imageSize != candidate.imageSize ||
        current.rotation != candidate.rotation ||
        current.lensDirection != candidate.lensDirection;
  }

  void _handleMissingCandidate() {
    _resetPendingCandidate();
    final current = _focusedItem;
    if (current == null) return;

    _missedCandidateFrameCount++;
    if (_missedCandidateFrameCount >= _clearFocusAfterMissedFrames) {
      _focusedItem = null;
      notifyListeners();
    }
  }

  bool _isStableCandidate(
    String candidateValue,
    bool isBarcode,
    Rect boundingBox,
  ) {
    final isSameCandidate =
        _pendingCandidateValue == candidateValue &&
        _pendingCandidateIsBarcode == isBarcode &&
        _isNearPendingCandidate(boundingBox);
    if (isSameCandidate) {
      _pendingCandidateFrameCount++;
    } else {
      _pendingCandidateValue = candidateValue;
      _pendingCandidateIsBarcode = isBarcode;
      _pendingCandidateFrameCount = 1;
    }
    _pendingCandidateBoundingBox = boundingBox;
    return _pendingCandidateFrameCount >= _stableFrameThreshold;
  }

  bool _isNearPendingCandidate(Rect boundingBox) {
    final previousBoundingBox = _pendingCandidateBoundingBox;
    if (previousBoundingBox == null) return true;

    final currentReferenceSize = math.max(
      boundingBox.width,
      boundingBox.height,
    );
    final previousReferenceSize = math.max(
      previousBoundingBox.width,
      previousBoundingBox.height,
    );
    final allowedDrift =
        math.max(currentReferenceSize, previousReferenceSize) * 1.1;
    return (boundingBox.center - previousBoundingBox.center).distance <=
        allowedDrift;
  }

  void _resetPendingCandidate() {
    _pendingCandidateValue = null;
    _pendingCandidateIsBarcode = null;
    _pendingCandidateBoundingBox = null;
    _pendingCandidateFrameCount = 0;
  }

  _RecognizedItem? _pickItemNearestCenter(
    List<_RecognizedItem> recognizedItems,
    Size imageSize,
    InputImageRotation rotation,
  ) {
    final orientedSize = _orientedImageSize(imageSize, rotation);
    if (orientedSize.width <= 0 || orientedSize.height <= 0) return null;

    final imageCenter = Offset(orientedSize.width / 2, orientedSize.height / 2);
    final centerHitSlop =
        math.min(orientedSize.width, orientedSize.height) *
        _centerHitSlopFraction;
    final minRecognizedArea =
        orientedSize.width * orientedSize.height * _minRecognizedAreaFraction;
    _RecognizedItem? nearestItem;
    var bestScore = double.infinity;

    // O bounding box do ML Kit já está no espaço orientado, então a distância
    // até o centro da mira é medida direto, sem rotação de eixos.
    for (final item in recognizedItems) {
      if (item.text.trim().isEmpty) continue;
      final orientedRect = item.boundingBox;
      if (orientedRect.width <= 0 || orientedRect.height <= 0) continue;
      if (orientedRect.width * orientedRect.height < minRecognizedArea) {
        continue;
      }

      final distanceToRect = _distanceFromPointToRect(
        imageCenter,
        orientedRect.inflate(centerHitSlop),
      );
      final distanceToCenter = (orientedRect.center - imageCenter).distance;
      final baseScore = distanceToRect == 0
          ? distanceToCenter * 0.2
          : distanceToRect + distanceToCenter * 0.05;
      final largerItemBonus =
          math.sqrt(orientedRect.width * orientedRect.height) *
          _largerItemBias;
      final score = baseScore - largerItemBonus;
      if (score < bestScore) {
        bestScore = score;
        nearestItem = item;
      }
    }
    return nearestItem;
  }

  double _distanceFromPointToRect(Offset point, Rect rect) {
    final dx = point.dx < rect.left
        ? rect.left - point.dx
        : math.max(0, point.dx - rect.right);
    final dy = point.dy < rect.top
        ? rect.top - point.dy
        : math.max(0, point.dy - rect.bottom);
    return math.sqrt(dx * dx + dy * dy);
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
