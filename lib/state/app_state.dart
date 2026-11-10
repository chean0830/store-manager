import 'package:flutter/widgets.dart';

import '../data/app_database.dart';
import '../models/order.dart';
import '../models/product.dart';

/// 상품 목록과 장바구니를 들고 있는 앱 전체 상태.
/// DB가 바뀔 때마다 [revision]을 올려서, 주문 기록을 보여주는 화면들이 다시 불러오게 한다.
class AppState extends ChangeNotifier {
  AppState(this.db);

  final AppDatabase db;

  List<Product> _products = const [];
  final Map<int, int> _cart = {};
  int _revision = 0;

  List<Product> get products => _products;
  int get revision => _revision;

  Product? productById(int id) {
    for (final product in _products) {
      if (product.id == id) return product;
    }
    return null;
  }

  // ── 장바구니 ──────────────────────────────────────

  int quantityInCart(Product product) => _cart[product.id] ?? 0;

  List<(Product, int)> get cartLines => [
    for (final entry in _cart.entries)
      if (productById(entry.key) case final product?) (product, entry.value),
  ];

  int get cartCount => _cart.values.fold(0, (a, b) => a + b);

  int get cartTotal =>
      cartLines.fold(0, (sum, line) => sum + line.$1.price * line.$2);

  /// 재고보다 많이 담으려 하면 false를 돌려준다.
  bool addToCart(Product product) {
    final quantity = quantityInCart(product);
    if (quantity >= product.stock) return false;
    _cart[product.id!] = quantity + 1;
    notifyListeners();
    return true;
  }

  void removeFromCart(Product product) {
    final quantity = quantityInCart(product);
    if (quantity <= 1) {
      _cart.remove(product.id);
    } else {
      _cart[product.id!] = quantity - 1;
    }
    notifyListeners();
  }

  void clearCart() {
    _cart.clear();
    notifyListeners();
  }

  Future<void> checkout(PaymentMethod payment) async {
    final items = [
      for (final (product, quantity) in cartLines)
        OrderItem(
          productId: product.id!,
          productName: product.name,
          unitPrice: product.price,
          unitCost: product.cost,
          quantity: quantity,
        ),
    ];
    if (items.isEmpty) return;
    await db.placeOrder(items, payment);
    _cart.clear();
    await _reload();
  }

  // ── 상품·재고·주문 변경 ─────────────────────────────

  Future<void> loadProducts() async {
    _products = await db.products();
    // 삭제됐거나 재고가 줄어든 상품은 장바구니 수량을 맞춘다.
    for (final id in _cart.keys.toList()) {
      final product = productById(id);
      if (product == null || product.stock <= 0) {
        _cart.remove(id);
      } else if (_cart[id]! > product.stock) {
        _cart[id] = product.stock;
      }
    }
    notifyListeners();
  }

  Future<void> saveProduct(Product product) async {
    if (product.id == null) {
      await db.insertProduct(product);
    } else {
      await db.updateProduct(product);
    }
    await _reload();
  }

  Future<void> deleteProduct(Product product) async {
    await db.deleteProduct(product.id!);
    await _reload();
  }

  Future<void> addStock(Product product, int quantity) async {
    await db.addStock(product.id!, quantity);
    await _reload();
  }

  Future<void> refundOrder(int orderId) async {
    await db.refundOrder(orderId);
    await _reload();
  }

  Future<void> _reload() async {
    _revision++;
    await loadProducts();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  /// build 안에서 쓴다. 상태가 바뀌면 다시 그려진다.
  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// 버튼 콜백처럼 build 밖에서 쓴다.
  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
