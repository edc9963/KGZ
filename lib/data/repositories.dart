import 'dart:async';
import 'dart:typed_data';

import '../domain/models.dart';
import 'ocr_models.dart';

abstract interface class AuthRepository {
  String? get currentUserId;
  String? get currentUserDisplayName;
  bool get isSignedIn;
  Stream<bool> get authStateChanges;
  Future<void> signInWithLine({String? returnPath});
  Future<void> signOut();
}

abstract interface class FinanceRepository {
  Future<FinanceSnapshot> load();
  Future<SaveResult> save(AppData data);
  Future<SaveResult> clear();
  Future<FinanceSnapshot> resolveInitialMigration(
    InitialMigrationAction action,
  );
}

class MarketInstrument {
  const MarketInstrument({
    required this.market,
    required this.symbol,
    required this.name,
    required this.type,
    required this.currency,
    required this.closePriceMinor,
    required this.quoteDate,
  });

  final String market;
  final String symbol;
  final String name;
  final String type;
  final CurrencyCode currency;
  final int closePriceMinor;
  final DateTime? quoteDate;

  factory MarketInstrument.fromJson(Json json) => MarketInstrument(
    market: json['market'] as String? ?? 'TWSE',
    symbol: json['symbol'] as String,
    name: json['name'] as String,
    type: json['type'] as String,
    currency: json['currency'] as String? ?? 'TWD',
    closePriceMinor: (json['closePriceMinor'] as num?)?.toInt() ?? 0,
    quoteDate: json['quoteDate'] == null
        ? null
        : DateTime.parse(json['quoteDate'] as String),
  );

  Json toJson() => {
    'market': market,
    'symbol': symbol,
    'name': name,
    'type': type,
    'currency': currency,
    'closePriceMinor': closePriceMinor,
    'quoteDate': quoteDate?.toIso8601String(),
  };
}

abstract interface class MarketDataRepository {
  Future<List<MarketInstrument>> loadCatalog({bool forceRefresh = false});
  Future<List<MarketInstrument>> search(String query);
  Future<List<MarketInstrument>> quotes(Iterable<String> symbols);
}

class PublicCollectionDetails {
  const PublicCollectionDetails({
    required this.orderName,
    required this.orderDate,
    required this.orderNote,
    required this.participantName,
    required this.itemName,
    required this.itemAmountMinor,
    required this.sharedFeeMinor,
    required this.discountMinor,
    required this.dueMinor,
    required this.status,
    required this.collectionMethod,
    required this.bankQrData,
    required this.bankAccountInfo,
  });

  final String orderName;
  final DateTime orderDate;
  final String orderNote;
  final String participantName;
  final String itemName;
  final int itemAmountMinor;
  final int sharedFeeMinor;
  final int discountMinor;
  final int dueMinor;
  final CollectionStatus status;
  final String collectionMethod;
  final String bankQrData;
  final String bankAccountInfo;

  factory PublicCollectionDetails.fromJson(Json json) =>
      PublicCollectionDetails(
        orderName: json['orderName'] as String,
        orderDate: DateTime.parse(json['orderDate'] as String),
        orderNote: json['orderNote'] as String? ?? '',
        participantName: json['participantName'] as String,
        itemName: json['itemName'] as String,
        itemAmountMinor: (json['itemAmountMinor'] as num).toInt(),
        sharedFeeMinor: (json['sharedFeeMinor'] as num).toInt(),
        discountMinor: (json['discountMinor'] as num).toInt(),
        dueMinor: (json['dueMinor'] as num).toInt(),
        status: CollectionStatus.values.byName(
          json['collectionStatus'] as String,
        ),
        collectionMethod: json['collectionMethod'] as String,
        bankQrData: json['bankQrData'] as String? ?? '',
        bankAccountInfo: json['bankAccountInfo'] as String? ?? '',
      );
}

abstract interface class PublicCollectionRepository {
  Future<PublicCollectionDetails?> load(String token);
  Future<void> markPending(String token);
}

enum InitialMigrationAction { uploadLocal, merge, useCloud, replaceCloud }

class FinanceSnapshot {
  const FinanceSnapshot({
    required this.data,
    this.revision = 0,
    this.updatedAt,
    this.cloudExists = false,
    this.isOffline = false,
    this.localCandidate,
  });

