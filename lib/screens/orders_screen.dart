import 'package:flutter/material.dart';

import '../logic/sales_stats.dart';
import '../models/order.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// 최근 30일 주문 기록. 주문을 누르면 상세 내역과 환불 버튼이 나온다.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  int? _revision;
  late Future<List<SalesOrder>> _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    if (_revision != state.revision) {
      _revision = state.revision;
      final today = startOfDay(DateTime.now());
      _future = state.db.orders(
        from: DateTime(today.year, today.month, today.day - 29),
        to: DateTime(today.year, today.month, today.day + 1),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('주문 내역')),
      body: FutureBuilder<List<SalesOrder>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyHint(
              icon: Icons.error_outline,
              message: '불러오지 못했어요\n${snapshot.error}',
            );
          }
          final orders = snapshot.data;
          if (orders == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (orders.isEmpty) {
            return const EmptyHint(
              icon: Icons.receipt_long_outlined,
              message: '최근 30일 주문이 없어요.',
            );
          }

          // 날짜 머리글과 주문을 한 목록에 섞어 둔다.
          final rows = <Object>[];
          final dailyTotal = <DateTime, int>{};
          for (final order in orders) {
            final day = startOfDay(order.createdAt);
            if (!dailyTotal.containsKey(day)) {
              dailyTotal[day] = 0;
              rows.add(day);
            }
            if (order.isPaid) dailyTotal[day] = dailyTotal[day]! + order.total;
            rows.add(order);
          }

          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) => switch (rows[i]) {
              final DateTime day => _DayHeader(
                day: day,
                total: dailyTotal[day]!,
              ),
              final SalesOrder order => _OrderTile(order: order),
              _ => const SizedBox.shrink(),
            },
          );
        },
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.total});

  final DateTime day;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(fullDate(day), style: theme.textTheme.titleSmall),
          const Spacer(),
          Text('매출 ${won(total)}', style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});

  final SalesOrder order;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final refunded = !order.isPaid;
    final strike = refunded
        ? TextStyle(
            decoration: TextDecoration.lineThrough,
            color: scheme.outline,
          )
        : null;

    return ListTile(
      title: Text(order.summary, style: strike),
      subtitle: Text(
        '${timeOf(order.createdAt)} · ${order.payment.label} · #${order.id}',
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            won(order.total),
            style: strike ?? const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (refunded)
            Text('환불', style: TextStyle(color: scheme.error, fontSize: 12)),
        ],
      ),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => _OrderDetailSheet(order: order),
      ),
    );
  }
}

class _OrderDetailSheet extends StatelessWidget {
  const _OrderDetailSheet({required this.order});

  final SalesOrder order;

  Future<void> _refund(BuildContext context) async {
    final state = AppScope.read(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('환불 처리'),
        content: Text('${won(order.total)}을 환불할까요?\n판매한 수량은 재고로 되돌아가요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('환불'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await state.refundOrder(order.id);
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text('주문 #${order.id}을 환불했어요.')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('주문 #${order.id}', style: theme.textTheme.titleLarge),
            Text(
              '${fullDate(order.createdAt)} ${timeOf(order.createdAt)} · ${order.payment.label}',
            ),
            const Divider(height: 24),
            for (final item in order.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${item.productName} × ${item.quantity}'),
                    ),
                    Text(won(item.subtotal)),
                  ],
                ),
              ),
            const Divider(height: 24),
            Row(
              children: [
                Text('합계', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(
                  won(order.total),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Text(
              '원가 ${won(order.costTotal)} · 이익 ${won(order.total - order.costTotal)}',
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (order.isPaid)
              OutlinedButton.icon(
                onPressed: () => _refund(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.undo),
                label: const Text('환불 처리'),
              )
            else
              Text(
                '환불된 주문이에요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}
