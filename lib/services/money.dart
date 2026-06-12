import 'package:intl/intl.dart';

final _currencyFormat = NumberFormat.currency(
  locale: 'zh_CN',
  symbol: '¥',
  decimalDigits: 2,
);

int parseMoneyToCents(String input) {
  final normalized = input
      .replaceAll(',', '')
      .replaceAll('¥', '')
      .replaceAll('￥', '')
      .replaceAll('元', '')
      .trim();
  if (normalized.isEmpty) {
    throw const FormatException('金额不能为空');
  }

  final negative = normalized.startsWith('-') || normalized.startsWith('支出');
  final match = RegExp(r'-?\d+(?:\.\d{1,2})?').firstMatch(normalized);
  if (match == null) {
    throw FormatException('无法识别金额：$input');
  }

  final value = double.parse(match.group(0)!);
  final cents = (value.abs() * 100).round();
  return negative ? -cents : cents;
}

String formatMoney(int cents, {bool withSign = false}) {
  final sign = withSign && cents > 0 ? '+' : '';
  return '$sign${_currencyFormat.format(cents / 100)}';
}

String formatPlainMoney(int cents) {
  return (cents / 100).toStringAsFixed(2);
}

int signedAmountForType(EntryType type, int cents) {
  final absolute = cents.abs();
  return type == EntryType.expense ? -absolute : absolute;
}

enum EntryType {
  income,
  expense;

  String get label => switch (this) {
    EntryType.income => '收入',
    EntryType.expense => '支出',
  };

  int get sign => switch (this) {
    EntryType.income => 1,
    EntryType.expense => -1,
  };

  static EntryType fromString(String value) {
    final normalized = value.toLowerCase();
    if (normalized.contains('收入') ||
        normalized.contains('入账') ||
        normalized.contains('收款') ||
        normalized.contains('income')) {
      return EntryType.income;
    }
    return EntryType.expense;
  }
}
