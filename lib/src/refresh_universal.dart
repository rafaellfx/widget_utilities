import 'package:flutter/material.dart';

/// Wrapper de pull-to-refresh que funciona com qualquer widget, scrollable
/// ou não.
///
/// Quando o [child] já é um widget naturalmente rolável (`ListView`,
/// `GridView`, `SingleChildScrollView`, `CustomScrollView`, `PageView`,
/// `NestedScrollView` ou `ScrollView`), o widget apenas o envolve com um
/// [RefreshIndicator]. Caso contrário, ele cria um `SingleChildScrollView`
/// com `AlwaysScrollableScrollPhysics` e altura mínima igual ao espaço
/// disponível, garantindo que o gesto de puxar funcione mesmo em conteúdos
/// curtos ou estáticos.
class RefreshUniversal extends StatelessWidget {
  /// Conteúdo a ser exibido dentro do refresh.
  final Widget child;

  /// Callback assíncrono invocado quando o usuário puxa para atualizar.
  /// Deve completar quando o trabalho de refresh terminar.
  final Future<void> Function() onRefresh;

  const RefreshUniversal({
    super.key,
    required this.child,
    required this.onRefresh,
  });

  bool _isScrollableWidget(Widget widget) {
    // Verifica se o widget é um tipo que naturalmente é scrollável
    return widget is ScrollView ||
        widget is ListView ||
        widget is GridView ||
        widget is CustomScrollView ||
        widget is SingleChildScrollView ||
        widget is PageView ||
        widget is NestedScrollView;
  }

  @override
  Widget build(BuildContext context) {
    // Caso o filho já seja um widget com scroll, apenas adicionamos o RefreshIndicator
    if (_isScrollableWidget(child)) {
      return RefreshIndicator(onRefresh: onRefresh, child: child);
    }

    // Caso não seja, envolvemos com SingleChildScrollView e AlwaysScrollableScrollPhysics
    return LayoutBuilder(
      builder: (_, constraints) {
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ScrollConfiguration(
            behavior: _NoGlowBehavior(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                  minWidth: constraints.maxWidth,
                ),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NoGlowBehavior extends ScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // Remove o efeito de overscroll (glow azul padrão)
    return child;
  }
}
