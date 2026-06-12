import 'package:flutter_test/flutter_test.dart';
import 'package:lizhang/services/money.dart';

void main() {
  test('parses and formats money with cents precision', () {
    expect(parseMoneyToCents('¥12.34'), 1234);
    expect(parseMoneyToCents('-8.00'), -800);
    expect(formatMoney(1234), '¥12.34');
  });

  test('maps entry type to signed amount', () {
    expect(signedAmountForType(EntryType.income, 100), 100);
    expect(signedAmountForType(EntryType.expense, 100), -100);
  });
}
