## 0.1.8

* Foco dinâmico de texto no `ScannerTextInput` (estilo Live Text do iOS): os colchetes amarelos passam a grudar na palavra mais próxima do centro da mira e a acompanham conforme a câmera se move.
* A palavra focada vira o texto candidato exibido no preview e inserido ao tocar em "Inserir" (substitui a seleção pela linha mais longa no modo texto).
* Quando não há texto no quadro, o overlay volta ao quadro central estático como guia de enquadramento.

## 0.1.7

* Adiciona overlay de mira (foco) ao painel do `ScannerTextInput`: colchetes amarelos nos cantos da área de leitura para guiar o enquadramento da câmera.
* O overlay aparece apenas quando a câmera está inicializada e não interfere nas interações do painel.

## 0.1.6

* Adiciona suporte opcional a leitura de **códigos de barra 1D/2D e QR Code** em `ScannerTextInput` via novo enum `ScannerMode` (`text`, `barcode`, `textAndBarcode`).
* Novo parâmetro `autoConfirmBarcode` (padrão `true`) fecha o modal automaticamente quando um código é reconhecido.
* Mantém compatibilidade total com a API anterior (modo padrão segue OCR de texto).
* Ajusta `platforms:` do `pubspec.yaml` para refletir o suporte real (Android, iOS, web stub) — remove declarações de plataformas desktop que não têm plugin nativo.

## 0.1.5

* Adiciona `ScannerTextInput`, utilitário para integrar OCR em `TextField`/`TextFormField` via menu de contexto ou abertura direta do scanner.
* Inclui painel mobile com câmera e reconhecimento de texto via ML Kit para Android e iOS.
* Documenta permissões de câmera necessárias nos apps consumidores.

## 0.1.4

* Corrige o barrel `lib/widget_utilities.dart` para exportar `DatePickerUniversal`, que estava implementado mas inacessível na versão anterior.
* Atualiza o exemplo (`example/`) com demonstração combinada de `RefreshUniversal` e `DatePickerUniversal`.
* Pequenos ajustes de documentação no `README.md`.

## 0.1.3

* Adiciona o widget `DatePickerUniversal` — date picker customizado baseado no `showDatePicker` do Flutter, com suporte ao parâmetro opcional `addButtonToday` que exibe um botão "Hoje" no rodapé do diálogo.

## 0.1.0

* Release inicial do package.
* Adiciona `RefreshUniversal` — wrapper de pull-to-refresh que funciona com qualquer widget, scrollable ou não.
