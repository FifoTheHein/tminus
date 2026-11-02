import 'package:flutter/material.dart';

/// Placeholder: the real profile editor replaces this file. A null
/// [profileId] makes a new profile.
class ProfileEditorScreen extends StatelessWidget {
  const ProfileEditorScreen({super.key, this.profileId});

  final String? profileId;

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text('Profile')));
}
