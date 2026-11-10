/// 매장에서 판매하는 상품. 금액은 모두 원 단위 정수로 다룬다.
class Product {
  const Product({
    this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.cost,
    required this.stock,
    required this.lowStockThreshold,
  });

  factory Product.fromMap(Map<String, Object?> map) => Product(
    id: map['id'] as int,
    name: map['name'] as String,
    category: map['category'] as String,
    price: map['price'] as int,
    cost: map['cost'] as int,
    stock: map['stock'] as int,
    lowStockThreshold: map['low_stock'] as int,
  );

  final int? id;
  final String name;
  final String category;

  /// 판매가
  final int price;

  /// 원가(재료비)
  final int cost;
  final int stock;

  /// 재고가 이 수량 이하로 떨어지면 부족으로 표시한다.
  final int lowStockThreshold;

  int get margin => price - cost;
  double get marginRate => price == 0 ? 0 : margin / price;
  bool get isLowStock => stock <= lowStockThreshold;

  Map<String, Object?> toMap() => {
    'name': name,
    'category': category,
    'price': price,
    'cost': cost,
    'stock': stock,
    'low_stock': lowStockThreshold,
  };
}

const kCategories = ['커피', '음료', '디저트', '푸드', '기타'];
