## 0.1.11

* O painel do `ScannerTextInput` agora é **redimensionável**: arrastando o puxador no topo, o usuário aumenta (até ~94% da tela) ou diminui (até a altura inicial) a área da câmera ao vivo. A altura inicial continua em ~34% da tela.

## 0.1.10

* O foco de texto do `ScannerTextInput` passa a prender a **frase (linha de texto) sob a mira** em vez do bloco/parágrafo inteiro, alinhando os colchetes amarelos exatamente sobre a linha enquadrada.
* No modo texto, a frase reconhecida **preenche o campo de origem ao vivo**, em tempo real: `onTextScanned` é disparado a cada leitura estável, sem etapa de confirmação.
* O botão "Inserir" dá lugar ao botão "Concluir", que apenas encerra o painel mantendo o último valor já entregue.
* O painel inferior agora exibe a frase reconhecida atual como feedback (útil quando o campo de origem fica coberto pelo modal).
* A escolha do foco reduz o viés por itens maiores para favorecer a linha realmente sob a mira.
* Corrige a orientação das bordas amarelas do foco: as caixas do ML Kit já vêm no espaço orientado, então a rotação extra de eixos foi removida — uma linha de texto horizontal agora desenha o quadro na horizontal (e não mais "em pé"). A correção vale para o desenho do overlay e para a seleção da linha central, com tratamento distinto de Android e iOS.

## 0.1.9

* Atualiza o painel do scanner conforme a referência do iCloud: bottom sheet compacto, botão "Inserir" pequeno centralizado e botão de fechar circular no topo direito.
* Ajuste visual do foco do `ScannerTextInput`: colchetes amarelos mais finos e com cantos levemente arredondados.
* O OCR passa a focar blocos de texto/parágrafos em vez de palavras isoladas.
* O foco de texto usa a união das linhas do bloco para alinhar melhor as bordas amarelas sobre a frase/parágrafo.
* Remove o preenchimento amarelo translúcido do item focado, mantendo apenas as bordas.
* O foco dinâmico passa a validar texto, tipo e proximidade da caixa antes de trocar de item, reduzindo saltos para palavras/códigos errados.
* A escolha do foco passa a favorecer blocos maiores e ignora mais ruídos pequenos no OCR.
* A troca de foco fica mais rápida, mantendo confirmação por frames consecutivos para evitar oscilação excessiva.
* O overlay mantém o último foco por alguns frames quando a leitura oscila, evitando piscadas durante o enquadramento.

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
