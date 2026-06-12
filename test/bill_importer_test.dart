import 'package:flutter_test/flutter_test.dart';
import 'package:lizhang/models/import_models.dart';
import 'package:lizhang/models/ledger_entry.dart';
import 'package:lizhang/services/bill_importer.dart';
import 'package:lizhang/services/ledger_database.dart';
import 'package:lizhang/services/money.dart';

void main() {
  test('parses common WeChat bill csv text', () async {
    final importer = BillImporter(_FakeLedgerDatabase());
    final preview = await importer.previewText('''
微信支付账单明细
交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,备注
2026-06-12 08:30:00,商户消费,早餐店,豆浆,支出,12.50,零钱,支付成功,wx-1,早餐
2026-06-12 18:00:00,二维码收款,朋友,转账,收入,100.00,零钱,支付成功,wx-2,还款
''');

    expect(preview.source, 'wechat');
    expect(preview.method, ImportMethod.paste);
    expect(preview.validCount, 2);
    expect(preview.candidates.first.entry.type, EntryType.expense);
    expect(preview.candidates.first.entry.amountCents, 1250);
    expect(preview.candidates.last.entry.type, EntryType.income);
  });

  test('parses common Alipay bill csv text', () async {
    final importer = BillImporter(_FakeLedgerDatabase());
    final preview = await importer.previewText('''
支付宝交易记录明细
交易号,商家订单号,交易创建时间,付款时间,类型,交易对方,商品名称,金额（元）,收/支,交易状态,备注
ali-1,order-1,2026-06-11 21:00:00,2026-06-11 21:01:00,即时到账,便利店,饮料,8.80,支出,交易成功,夜宵
''');

    expect(preview.source, 'alipay');
    expect(preview.validCount, 1);
    expect(preview.candidates.single.entry.merchant, '便利店');
    expect(
      preview.candidates.single.entry.amountCents,
      parseMoneyToCents('8.80'),
    );
  });
}

class _FakeLedgerDatabase extends LedgerDatabase {
  @override
  Future<bool> hasPotentialDuplicate(LedgerEntry entry) async => false;
}
