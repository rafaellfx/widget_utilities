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
