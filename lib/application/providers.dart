import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_store.dart';
import 'theme_mode_controller.dart';

final appStoreProvider = ChangeNotifierProvider<AppStore>(
  (ref) => throw UnimplementedError('AppStore must be overridden at startup'),
);

final themeModeControllerProvider = ChangeNotifierProvider<ThemeModeController>(
  (ref) =>
      throw UnimplementedError('ThemeModeController must be overridden at startup'),
);