  final AppData data;
  final int revision;
  final DateTime? updatedAt;
  final bool cloudExists;
  final bool isOffline;
  final AppData? localCandidate;

  bool get needsInitialMigration => localCandidate != null && !isOffline;
}

class SaveResult {
  const SaveResult({required this.revision, required this.updatedAt});

  final int revision;
  final DateTime updatedAt;
}

class FinanceConflictException implements Exception {
  const FinanceConflictException(this.serverRevision);
  final int serverRevision;

  @override
  String toString() => '雲端資料已在其他裝置更新，請重新載入';
}

class FinanceConnectionException implements Exception {
  const FinanceConnectionException([this.cause]);
  final Object? cause;

  @override
  String toString() => '目前無法連線到雲端，請稍後再試';
}

abstract interface class LocalPersistence {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

abstract interface class CsvExportService {
  Future<void> export(String fileName, List<List<Object?>> rows);
}

class ImportImage {
  const ImportImage({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;
}

class ImportedParticipant {
  const ImportedParticipant({
    required this.name,
    required this.isSelf,
    required this.itemName,
    required this.itemAmountMinor,
    this.nameConfidence = 1,
    this.itemConfidence = 1,
    this.amountConfidence = 1,
  });

  final String name;
  final bool isSelf;
  final String itemName;
  final int itemAmountMinor;
  final double nameConfidence;
  final double itemConfidence;
  final double amountConfidence;

  factory ImportedParticipant.fromJson(Json json) => ImportedParticipant(
    name: json['name'] as String,
    isSelf: json['isSelf'] as bool,
    itemName: (json['items'] as List)
        .map((item) {
          final value = item as Json;
          final quantity = value['quantity'] as int? ?? 1;
          return quantity == 1
              ? value['name'] as String
              : '${value['name']} ×$quantity';
        })
        .join('、'),
    itemAmountMinor: json['itemAmountMinor'] as int,
    nameConfidence: (json['nameConfidence'] as num?)?.toDouble() ?? 1,
    itemConfidence: (json['itemConfidence'] as num?)?.toDouble() ?? 1,
    amountConfidence: (json['amountConfidence'] as num?)?.toDouble() ?? 1,
  );
}

class ImportedOrder {
  const ImportedOrder({
    required this.name,
    required this.platform,
    required this.date,
    required this.totalMinor,
    required this.deliveryFeeMinor,
    required this.serviceFeeMinor,
    required this.discountMinor,
    required this.paymentLastFour,
    required this.participants,
    required this.warnings,
    required this.reconciliationDifferenceMinor,
    this.fieldConfidence = const {},
  });

  final String name;
  final String platform;
  final DateTime date;
  final int totalMinor;
  final int deliveryFeeMinor;
  final int serviceFeeMinor;
  final int discountMinor;
  final String? paymentLastFour;
  final List<ImportedParticipant> participants;
  final List<String> warnings;
  final int reconciliationDifferenceMinor;
  final Map<String, double> fieldConfidence;

  bool isLowConfidence(String field) => (fieldConfidence[field] ?? 1) < 0.75;

  factory ImportedOrder.fromJson(Json json) => ImportedOrder(
    name: json['name'] as String,
    platform: json['platform'] as String,
    date: DateTime.parse(json['date'] as String),
    totalMinor: json['totalMinor'] as int,
    deliveryFeeMinor: json['deliveryFeeMinor'] as int,
    serviceFeeMinor: json['serviceFeeMinor'] as int,
    discountMinor: json['discountMinor'] as int,
    paymentLastFour: json['paymentLastFour'] as String?,
    participants: (json['participants'] as List)
        .map((item) => ImportedParticipant.fromJson(item as Json))
        .toList(),
    warnings: List<String>.from(json['warnings'] as List? ?? const []),
    reconciliationDifferenceMinor:
        json['reconciliationDifferenceMinor'] as int? ?? 0,
    fieldConfidence: {
      for (final entry in (json['fieldConfidence'] as Map? ?? const {}).entries)
        entry.key.toString(): (entry.value as num).toDouble(),
    },
  );
}

abstract interface class OrderImportRepository {
  Future<ImportedOrder> importUberEats(
    List<ImportImage> images, {
    OcrProgressCallback? onProgress,
  });
}
