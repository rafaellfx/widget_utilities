# 🧩 widget_utilities

**Coleção de widgets customizados reutilizáveis** para o dia a dia do desenvolvimento Flutter.  
O objetivo deste package é acelerar o desenvolvimento com componentes práticos, reutilizáveis e baseados em boas práticas.

---

## 🚀 Objetivo

O **`widget_utilities`** nasceu da necessidade de **evitar repetição de código** e **padronizar componentes visuais** usados em diversos projetos Flutter.  
Aqui você encontra widgets prontos para uso, leves e fáceis de integrar com uns adicionais.  

---

## 📦 Instalação

Adicione a dependência no seu `pubspec.yaml`:
```yaml
dependencies:
  widget_utilities: ^0.1.0
```

## ⚙️ Importação

```dart
import 'package:widget_utilities/widget_utilities.dart';

```

## 🔄 Exemplo de uso RefreshUniversal


```dart
import 'package:flutter/material.dart';
import 'package:widget_utilities/widget_utilities.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<void> _onRefresh() async {
    await Future.delayed(const Duration(seconds: 2));
    debugPrint('Página atualizada!');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('widget_utilities Example')),
        body: RefreshUniversal(
          onRefresh: _onRefresh,
          child: const Center(
            child: Text('Puxe para atualizar 🚀'),
          ),
        ),
      ),
    );
  }
}
```

## 🗓️ Exemplo simples com o DatePickerUniversal

```dart
import 'package:flutter/material.dart';
import 'package:widget_utilities/widget_utilities.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<void> _onRefresh() async {
    await Future.delayed(const Duration(seconds: 2));
    debugPrint('Página atualizada!');
  }

  Future<void> _showDatePicker(BuildContext context) async {
    final DateTime? date = await DatePickerUniversal.show(
      context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      addButtonToday: true, // Ativa o botão "Hoje"
    );

    if (date != null) {
      debugPrint('Data selecionada: $date');
    } else {
      debugPrint('Seleção cancelada');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('widget_utilities Example')),
        body: RefreshUniversal(
          onRefresh: _onRefresh,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Puxe para atualizar 🚀'),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => _showDatePicker(context),
                  child: const Text('Abrir DatePickerUniversal'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```



## 🧱 Widgets disponíveis

| Widget | Descrição | Exemplo |
|--------|------------|----------|
| **RefreshUniversal** | Widget de *pull-to-refresh* que funciona com ou sem scroll. Ideal para qualquer tipo de tela. | `RefreshUniversal(child: Container(), onRefresh: ...)` |
| **DatePickerUniversal 🗓️** |Um date picker customizado baseado no showDatePicker do Flutter, com opção para incluir um botão de "Hoje" (addButtonToday = true). | `await DatePickerUniversal.show(context, addButtonToday: true)` |
| *(Em breve)* **ContainerBorderComponent** | Um container mais robusto com algumas facilidades de estilização. | - |
| *(Em breve)* **CheckboxCustom** | Checkbox que adiciona o texto com ação de seleção. | - |

