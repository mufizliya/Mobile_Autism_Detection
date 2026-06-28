import 'package:flutter/material.dart';

import '../modules/child_info/child_info_screen.dart';

class AutismDetectionReplicaApp extends StatelessWidget {
  const AutismDetectionReplicaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Autism Detection Mobile Replica',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
      ),
      home: const ChildInfoScreen(),
    );
  }
}