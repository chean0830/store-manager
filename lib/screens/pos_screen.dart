import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

const _all = '전체';

/// 계산대 화면. 메뉴를 눌러 담고 결제하면 재고가 바로 줄어든다.
class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  String _category = _all;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final categories = [
      _all,
      ...{for (final p in state.products) p.category},
    ];
    final selected = categories.contains(_category) ? _category : _all;
    final products = selected == _all
        ? state.products
        : state.products.where((p) => p.category == selected).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('주문 받기'),
        actions: [
          if (state.cartCount > 0)
            TextButton(onPressed: state.clearCart, child: const Text('비우기')),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final category in categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(category),
                      selected: category == selected,
                      onSelected: (_) => setState(() => _category = category),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: products.isEmpty
                ? const EmptyHint(
                    icon: Icons.local_cafe_outlined,
                    message: '등록된 상품이 없어요.\n상품 탭에서 추가하세요.',
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 200,
                          mainAxisExtent: 112,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemCount: products.length,
                    itemBuilder: (context, i) =>
                        _ProductTile(product: products[i]),
                  ),
          ),
          if (state.cartCount > 0) const _CartBar(),
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final inCart = state.quantityInCart(product);
    final remaining = product.stock - inCart;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: inCart > 0 ? scheme.primaryContainer : null,
      child: InkWell(
        onTap: remaining <= 0 ? null : () => state.addToCart(product),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (inCart > 0)
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: scheme.primary,
                      child: Text(
                        '$inCart',
                        style: TextStyle(color: scheme.onPrimary, fontSize: 12),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Text(won(product.price), style: textTheme.titleMedium),
              Text(
                remaining <= 0 ? '품절' : '재고 $remaining개',
                style: textTheme.bodySmall?.copyWith(
                  color: remaining <= 0 || product.isLowStock
                      ? scheme.error
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartBar extends StatelessWidget {
  const _CartBar();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${state.cartCount}개 담김',
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    won(state.cartTotal),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => const _CartSheet(),
              ),
              icon: const Icon(Icons.shopping_cart_checkout),
              label: const Text('주문 확인'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartSheet extends StatefulWidget {
  const _CartSheet();

  @override
  State<_CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends State<_CartSheet> {
  PaymentMethod _payment = PaymentMethod.card;
  bool _busy = false;

  Future<void> _checkout() async {
    final state = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final total = state.cartTotal;
    setState(() => _busy = true);
    try {
      await state.checkout(_payment);
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('결제 완료 · ${won(total)} (${_payment.label})')),
      );
    } on InsufficientStockException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final lines = state.cartLines;

    if (lines.isEmpty) {
      return const SizedBox(
        height: 160,
        child: EmptyHint(
          icon: Icons.shopping_cart_outlined,
          message: '장바구니가 비었어요.',
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('주문 확인', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.4,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (product, quantity) in lines)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(product.name),
                      subtitle: Text('${won(product.price)} × $quantity'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '빼기',
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => state.removeFromCart(product),
                          ),
                          Text('$quantity', style: theme.textTheme.titleMedium),
                          IconButton(
                            tooltip: '더하기',
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: quantity >= product.stock
                                ? null
                                : () => state.addToCart(product),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const Divider(),
            Row(
              children: [
                Text('합계', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(
                  won(state.cartTotal),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<PaymentMethod>(
              segments: [
                for (final method in PaymentMethod.values)
                  ButtonSegment(value: method, label: Text(method.label)),
              ],
              selected: {_payment},
              onSelectionChanged: (s) => setState(() => _payment = s.first),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _checkout,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: Text('${won(state.cartTotal)} 결제하기'),
            ),
          ],
        ),
      ),
    );
  }
}
