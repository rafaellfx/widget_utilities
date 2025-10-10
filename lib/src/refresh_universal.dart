import 'package:flutter/material.dart';

/// RefreshUniversal é um [StatelessWidget] que utiliza dos recursos
/// do [RefreshIndicator] com uma pequena diferença, permite adicionar
/// um filho (child) sem necessitar de um Scroll, ou seja adiciona
///  o pull to refresh em qual quer widget.

class RefreshUniversal extends StatelessWidget {
  final Widget child;
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
      builder: (_, constrains) {
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ScrollConfiguration(
            behavior: _NoGlowBehavior(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constrains.maxHeight,
                  minWidth: constrains.maxWidth,
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
