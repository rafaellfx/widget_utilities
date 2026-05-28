# 🧩 widget_utilities

**Coleção de widgets customizados reutilizáveis** para o dia a dia do desenvolvimento Flutter.  
O objetivo deste package é acelerar o desenvolvimento com componentes práticos, reutilizáveis e baseados em boas práticas.

---

## 🚀 Objetivo

O **`widget_utilities`** nasceu da necessidade de **evitar repetição de código** e **padronizar componentes visuais** usados em diversos projetos Flutter.  
Aqui você encontra widgets prontos para uso, leves e fáceis de integrar, com pequenos diferenciais opcionais.

---

## 📦 Instalação

Adicione a dependência no seu `pubspec.yaml`:
```yaml
dependencies:
  widget_utilities: ^0.1.8
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

## 🗓️ Exemplo simples com o DatePickerUniversal e RefreshUniversal


```dart
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

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<void> _onRefresh() async {
    await Future.delayed(const Duration(seconds: 2));
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

```

## 📷 Exemplo de uso ScannerTextInput

O `ScannerTextInput` adiciona uma opção de scanner ao menu de contexto de um
`TextField`/`TextFormField` e também pode ser aberto diretamente por um botão.
O painel suporta OCR de texto e/ou leitura de **códigos de barra 1D/2D e QR
Code** via ML Kit, conforme o `ScannerMode` escolhido. Disponível em Android e iOS.

Modos disponíveis (`ScannerMode`):

- `text` — apenas OCR de texto (padrão; comportamento legado).
- `barcode` — apenas códigos de barra e QR Code; ao reconhecer, o modal fecha
  automaticamente.
- `textAndBarcode` — ambos no mesmo painel; quando o usuário aponta para um
  código, ele tem prioridade sobre o texto.

```dart
import 'package:flutter/material.dart';
import 'package:widget_utilities/widget_utilities.dart';

class ScannerExample extends StatefulWidget {
  const ScannerExample({super.key});

  @override
  State<ScannerExample> createState() => _ScannerExampleState();
}

class _ScannerExampleState extends State<ScannerExample> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      contextMenuBuilder: ScannerTextInput.contextMenuBuilder(
        mode: ScannerMode.textAndBarcode,
        onTextScanned: (text) {
          _controller.text = text;
        },
      ),
      decoration: InputDecoration(
        labelText: 'Código',
        suffixIcon: IconButton(
          icon: const Icon(Icons.qr_code_scanner_outlined),
          onPressed: () => ScannerTextInput.open(
            context,
            mode: ScannerMode.barcode,
            onTextScanned: (text) {
              _controller.text = text;
            },
          ),
        ),
      ),
    );
  }
}
```

> 💡 Formatos suportados pela leitura de códigos: QR Code, Data Matrix,
> EAN-13, EAN-8, UPC-A, UPC-E, Code 128, Code 39, Code 93, Codabar, ITF, PDF417
> e Aztec.

### Permissões de câmera

No Android, adicione a permissão no `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

O ML Kit também exige `minSdkVersion` 21 ou superior no Android.

No iOS, adicione a descrição no `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Este app usa a câmera para reconhecer textos.</string>
```

No iOS, o ML Kit exige deployment target `15.5` ou superior, Xcode 15.3+
e Swift 5. Se o app usa `Podfile`, defina `platform :ios, '15.5'` e mantenha
os pods com `IPHONEOS_DEPLOYMENT_TARGET = '15.5'`.



## 🧱 Widgets disponíveis

| Widget | Descrição | Exemplo |
|--------|------------|----------|
| **RefreshUniversal** | Widget de *pull-to-refresh* que funciona com ou sem scroll. Ideal para qualquer tipo de tela. | `RefreshUniversal(child: Container(), onRefresh: ...)` |
| **DatePickerUniversal 🗓️** |Um date picker customizado baseado no showDatePicker do Flutter, com opção para incluir um botão de "Hoje" (addButtonToday = true). | `await DatePickerUniversal.show(context, addButtonToday: true)` |
| **ScannerTextInput 📷** | Utilitário mobile para abrir scanner de texto e/ou códigos de barra/QR Code via menu de contexto ou botão em campos de texto. | `ScannerTextInput.contextMenuBuilder(mode: ScannerMode.textAndBarcode, onTextScanned: ...)` |
| *(Em breve)* **ContainerBorderComponent** | Um container mais robusto com algumas facilidades de estilização. | - |
| *(Em breve)* **CheckboxCustom** | Checkbox que adiciona o texto com ação de seleção. | - |
