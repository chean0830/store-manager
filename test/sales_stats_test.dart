import 'package:flutter_test/flutter_test.dart';
import 'package:store_manager/logic/sales_stats.dart';
import 'package:store_manager/models/order.dart';
import 'package:store_manager/models/product.dart';

OrderItem item(int productId, String name, int price, int cost, int qty) =>
    OrderItem(
      productId: productId,
      productName: name,
      unitPrice: price,
      unitCost: cost,
      quantity: qty,
    );

SalesOrder order(
  int id,
  DateTime at,
  List<OrderItem> items, {
  PaymentMethod payment = PaymentMethod.card,
  OrderStatus status = OrderStatus.paid,
}) => SalesOrder(
  id: id,
  createdAt: at,
  payment: payment,
  status: status,
  items: items,
);

Product product(int id, String name, {int stock = 50, int low = 10}) => Product(
  id: id,
  name: name,
  category: '커피',
  price: 4500,
  cost: 800,
  stock: stock,
  lowStockThreshold: low,
);

void main() {
  final americano = item(1, '아메리카노', 4500, 800, 2);
  final latte = item(2, '카페라떼', 5000, 1200, 1);
  final cake = item(3, '치즈케이크', 6500, 2800, 1);

  final orders = [
    order(1, DateTime(2026, 11, 9, 9, 10), [americano]),
    order(2, DateTime(2026, 11, 9, 12, 30), [
      latte,
      cake,
    ], payment: PaymentMethod.cash),
    order(3, DateTime(2026, 11, 10, 12, 5), [americano, latte]),
    order(4, DateTime(2026, 11, 10, 12, 40), [
      cake,
    ], status: OrderStatus.refunded),
  ];

  group('SalesSummary', () {
    test('환불된 주문은 매출에서 뺀다', () {
      final summary = SalesSummary.of(orders);
      // 9000 + 11500 + 14000
      expect(summary.revenue, 34500);
      expect(summary.cost, 1600 + 4000 + 2800);
      expect(summary.profit, 34500 - 8400);
      expect(summary.orderCount, 3);
      expect(summary.itemsSold, 2 + 2 + 3);
      expect(summary.averageOrderValue, 11500);
    });

    test('주문이 없으면 0으로 나누지 않는다', () {
      const empty = SalesSummary();
      expect(empty.averageOrderValue, 0);
      expect(empty.profitRate, 0);
    });
  });

  test('dailySales는 주문이 없는 날도 0으로 채운다', () {
    final daily = dailySales(orders, from: DateTime(2026, 11, 8), days: 3);
    expect([for (final d in daily) d.revenue], [0, 20500, 14000]);
    expect([for (final d in daily) d.orderCount], [0, 2, 1]);
    expect(daily.last.day, DateTime(2026, 11, 10));
  });

  test('dailySales는 월이 바뀌어도 날짜를 맞게 센다', () {
    final daily = dailySales(
      [
        order(1, DateTime(2026, 12, 1, 10), [latte]),
      ],
      from: DateTime(2026, 11, 29),
      days: 3,
    );
    expect([for (final d in daily) d.revenue], [0, 0, 5000]);
  });

  test('hourlyRevenue는 시간대별로 나눈다', () {
    final hourly = hourlyRevenue(orders);
    expect(hourly.length, 24);
    expect(hourly[9], 9000);
    expect(hourly[12], 11500 + 14000);
  });

  test('productRanking은 매출이 큰 순서로 정렬한다', () {
    final ranking = productRanking(orders);
    expect([for (final r in ranking) r.name], ['아메리카노', '카페라떼', '치즈케이크']);
    expect(ranking.first.quantity, 4);
    expect(ranking.first.profit, 4 * (4500 - 800));
    // 환불된 케이크는 빠지고 결제된 1개만 남는다
    expect(ranking.last.quantity, 1);
  });

  test('paymentBreakdown은 결제 수단별 매출을 모은다', () {
    final payments = paymentBreakdown(orders);
    expect(payments[PaymentMethod.card], 9000 + 14000);
    expect(payments[PaymentMethod.cash], 11500);
    expect(payments[PaymentMethod.transfer], 0);
  });

  test('changeRate는 비교 기록이 없으면 null', () {
    expect(changeRate(100, 0), isNull);
    expect(changeRate(150, 100), closeTo(0.5, 1e-9));
    expect(changeRate(50, 100), closeTo(-0.5, 1e-9));
  });

  group('buildInsights', () {
    test('매출 증감, 피크 시간, 이익 1위, 판매 부진, 재고 부족을 알려준다', () {
      final insights = buildInsights(
        current: orders.where((o) => o.createdAt.day == 10).toList(),
        previous: orders.where((o) => o.createdAt.day == 9).toList(),
        products: [
          product(1, '아메리카노'),
          product(2, '카페라떼'),
          product(3, '치즈케이크', stock: 3, low: 5),
        ],
      );
      final kinds = [for (final i in insights) i.kind];
      expect(kinds, [
        InsightKind.trendDown,
        InsightKind.peakHour,
        InsightKind.bestProduct,
        InsightKind.slowProduct,
        InsightKind.lowStock,
      ]);
      expect(insights[1].message, contains('12시~13시'));
      expect(insights[2].message, contains('아메리카노'));
      expect(insights[3].message, contains('치즈케이크'));
    });

    test('판매 기록이 없으면 재고 알림만 남는다', () {
      final insights = buildInsights(
        current: const [],
        previous: const [],
        products: [product(1, '아메리카노', stock: 0)],
      );
      expect([for (final i in insights) i.kind], [InsightKind.lowStock]);
    });
  });
}
