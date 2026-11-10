import '../models/order.dart';
import '../models/product.dart';
import '../utils/format.dart';

DateTime startOfDay(DateTime time) => DateTime(time.year, time.month, time.day);

/// 두 날짜 사이의 일수. 시각과 서머타임 영향을 받지 않도록 UTC 날짜로 비교한다.
int daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// 결제 완료된 주문만 집계한 요약. 환불된 주문은 매출에서 빠진다.
class SalesSummary {
  const SalesSummary({
    this.revenue = 0,
    this.cost = 0,
    this.orderCount = 0,
    this.itemsSold = 0,
  });

  factory SalesSummary.of(Iterable<SalesOrder> orders) {
    var revenue = 0, cost = 0, count = 0, items = 0;
    for (final order in orders.where((o) => o.isPaid)) {
      revenue += order.total;
      cost += order.costTotal;
      count++;
      items += order.itemCount;
    }
    return SalesSummary(
      revenue: revenue,
      cost: cost,
      orderCount: count,
      itemsSold: items,
    );
  }

  final int revenue;
  final int cost;
  final int orderCount;
  final int itemsSold;

  int get profit => revenue - cost;
  double get profitRate => revenue == 0 ? 0 : profit / revenue;
  int get averageOrderValue =>
      orderCount == 0 ? 0 : (revenue / orderCount).round();
}

class DailySales {
  const DailySales(this.day, this.revenue, this.orderCount);

  final DateTime day;
  final int revenue;
  final int orderCount;
}

/// [from]부터 [days]일 동안의 일별 매출. 주문이 없는 날도 0으로 채운다.
List<DailySales> dailySales(
  Iterable<SalesOrder> orders, {
  required DateTime from,
  required int days,
}) {
  final revenue = List.filled(days, 0);
  final counts = List.filled(days, 0);
  for (final order in orders.where((o) => o.isPaid)) {
    final index = daysBetween(from, order.createdAt);
    if (index < 0 || index >= days) continue;
    revenue[index] += order.total;
    counts[index]++;
  }
  return [
    for (var i = 0; i < days; i++)
      DailySales(
        DateTime(from.year, from.month, from.day + i),
        revenue[i],
        counts[i],
      ),
  ];
}

/// 0시~23시 시간대별 매출.
List<int> hourlyRevenue(Iterable<SalesOrder> orders) {
  final revenue = List.filled(24, 0);
  for (final order in orders.where((o) => o.isPaid)) {
    revenue[order.createdAt.hour] += order.total;
  }
  return revenue;
}

class ProductSales {
  ProductSales(this.productId, this.name);

  final int productId;
  String name;
  int quantity = 0;
  int revenue = 0;
  int profit = 0;
}

/// 상품별 판매 실적을 매출이 큰 순서로 정렬한다.
List<ProductSales> productRanking(Iterable<SalesOrder> orders) {
  final byProduct = <int, ProductSales>{};
  for (final order in orders.where((o) => o.isPaid)) {
    for (final item in order.items) {
      final sales = byProduct.putIfAbsent(
        item.productId,
        () => ProductSales(item.productId, item.productName),
      );
      sales
        ..quantity += item.quantity
        ..revenue += item.subtotal
        ..profit += item.subtotal - item.costTotal;
    }
  }
  return byProduct.values.toList()
    ..sort((a, b) => b.revenue.compareTo(a.revenue));
}

Map<PaymentMethod, int> paymentBreakdown(Iterable<SalesOrder> orders) {
  final totals = {for (final method in PaymentMethod.values) method: 0};
  for (final order in orders.where((o) => o.isPaid)) {
    totals[order.payment] = totals[order.payment]! + order.total;
  }
  return totals;
}

/// 직전 값 대비 증감률. 비교할 기록이 없으면 null.
double? changeRate(int current, int previous) =>
    previous == 0 ? null : (current - previous) / previous;

enum InsightKind {
  trendUp,
  trendDown,
  peakHour,
  bestProduct,
  slowProduct,
  lowStock,
}

class Insight {
  const Insight(this.kind, this.message);

  final InsightKind kind;
  final String message;
}

/// 판매 기록을 보고 매출을 늘리거나 일을 줄일 수 있는 제안을 만든다.
List<Insight> buildInsights({
  required List<SalesOrder> current,
  required List<SalesOrder> previous,
  required List<Product> products,
}) {
  final insights = <Insight>[];

  final rate = changeRate(
    SalesSummary.of(current).revenue,
    SalesSummary.of(previous).revenue,
  );
  if (rate != null) {
    insights.add(
      rate >= 0
          ? Insight(
              InsightKind.trendUp,
              '직전 기간보다 매출이 ${percent(rate)} 늘었어요. 잘 팔리는 메뉴의 재고를 넉넉히 준비하세요.',
            )
          : Insight(
              InsightKind.trendDown,
              '직전 기간보다 매출이 ${percent(-rate)} 줄었어요. 판매가 적은 메뉴를 할인하거나 세트로 묶어 보세요.',
            ),
    );
  }

  final hourly = hourlyRevenue(current);
  var peak = 0;
  for (var hour = 1; hour < 24; hour++) {
    if (hourly[hour] > hourly[peak]) peak = hour;
  }
  if (hourly[peak] > 0) {
    insights.add(
      Insight(
        InsightKind.peakHour,
        '매출이 가장 많은 시간은 $peak시~${peak + 1}시예요. 그 전에 재료 손질과 인력 배치를 끝내 두세요.',
      ),
    );
  }

  final ranking = productRanking(current);
  if (ranking.isNotEmpty) {
    final best = ranking.reduce((a, b) => a.profit >= b.profit ? a : b);
    insights.add(
      Insight(
        InsightKind.bestProduct,
        '이익을 가장 많이 남긴 메뉴는 ${best.name}(${won(best.profit)})예요. 메뉴판 앞쪽에 두고 추천해 보세요.',
      ),
    );
  }

  if (products.length >= 2 && current.isNotEmpty) {
    final sold = {for (final s in ranking) s.productId: s.quantity};
    final slow = products.reduce(
      (a, b) => (sold[a.id] ?? 0) <= (sold[b.id] ?? 0) ? a : b,
    );
    insights.add(
      Insight(
        InsightKind.slowProduct,
        '${slow.name}은(는) 이 기간 ${sold[slow.id] ?? 0}개만 팔렸어요. 묶음 할인이나 메뉴 교체를 검토해 보세요.',
      ),
    );
  }

  final lowStock = products.where((p) => p.isLowStock).toList();
  if (lowStock.isNotEmpty) {
    final names = lowStock.take(3).map((p) => p.name).join(', ');
    final more = lowStock.length > 3 ? ' 외 ${lowStock.length - 3}개' : '';
    insights.add(
      Insight(
        InsightKind.lowStock,
        '재고가 부족한 상품이 ${lowStock.length}개 있어요($names$more). 품절되기 전에 입고하세요.',
      ),
    );
  }

  return insights;
}
