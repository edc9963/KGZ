import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_store.dart';

final appStoreProvider = ChangeNotifierProvider<AppStore>(
  (ref) => throw UnimplementedError('AppStore must be overridden at startup'),
);
