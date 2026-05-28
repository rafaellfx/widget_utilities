import 'package:flutter/material.dart';

/// Define o que o scanner deve reconhecer.
///
/// - [text]: apenas OCR de texto (comportamento padrão e legado).
/// - [barcode]: apenas códigos de barra 1D/2D e QR Code.
/// - [textAndBarcode]: ambos no mesmo painel.
///
/// Em plataformas sem suporte (web/desktop) este enum existe apenas para
/// preservar a API; nenhum reconhecimento é executado.
enum ScannerMode { text, barcode, textAndBarcode }

/// Utilitário para integrar scanner em qualquer
/// [TextField]/[TextFormField] via `contextMenuBuilder`.
///
/// O scanner com câmera (OCR e leitura de códigos de barra/QR Code) é
/// suportado apenas em Android e iOS. Em outras plataformas, a chamada
/// exibe uma mensagem amigável e não altera o campo.
class ScannerTextInput {
  ScannerTextInput._();

  static const String _defaultMenuLabel = 'Scannear etiqueta';
  static const String _unsupportedPlatformMessage =
      'ScannerTextInput é suportado apenas no Android e iOS.';

  /// Retorna um [EditableTextContextMenuBuilder] que insere a opção de scanner
  /// no menu de contexto do campo de texto. Em plataformas não suportadas, a
  /// opção continua aparecendo, mas ao ser tocada apenas exibe uma mensagem.
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

  /// Em plataformas sem suporte, exibe uma mensagem e não retorna texto.
  static Future<void> open(
    BuildContext context, {
    required ValueChanged<String> onTextScanned,
    ScannerMode mode = ScannerMode.text,
    bool autoConfirmBarcode = true,
  }) async {
    FocusScope.of(context).unfocus();
    _showUnsupportedPlatformMessage(context);
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
