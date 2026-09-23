import '../../domain/models.dart';

/// Returns [transactions] with any existing entry whose id is [id] removed
/// and [transaction] appended.
///
/// Shared by the domain managers in this folder: several of them mirror a
/// user-facing record (an expense, an account transfer, a bill payment...)
/// into the unified [FinancialTransaction] ledger, and all of them replace
/// the mirrored entry the same way.
List<FinancialTransaction> replaceTransaction(
  List<FinancialTransaction> transactions,
  String id,
  FinancialTransaction transaction,
) => [
  for (final item in transactions)
    if (item.id != id) item,
  transaction,
];
