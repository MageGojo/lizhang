import '../services/money.dart';

class BalanceAnchor {
  const BalanceAnchor({
    required this.amountCents,
    required this.asOf,
    required this.updatedAt,
  });

  final int amountCents;
  final DateTime asOf;
  final DateTime updatedAt;

  factory BalanceAnchor.fromMap(Map<String, Object?> map) {
    return BalanceAnchor(
      amountCents: map['amount_cents'] as int,
      asOf: DateTime.fromMillisecondsSinceEpoch(map['as_of_ms'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        map['updated_at_ms'] as int,
      ),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': 1,
      'amount_cents': amountCents,
      'as_of_ms': asOf.millisecondsSinceEpoch,
      'updated_at_ms': updatedAt.millisecondsSinceEpoch,
    };
  }
}

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.type,
    required this.amountCents,
    required this.occurredAt,
    required this.category,
    required this.merchant,
    required this.note,
    required this.source,
    required this.externalId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final int? id;
  final EntryType type;
  final int amountCents;
  final DateTime occurredAt;
  final String category;
  final String merchant;
  final String note;
  final String source;
  final String externalId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;
  int get signedAmountCents => signedAmountForType(type, amountCents);

  LedgerEntry copyWith({
    int? id,
    EntryType? type,
    int? amountCents,
    DateTime? occurredAt,
    String? category,
    String? merchant,
    String? note,
    String? source,
    String? externalId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return LedgerEntry(
      id: id ?? this.id,
      type: type ?? this.type,
      amountCents: amountCents ?? this.amountCents,
      occurredAt: occurredAt ?? this.occurredAt,
      category: category ?? this.category,
      merchant: merchant ?? this.merchant,
      note: note ?? this.note,
      source: source ?? this.source,
      externalId: externalId ?? this.externalId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    );
  }

  factory LedgerEntry.fromMap(Map<String, Object?> map) {
    return LedgerEntry(
      id: map['id'] as int?,
      type: EntryType.fromString(map['type'] as String),
      amountCents: map['amount_cents'] as int,
      occurredAt: DateTime.fromMillisecondsSinceEpoch(
        map['occurred_at_ms'] as int,
      ),
      category: map['category'] as String? ?? '',
      merchant: map['merchant'] as String? ?? '',
      note: map['note'] as String? ?? '',
      source: map['source'] as String? ?? 'manual',
      externalId: map['external_id'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['created_at_ms'] as int,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        map['updated_at_ms'] as int,
      ),
      deletedAt: map['deleted_at_ms'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['deleted_at_ms'] as int),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'type': type.name,
      'amount_cents': amountCents.abs(),
      'occurred_at_ms': occurredAt.millisecondsSinceEpoch,
      'category': category,
      'merchant': merchant,
      'note': note,
      'source': source,
      'external_id': externalId,
      'created_at_ms': createdAt.millisecondsSinceEpoch,
      'updated_at_ms': updatedAt.millisecondsSinceEpoch,
      'deleted_at_ms': deletedAt?.millisecondsSinceEpoch,
    };
  }
}

class DayArchive {
  const DayArchive({
    required this.day,
    required this.entries,
    required this.netCents,
    required this.incomeCents,
    required this.expenseCents,
  });

  final DateTime day;
  final List<LedgerEntry> entries;
  final int netCents;
  final int incomeCents;
  final int expenseCents;
}

class LedgerSnapshot {
  const LedgerSnapshot({
    required this.anchor,
    required this.entries,
    required this.archives,
    required this.realtimeBalanceCents,
    required this.totalIncomeCents,
    required this.totalExpenseCents,
  });

  final BalanceAnchor anchor;
  final List<LedgerEntry> entries;
  final List<DayArchive> archives;
  final int realtimeBalanceCents;
  final int totalIncomeCents;
  final int totalExpenseCents;

  List<LedgerEntry> get todayEntries {
    final now = DateTime.now();
    return entries.where((entry) {
      return entry.occurredAt.year == now.year &&
          entry.occurredAt.month == now.month &&
          entry.occurredAt.day == now.day;
    }).toList();
  }
}
