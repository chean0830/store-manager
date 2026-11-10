import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/product.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'product_form_screen.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  bool _lowOnly = false;

  void _openForm(Product? product) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductFormScreen(product: product),
      ),
    );
  }

  Future<void> _restock(Product product) async {
    final state = AppScope.read(context);
    final quantity = await showDialog<int>(
      context: context,
      builder: (_) => _RestockDialog(product: product),
    );
    if (quantity == null || quantity <= 0) return;
    await state.addStock(product, quantity);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${product.name} $quantity개 입고했어요.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final products = _lowOnly
        ? state.products.where((p) => p.isLowStock).toList()
        : state.products;

    return Scaffold(
      appBar: AppBar(
        title: const Text('상품·재고'),
        actions: [
          FilterChip(
            label: const Text('재고 부족만'),
            selected: _lowOnly,
            onSelected: (value) => setState(() => _lowOnly = value),
          ),
          const SizedBox(width: 12),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(null),
        icon: const Icon(Icons.add),
        label: const Text('상품 추가'),
      ),
      body: products.isEmpty
          ? EmptyHint(
              icon: Icons.inventory_2_outlined,
              message: _lowOnly ? '재고가 부족한 상품이 없어요.' : '등록된 상품이 없어요.',
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: products.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final product = products[i];
                final stockColor = product.isLowStock ? scheme.error : null;
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(product.category.substring(0, 1)),
                  ),
                  title: Text(product.name),
                  subtitle: Text(
                    '${won(product.price)} · 마진 ${percent(product.marginRate)}',
                  ),
                  onTap: () => _openForm(product),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${product.stock}개',
                            style: TextStyle(
                              color: stockColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (product.isLowStock)
                            Text(
                              '재고 부족',
                              style: TextStyle(color: stockColor, fontSize: 11),
                            ),
                        ],
                      ),
                      IconButton(
                        tooltip: '입고',
                        icon: const Icon(Icons.add_box_outlined),
                        onPressed: () => _restock(product),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _RestockDialog extends StatefulWidget {
  const _RestockDialog({required this.product});

  final Product product;

  @override
  State<_RestockDialog> createState() => _RestockDialogState();
}

class _RestockDialogState extends State<_RestockDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() =>
      Navigator.pop(context, int.tryParse(_controller.text.trim()));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.product.name} 입고'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('현재 재고 ${widget.product.stock}개'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: '입고 수량',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final amount in const [10, 20, 50])
                ActionChip(
                  label: Text('+$amount'),
                  onPressed: () => _controller.text = '$amount',
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(onPressed: _submit, child: const Text('입고')),
      ],
    );
  }
}
