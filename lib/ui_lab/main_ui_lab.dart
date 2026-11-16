// UI library comparison lab — NOT part of the production app.
//
// Run with:
//   flutter run -d chrome -t lib/ui_lab/main_ui_lab.dart
//
// Renders the same "支出分類" screen twice, once with shadcn_ui and once with
// forui. Each library gets its own app root (ShadApp vs MaterialApp + FTheme)
// because both expect their theme above the Navigator so dialogs inherit it.
import 'package:flutter/material.dart';

import 'forui_demo.dart';
import 'shadcn_demo.dart';

void main() => runApp(const UiLabRoot());

enum UiLibrary { shadcn, forui }

class UiLabRoot extends StatefulWidget {
  const UiLabRoot({super.key});

  @override
  State<UiLabRoot> createState() => _UiLabRootState();
}

class _UiLabRootState extends State<UiLabRoot> {
  UiLibrary library = UiLibrary.forui;
  bool dark = false;

  void _switchLibrary() => setState(
    () => library = library == UiLibrary.shadcn ? UiLibrary.forui : UiLibrary.shadcn,
  );

  void _toggleTheme() => setState(() => dark = !dark);

  @override
  Widget build(BuildContext context) => switch (library) {
    UiLibrary.shadcn => ShadcnDemoApp(
      key: const ValueKey('shadcn'),
      dark: dark,
      onToggleTheme: _toggleTheme,
      onSwitchLibrary: _switchLibrary,
    ),
    UiLibrary.forui => ForuiDemoApp(
      key: const ValueKey('forui'),
      dark: dark,
      onToggleTheme: _toggleTheme,
      onSwitchLibrary: _switchLibrary,
    ),
  };
}
