import 'package:supabase_flutter/supabase_flutter.dart';

import 'repositories.dart';

class SupabasePublicCollectionRepository implements PublicCollectionRepository {
  const SupabasePublicCollectionRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<PublicCollectionDetails?> load(String token) async {
    final raw = await _client.rpc(
      'load_public_collection',
      params: {'p_token': token},
    );
    final response = Map<String, dynamic>.from(raw as Map);
    if (response['status'] == 'not_found') return null;
    if (response['status'] != 'ok') {
      throw StateError('無法讀取收款資料');
    }
    return PublicCollectionDetails.fromJson(response);
  }

  @override
  Future<void> markPending(String token) async {
    final raw = await _client.rpc(
      'mark_public_collection_pending',
      params: {'p_token': token},
    );
    final response = Map<String, dynamic>.from(raw as Map);
    if (response['status'] != 'ok') {
      throw StateError('收款連結不存在或已失效');
    }
  }
}
