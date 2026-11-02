import 'package:supabase_flutter/supabase_flutter.dart';

import 'repositories.dart';

class SupabaseCaptureSetupRepository implements CaptureSetupRepository {
  SupabaseCaptureSetupRepository(this._client, String supabaseUrl)
    : endpoints = CaptureEndpoints(
        '${supabaseUrl.replaceFirst(RegExp(r'/$'), '')}/functions/v1',
      );

  final SupabaseClient _client;

  @override
  final CaptureEndpoints endpoints;

  @override
  Future<CaptureSetupStatus> loadStatus() async {
    final raw = await _client.rpc('capture_web_status');
    final response = Map<String, dynamic>.from(raw as Map);
    if (response['status'] != 'ok') throw StateError('無法讀取自動記帳狀態');
    return CaptureSetupStatus.fromJson(response);
  }

  @override
  Future<String> issueToken() async {
    final raw = await _client.rpc('capture_web_issue_token');
    final response = Map<String, dynamic>.from(raw as Map);
    final token = response['token'];
    if (response['status'] != 'issued' || token is! String) {
      throw StateError('無法產生金鑰');
    }
    return token;
  }
}
