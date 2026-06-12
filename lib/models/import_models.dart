import 'ledger_entry.dart';

enum ImportMethod {
  file,
  paste,
  share,
  drop;

  String get label => switch (this) {
    ImportMethod.file => '文件',
    ImportMethod.paste => '粘贴',
    ImportMethod.share => '分享打开',
    ImportMethod.drop => '拖入',
  };
}

class ImportCandidate {
  const ImportCandidate({
    required this.entry,
    required this.rowNumber,
    required this.rawSummary,
    required this.isDuplicate,
    this.error,
  });

  final LedgerEntry entry;
  final int rowNumber;
  final String rawSummary;
  final bool isDuplicate;
  final String? error;

  bool get isValid => error == null && !isDuplicate;
}

class ImportPreview {
  const ImportPreview({
    required this.source,
    required this.method,
    required this.candidates,
    required this.createdAt,
    this.label,
  });

  final String source;
  final ImportMethod method;
  final List<ImportCandidate> candidates;
  final DateTime createdAt;
  final String? label;

  int get validCount =>
      candidates.where((candidate) => candidate.isValid).length;
  int get duplicateCount =>
      candidates.where((candidate) => candidate.isDuplicate).length;
  int get errorCount =>
      candidates.where((candidate) => candidate.error != null).length;
  bool get hasImportableRows => validCount > 0;
}
