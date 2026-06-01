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
  widget_utilities: ^0.1.12
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

- `text` — OCR de texto (padrão). O foco prende a **frase (linha de texto) sob
  a mira** e a escreve no campo **ao vivo**, em tempo real, conforme você
  enquadra. Não há etapa de confirmação: encerre tocando em "Concluir" ou
  fechando o painel — o último valor reconhecido permanece no campo.
- `barcode` — apenas códigos de barra e QR Code; ao reconhecer, o modal fecha
  automaticamente.
- `textAndBarcode` — ambos no mesmo painel; quando o usuário aponta para um
  código, ele tem prioridade sobre o texto.

> 💡 Como o modo texto preenche o campo em tempo real, `onTextScanned` é
> chamado a cada leitura estável (não apenas uma vez). Use-o para atribuir o
> valor direto ao `controller`, como nos exemplos abaixo.

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

### Requisitos e configuração

O scanner usa a câmera e o **Google ML Kit** (OCR de texto e leitura de
códigos). Essas dependências nativas (`camera`, `google_mlkit_text_recognition`,
`google_mlkit_barcode_scanning`) já acompanham o package — você **não** precisa
declará-las no app. Basta configurar permissões e versões mínimas.

#### Android

1. Permissão de câmera em `android/app/src/main/AndroidManifest.xml`, dentro da
   tag `<manifest>`:

   ```xml
   <uses-permission android:name="android.permission.CAMERA" />
   ```

2. **(Recomendado)** Pré-baixe os modelos do ML Kit na instalação do app, para o
   primeiro uso não esperar o download. Adicione dentro de `<application>`:

   ```xml
   <meta-data
       android:name="com.google.mlkit.vision.DEPENDENCIES"
       android:value="ocr,barcode" />
   ```

   Use `ocr` se só lê texto, `barcode` se só lê códigos, ou `ocr,barcode` para
   ambos.

3. `minSdkVersion` **21** ou superior em `android/app/build.gradle`.

#### iOS

1. Descrição de uso da câmera em `ios/Runner/Info.plist`:

   ```xml
   <key>NSCameraUsageDescription</key>
   <string>Este app usa a câmera para reconhecer textos.</string>
   ```

2. Deployment target **15.5** ou superior (exigência do ML Kit), Xcode 15.3+ e
   Swift 5. No `Podfile`, defina `platform :ios, '15.5'` e mantenha os pods com
   `IPHONEOS_DEPLOYMENT_TARGET = '15.5'`.

#### Plataformas suportadas

| Plataforma     | Câmera / OCR | Código de barras / QR |
|----------------|:------------:|:---------------------:|
| Android        |      ✅      |          ✅           |
| iOS            |      ✅      |          ✅           |
| Web / Desktop  |      —       |           —           |

Em web/desktop a API continua disponível para não quebrar o build, mas apenas
exibe uma mensagem amigável e não altera o campo.



## 🧱 Widgets disponíveis

| Widget | Descrição | Exemplo |
|--------|------------|----------|
| **RefreshUniversal** | Widget de *pull-to-refresh* que funciona com ou sem scroll. Ideal para qualquer tipo de tela. | `RefreshUniversal(child: Container(), onRefresh: ...)` |
| **DatePickerUniversal 🗓️** |Um date picker customizado baseado no showDatePicker do Flutter, com opção para incluir um botão de "Hoje" (addButtonToday = true). | `await DatePickerUniversal.show(context, addButtonToday: true)` |
| **ScannerTextInput 📷** | Utilitário mobile para abrir scanner de texto e/ou códigos de barra/QR Code via menu de contexto ou botão em campos de texto. | `ScannerTextInput.contextMenuBuilder(mode: ScannerMode.textAndBarcode, onTextScanned: ...)` |
| *(Em breve)* **ContainerBorderComponent** | Um container mais robusto com algumas facilidades de estilização. | - |
| *(Em breve)* **CheckboxCustom** | Checkbox que adiciona o texto com ação de seleção. | - |
