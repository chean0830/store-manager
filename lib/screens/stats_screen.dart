import 'package:flutter/material.dart';

import '../logic/sales_stats.dart';
import '../models/order.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

enum StatsPeriod {
  today('오늘', 1),
  week('7일', 7),
  month('30일', 30);

  const StatsPeriod(this.label, this.days);
  final String label;
  final int days;
}

class _StatsData {
  const _StatsData({
    required this.current,
    required this.previous,
    required this.daily,
    required this.hourly,
    required this.ranking,
    required this.payments,
    required this.insights,
  });

  final SalesSummary current;
  final SalesSummary previous;
  final List<DailySales> daily;
  final List<int> hourly;
  final List<ProductSales> ranking;
  final Map<PaymentMethod, int> payments;
  final List<Insight> insights;
}

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  StatsPeriod _period = StatsPeriod.week;
  int? _revision;
  late Future<_StatsData> _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    if (_revision != state.revision) {
      _revision = state.revision;
      _future = _load(state);
    }
  }

  void _changePeriod(StatsPeriod period) {
    setState(() {
      _period = period;
      _future = _load(AppScope.read(context));
    });
  }

  /// 선택한 기간과, 바로 앞의 같은 길이 기간을 함께 불러와 비교한다.
  /// 직전 기간은 지금 시각만큼만 잘라서 진행 중인 기간과 공정하게 비교한다.
  Future<_StatsData> _load(AppState state) async {
    final days = _period.days;
    final now = DateTime.now();
    final today = startOfDay(now);
    final from = DateTime(today.year, today.month, today.day - (days - 1));
    final previousFrom = DateTime(from.year, from.month, from.day - days);
    final previousUntil = now.subtract(Duration(days: days));

    final orders = await state.db.orders(
      from: previousFrom,
      to: DateTime(today.year, today.month, today.day + 1),
    );
    final current = orders.where((o) => !o.createdAt.isBefore(from)).toList();
    final previous = orders
        .where((o) => o.createdAt.isBefore(previousUntil))
        .toList();

    return _StatsData(
      current: SalesSummary.of(current),
      previous: SalesSummary.of(previous),
      daily: dailySales(current, from: from, days: days),
      hourly: hourlyRevenue(current),
      ranking: productRanking(current),
      payments: paymentBreakdown(current),
      insights: buildInsights(
        current: current,
        previous: previous,
        products: state.products,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('매출 통계')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<StatsPeriod>(
                segments: [
                  for (final p in StatsPeriod.values)
                    ButtonSegment(value: p, label: Text(p.label)),
                ],
                selected: {_period},
                onSelectionChanged: (s) => _changePeriod(s.first),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<_StatsData>(
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
                return _StatsBody(period: _period, data: data);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsBody extends StatelessWidget {
  const _StatsBody({required this.period, required this.data});

  final StatsPeriod period;
  final _StatsData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = data.current;
    final before = data.previous;
    final base = period == StatsPeriod.today ? '어제' : '직전 ${period.label}';

    final (revenueCaption, revenueColor) = changeCaption(
      changeRate(now.revenue, before.revenue),
      base,
    );
    final (orderCaption, orderColor) = changeCaption(
      changeRate(now.orderCount, before.orderCount),
      base,
    );
    final (aovCaption, aovColor) = changeCaption(
      changeRate(now.averageOrderValue, before.averageOrderValue),
      base,
    );

    // 매출이 있는 시간대만 잘라서 보여준다.
    final firstHour = data.hourly.indexWhere((v) => v > 0);
    final lastHour = data.hourly.lastIndexWhere((v) => v > 0);

    final paymentTotal = data.payments.values.fold(0, (a, b) => a + b);
    final topRevenue = data.ranking.isEmpty ? 0 : data.ranking.first.revenue;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        StatGrid(
          children: [
            StatCard(
              icon: Icons.payments_outlined,
              label: '매출',
              value: won(now.revenue),
              caption: revenueCaption,
              captionColor: revenueColor,
            ),
            StatCard(
              icon: Icons.savings_outlined,
              label: '순이익 (매출 - 원가)',
              value: won(now.profit),
              caption: '이익률 ${percent(now.profitRate)}',
            ),
            StatCard(
              icon: Icons.receipt_outlined,
              label: '주문 수',
              value: '${now.orderCount}건',
              caption: orderCaption,
              captionColor: orderColor,
            ),
            StatCard(
              icon: Icons.person_outline,
              label: '객단가',
              value: won(now.averageOrderValue),
              caption: aovCaption,
              captionColor: aovColor,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (period != StatsPeriod.today)
          SectionCard(
            title: '일별 매출',
            child: SimpleBarChart(
              values: [for (final d in data.daily) d.revenue.toDouble()],
              labelOf: (i) => shortDate(data.daily[i].day),
              tooltipOf: (v) => won(v.round()),
              labelEvery: period == StatsPeriod.month ? 5 : 1,
            ),
          ),
        SectionCard(
          title: '시간대별 매출',
          child: firstHour < 0
              ? const Text('이 기간에는 매출이 없어요.')
              : SimpleBarChart(
                  values: [
                    for (var h = firstHour; h <= lastHour; h++)
                      data.hourly[h].toDouble(),
                  ],
                  labelOf: (i) => '${firstHour + i}시',
                  tooltipOf: (v) => won(v.round()),
                  labelEvery: 2,
                ),
        ),
        SectionCard(
          title: '상품별 판매 순위',
          child: data.ranking.isEmpty
              ? const Text('판매된 상품이 없어요.')
              : Column(
                  children: [
                    for (final (i, sales) in data.ranking.take(10).indexed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                SizedBox(
                                  width: 24,
                                  child: Text(
                                    '${i + 1}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Expanded(child: Text(sales.name)),
                                Text(
                                  '${sales.quantity}개',
                                  style: theme.textTheme.bodySmall,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  won(sales.revenue),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.only(left: 24),
                              child: LinearProgressIndicator(
                                value: sales.revenue / topRevenue,
                                minHeight: 6,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        SectionCard(
          title: '결제 수단',
          child: Column(
            children: [
              for (final MapEntry(key: method, value: amount)
                  in data.payments.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(width: 64, child: Text(method.label)),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: paymentTotal == 0 ? 0 : amount / paymentTotal,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        child: Text(
                          paymentTotal == 0
                              ? '-'
                              : percent(amount / paymentTotal),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        SectionCard(
          title: '매출 향상 인사이트',
          child: InsightList(insights: data.insights),
        ),
      ],
    );
  }
}
