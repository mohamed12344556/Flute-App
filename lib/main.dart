import 'package:flaut_app/flute_trainer_%D9%90auto_detecte_screen.dart';
import 'package:flaut_app/flute_trainer_screen.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flute Learning App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      // home: FluteTrainerScreen(),
      home: FluteTrainerAutoScreen(),
      // home: FluteTrainerTestScreen(),
    );
  }
}
