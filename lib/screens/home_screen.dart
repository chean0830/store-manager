import 'package:flutter/material.dart';

import '../logic/sales_stats.dart';
import '../models/order.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeData {
  const _HomeData({
    required this.today,
    required this.yesterday,
    required this.week,
    required this.insights,
  });

  final SalesSummary today;

  /// 어제 같은 시각까지의 실적. 오늘 진행 중인 매출과 공정하게 비교하기 위해 쓴다.
  final SalesSummary yesterday;
  final List<DailySales> week;
  final List<Insight> insights;
}

class _HomeScreenState extends State<HomeScreen> {
  int? _revision;
  late Future<_HomeData> _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    if (_revision != state.revision) {
      _revision = state.revision;
      _future = _load(state);
    }
  }

  Future<_HomeData> _load(AppState state) async {
    final now = DateTime.now();
    final today = startOfDay(now);
    final weekStart = DateTime(today.year, today.month, today.day - 6);
    final orders = await state.db.orders(
      from: DateTime(today.year, today.month, today.day - 13),
      to: DateTime(today.year, today.month, today.day + 1),
    );

    bool between(SalesOrder o, DateTime from, DateTime to) =>
        !o.createdAt.isBefore(from) && o.createdAt.isBefore(to);
    final yesterday = DateTime(today.year, today.month, today.day - 1);

    return _HomeData(
      today: SalesSummary.of(orders.where((o) => !o.createdAt.isBefore(today))),
      yesterday: SalesSummary.of(
        orders.where(
          (o) => between(o, yesterday, now.subtract(const Duration(days: 1))),
        ),
      ),
      week: dailySales(orders, from: weekStart, days: 7),
      insights: buildInsights(
        current: orders.where((o) => !o.createdAt.isBefore(weekStart)).toList(),
        previous: orders.where((o) => o.createdAt.isBefore(weekStart)).toList(),
        products: state.products,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final lowStock = state.products.where((p) => p.isLowStock).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('매장 매니저')),
      body: FutureBuilder<_HomeData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyHint(
              icon: Icons.error_outline,
              message: '불러오지 못했어요\n${snapshot.error}',
            );
          }
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final (revenueCaption, revenueColor) = changeCaption(
            changeRate(data.today.revenue, data.yesterday.revenue),
            '어제 이 시간',
          );
          final (orderCaption, orderColor) = changeCaption(
            changeRate(data.today.orderCount, data.yesterday.orderCount),
            '어제 이 시간',
          );

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                fullDate(DateTime.now()),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              StatGrid(
                children: [
                  StatCard(
                    icon: Icons.payments_outlined,
                    label: '오늘 매출',
                    value: won(data.today.revenue),
                    caption: revenueCaption,
                    captionColor: revenueColor,
                  ),
                  StatCard(
                    icon: Icons.savings_outlined,
                    label: '오늘 순이익',
                    value: won(data.today.profit),
                    caption: '이익률 ${percent(data.today.profitRate)}',
                  ),
                  StatCard(
                    icon: Icons.receipt_outlined,
                    label: '주문 수',
                    value: '${data.today.orderCount}건',
                    caption: orderCaption,
                    captionColor: orderColor,
                  ),
                  StatCard(
                    icon: Icons.person_outline,
                    label: '객단가',
                    value: won(data.today.averageOrderValue),
                    caption: '판매 ${data.today.itemsSold}개',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SectionCard(
                title: '최근 7일 매출',
                child: SimpleBarChart(
                  values: [for (final d in data.week) d.revenue.toDouble()],
                  labelOf: (i) => weekday(data.week[i].day),
                  tooltipOf: (v) => won(v.round()),
                ),
              ),
              SectionCard(
                title: '재고 부족 ${lowStock.length}건',
                child: lowStock.isEmpty
                    ? const Text('모든 상품의 재고가 충분해요.')
                    : Column(
                        children: [
                          for (final product in lowStock)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                Icons.inventory_2_outlined,
                                color: theme.colorScheme.error,
                              ),
                              title: Text(product.name),
                              subtitle: Text(
                                '알림 기준 ${product.lowStockThreshold}개',
                              ),
                              trailing: Text(
                                '남은 ${product.stock}개',
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          Text(
                            '상품 탭에서 입고 처리할 수 있어요.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
              ),
              SectionCard(
                title: '이번 주 매출 향상 팁',
                child: InsightList(insights: data.insights),
              ),
            ],
          );
        },
      ),
    );
  }
}
