import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/product.dart';
import '../state/app_state.dart';
import '../utils/format.dart';

class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, this.product});

  /// null이면 새 상품을 만든다.
  final Product? product;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.product?.name);
  late final _price = TextEditingController(
    text: widget.product?.price.toString(),
  );
  late final _cost = TextEditingController(
    text: widget.product?.cost.toString(),
  );
  late final _stock = TextEditingController(
    text: '${widget.product?.stock ?? 0}',
  );
  late final _lowStock = TextEditingController(
    text: '${widget.product?.lowStockThreshold ?? 5}',
  );
  late String _category = widget.product?.category ?? kCategories.first;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _price, _cost, _stock, _lowStock]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _number(String? text) => int.tryParse((text ?? '').trim());

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final state = AppScope.read(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    await state.saveProduct(
      Product(
        id: widget.product?.id,
        name: _name.text.trim(),
        category: _category,
        price: _number(_price.text)!,
        cost: _number(_cost.text)!,
        stock: _number(_stock.text)!,
        lowStockThreshold: _number(_lowStock.text)!,
      ),
    );
    navigator.pop();
  }

  Future<void> _delete() async {
    final product = widget.product!;
    final state = AppScope.read(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('상품 삭제'),
        content: Text('${product.name}을(를) 삭제할까요?\n지난 주문 기록과 매출은 그대로 남아요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await state.deleteProduct(product);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = widget.product != null;
    final price = _number(_price.text);
    final cost = _number(_cost.text);
    final categories = {...kCategories, _category}.toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? '상품 수정' : '상품 추가'),
        actions: [
          if (editing)
            IconButton(
              tooltip: '삭제',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '상품명',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v ?? '').trim().isEmpty ? '상품명을 입력하세요' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(
                labelText: '분류',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final c in categories)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => setState(() => _category = v!),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _numberField(_price, '판매가(원)', min: 1)),
                const SizedBox(width: 12),
                Expanded(child: _numberField(_cost, '원가(원)', min: 0)),
              ],
            ),
            if (price != null && cost != null && price > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '1개 팔 때 이익 ${won(price - cost)} · 마진율 ${percent((price - cost) / price)}',
                  style: TextStyle(
                    color: cost > price
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _numberField(
                    _stock,
                    editing ? '현재 재고' : '처음 재고',
                    min: 0,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _numberField(_lowStock, '부족 알림 기준', min: 0)),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label, {
    required int min,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => setState(() {}),
      validator: (v) {
        final n = _number(v);
        if (n == null) return '숫자를 입력하세요';
        if (n < min) return '$min 이상 입력하세요';
        return null;
      },
    );
  }
}
