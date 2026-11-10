enum PaymentMethod {
  card('카드'),
  cash('현금'),
  transfer('계좌이체');

  const PaymentMethod(this.label);
  final String label;
}

enum OrderStatus { paid, refunded }

/// 주문 당시의 상품명·가격·원가를 그대로 보관한다.
/// 나중에 상품 가격을 바꾸거나 삭제해도 과거 매출이 변하지 않게 하기 위해서다.
class OrderItem {
  const OrderItem({
    required this.productId,
    required this.productName,
    required this.unitPrice,
    required this.unitCost,
    required this.quantity,
  });

  factory OrderItem.fromMap(Map<String, Object?> map) => OrderItem(
    productId: map['product_id'] as int,
    productName: map['name'] as String,
    unitPrice: map['unit_price'] as int,
    unitCost: map['unit_cost'] as int,
    quantity: map['quantity'] as int,
  );

  final int productId;
  final String productName;
  final int unitPrice;
  final int unitCost;
  final int quantity;

  int get subtotal => unitPrice * quantity;
  int get costTotal => unitCost * quantity;
}

class SalesOrder {
  const SalesOrder({
    required this.id,
    required this.createdAt,
    required this.payment,
    required this.status,
    required this.items,
  });

  final int id;
  final DateTime createdAt;
  final PaymentMethod payment;
  final OrderStatus status;
  final List<OrderItem> items;

  bool get isPaid => status == OrderStatus.paid;
  int get total => items.fold(0, (sum, item) => sum + item.subtotal);
  int get costTotal => items.fold(0, (sum, item) => sum + item.costTotal);
  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  String get summary {
    if (items.isEmpty) return '(품목 없음)';
    if (items.length == 1) return items.first.productName;
    return '${items.first.productName} 외 ${items.length - 1}건';
  }
}
