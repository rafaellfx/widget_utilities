import 'package:flutter/material.dart';
import 'package:widget_utilities/widget_utilities.dart';

void mai() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: Scaffold(
        appBar: AppBar(title: const Text('Widget Utilities')),
        body: RefreshUniversal(
          child: Container(),
          onRefresh: () async {},
        ),
      ),
    );
  }
}
