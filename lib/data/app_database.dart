import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/order.dart';
import '../models/product.dart';

class InsufficientStockException implements Exception {
  const InsufficientStockException(this.productName, this.stock);

  final String productName;
  final int stock;

  @override
  String toString() => '$productName 재고가 부족해요 (남은 수량 $stock개)';
}

/// 기기 안의 SQLite에 상품·주문을 저장한다. 서버 없이 APK만으로 동작한다.
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  static Future<AppDatabase> open() async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, 'store_manager.db'),
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _createTables,
    );
    final appDb = AppDatabase._(db);
    await appDb._seedIfEmpty();
    return appDb;
  }

  static Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        price INTEGER NOT NULL,
        cost INTEGER NOT NULL,
        stock INTEGER NOT NULL,
        low_stock INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        created_at INTEGER NOT NULL,
        payment TEXT NOT NULL,
        status TEXT NOT NULL
      )''');
    // 상품이 삭제돼도 주문 기록은 남아야 하므로 product_id에는 외래키를 걸지 않는다.
    await db.execute('''
      CREATE TABLE order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
        product_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        unit_price INTEGER NOT NULL,
        unit_cost INTEGER NOT NULL,
        quantity INTEGER NOT NULL
      )''');
    await db.execute('CREATE INDEX idx_orders_created ON orders(created_at)');
    await db.execute('CREATE INDEX idx_items_order ON order_items(order_id)');
  }

  // ── 상품 ──────────────────────────────────────────

  Future<List<Product>> products() async {
    final rows = await _db.query('products', orderBy: 'category, name');
    return rows.map(Product.fromMap).toList();
  }

  Future<int> insertProduct(Product product) =>
      _db.insert('products', product.toMap());

  Future<void> updateProduct(Product product) => _db.update(
    'products',
    product.toMap(),
    where: 'id = ?',
    whereArgs: [product.id],
  );

  Future<void> deleteProduct(int id) =>
      _db.delete('products', where: 'id = ?', whereArgs: [id]);

  Future<void> addStock(int productId, int quantity) => _db.rawUpdate(
    'UPDATE products SET stock = stock + ? WHERE id = ?',
    [quantity, productId],
  );

  // ── 주문 ──────────────────────────────────────────

  /// 재고 확인, 재고 차감, 주문 저장을 한 트랜잭션으로 처리한다.
  /// 하나라도 재고가 모자라면 아무것도 저장하지 않는다.
  Future<int> placeOrder(List<OrderItem> items, PaymentMethod payment) {
    return _db.transaction((txn) async {
      for (final item in items) {
        final rows = await txn.query(
          'products',
          columns: ['stock'],
          where: 'id = ?',
          whereArgs: [item.productId],
        );
        final stock = rows.isEmpty ? 0 : rows.first['stock'] as int;
        if (stock < item.quantity) {
          throw InsufficientStockException(item.productName, stock);
        }
        await txn.rawUpdate(
          'UPDATE products SET stock = stock - ? WHERE id = ?',
          [item.quantity, item.productId],
        );
      }
      final orderId = await txn.insert('orders', {
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'payment': payment.name,
        'status': OrderStatus.paid.name,
      });
      for (final item in items) {
        await txn.insert('order_items', _itemRow(orderId, item));
      }
      return orderId;
    });
  }

  /// [from] 이상 [to] 미만에 생성된 주문을 최신순으로 돌려준다.
  Future<List<SalesOrder>> orders({
    required DateTime from,
    required DateTime to,
  }) async {
    final range = [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch];
    final orderRows = await _db.query(
      'orders',
      where: 'created_at >= ? AND created_at < ?',
      whereArgs: range,
      orderBy: 'created_at DESC, id DESC',
    );
    final itemRows = await _db.query(
      'order_items',
      where:
          'order_id IN '
          '(SELECT id FROM orders WHERE created_at >= ? AND created_at < ?)',
      whereArgs: range,
      orderBy: 'id',
    );
    final itemsByOrder = <int, List<OrderItem>>{};
    for (final row in itemRows) {
      itemsByOrder
          .putIfAbsent(row['order_id'] as int, () => [])
          .add(OrderItem.fromMap(row));
    }
    return [
      for (final row in orderRows)
        SalesOrder(
          id: row['id'] as int,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            row['created_at'] as int,
          ),
          payment: PaymentMethod.values.byName(row['payment'] as String),
          status: OrderStatus.values.byName(row['status'] as String),
          items: itemsByOrder[row['id']] ?? const [],
        ),
    ];
  }

  /// 환불하면 팔았던 수량만큼 재고를 되돌린다. 이미 환불된 주문은 무시한다.
  Future<void> refundOrder(int orderId) {
    return _db.transaction((txn) async {
      final rows = await txn.query(
        'orders',
        columns: ['status'],
        where: 'id = ?',
        whereArgs: [orderId],
      );
      if (rows.isEmpty || rows.first['status'] != OrderStatus.paid.name) {
        return;
      }
      final items = await txn.query(
        'order_items',
        where: 'order_id = ?',
        whereArgs: [orderId],
      );
      for (final item in items) {
        await txn.rawUpdate(
          'UPDATE products SET stock = stock + ? WHERE id = ?',
          [item['quantity'], item['product_id']],
        );
      }
      await txn.update(
        'orders',
        {'status': OrderStatus.refunded.name},
        where: 'id = ?',
        whereArgs: [orderId],
      );
    });
  }

  static Map<String, Object?> _itemRow(int orderId, OrderItem item) => {
    'order_id': orderId,
    'product_id': item.productId,
    'name': item.productName,
    'unit_price': item.unitPrice,
    'unit_cost': item.unitCost,
    'quantity': item.quantity,
  };

  // ── 데모 데이터 ────────────────────────────────────

  /// 처음 실행할 때 카페 메뉴와 최근 30일 주문 기록을 만들어 둔다.
  /// 설치하자마자 통계 화면을 확인할 수 있게 하기 위해서다.
  Future<void> _seedIfEmpty() async {
    final count =
        Sqflite.firstIntValue(
          await _db.rawQuery('SELECT COUNT(*) FROM products'),
        ) ??
        0;
    if (count > 0) return;

    // (이름, 분류, 판매가, 원가, 재고, 부족 기준, 인기도)
    const menu = [
      ('아메리카노', '커피', 4500, 800, 140, 30, 30),
      ('카페라떼', '커피', 5000, 1200, 90, 20, 18),
      ('바닐라라떼', '커피', 5500, 1400, 60, 15, 12),
      ('콜드브루', '커피', 5000, 1000, 12, 15, 9),
      ('녹차라떼', '음료', 5500, 1500, 40, 10, 6),
      ('자몽에이드', '음료', 6000, 1800, 35, 10, 7),
      ('딸기스무디', '음료', 6500, 2200, 25, 10, 3),
      ('치즈케이크', '디저트', 6500, 2800, 4, 5, 6),
      ('초코쿠키', '디저트', 2500, 900, 50, 15, 8),
      ('크루아상', '푸드', 3800, 1500, 30, 10, 7),
      ('햄치즈샌드위치', '푸드', 7000, 3200, 18, 8, 5),
    ];

    await _db.transaction((txn) async {
      final ids = <int>[];
      final weights = <int>[];
      final products = <Product>[];
      for (final (name, category, price, cost, stock, low, weight) in menu) {
        final product = Product(
          name: name,
          category: category,
          price: price,
          cost: cost,
          stock: stock,
          lowStockThreshold: low,
        );
        ids.add(await txn.insert('products', product.toMap()));
        weights.add(weight);
        products.add(product);
      }

      // 아침·점심·오후 간식 시간에 손님이 몰리는 카페를 가정한다.
      const hourWeights = {
        8: 7,
        9: 9,
        10: 5,
        11: 7,
        12: 13,
        13: 11,
        14: 6,
        15: 8,
        16: 6,
        17: 5,
        18: 6,
        19: 4,
        20: 3,
        21: 2,
      };
      final rnd = Random(7);
      final now = DateTime.now();
      final batch = txn.batch();
      var orderId = 0;

      for (var daysAgo = 29; daysAgo >= 0; daysAgo--) {
        final day = DateTime(now.year, now.month, now.day - daysAgo);
        final weekend = day.weekday >= DateTime.saturday;
        // 최근으로 올수록 조금씩 손님이 늘어나는 흐름
        final orderCount =
            (weekend ? 34 : 24) + (29 - daysAgo) ~/ 4 + rnd.nextInt(10);

        for (var n = 0; n < orderCount; n++) {
          final hour = _pickWeighted(
            rnd,
            hourWeights.keys.toList(),
            hourWeights.values.toList(),
          );
          final at = DateTime(
            day.year,
            day.month,
            day.day,
            hour,
            rnd.nextInt(60),
            rnd.nextInt(60),
          );
          if (at.isAfter(now)) continue;

          final lineCount =
              1 +
              (rnd.nextDouble() < 0.35 ? 1 : 0) +
              (rnd.nextDouble() < 0.1 ? 1 : 0);
          final chosen = <int>{};
          while (chosen.length < lineCount) {
            chosen.add(
              _pickWeighted(rnd, List.generate(ids.length, (i) => i), weights),
            );
          }

          final paymentRoll = rnd.nextDouble();
          orderId++;
          batch.insert('orders', {
            'id': orderId,
            'created_at': at.millisecondsSinceEpoch,
            'payment':
                (paymentRoll < 0.72
                        ? PaymentMethod.card
                        : paymentRoll < 0.87
                        ? PaymentMethod.transfer
                        : PaymentMethod.cash)
                    .name,
            'status':
                (rnd.nextDouble() < 0.02
                        ? OrderStatus.refunded
                        : OrderStatus.paid)
                    .name,
          });
          for (final index in chosen) {
            final product = products[index];
            batch.insert(
              'order_items',
              _itemRow(
                orderId,
                OrderItem(
                  productId: ids[index],
                  productName: product.name,
                  unitPrice: product.price,
                  unitCost: product.cost,
                  quantity: rnd.nextDouble() < 0.2 ? 2 : 1,
                ),
              ),
            );
          }
        }
      }
      await batch.commit(noResult: true);
    });
  }

  static T _pickWeighted<T>(Random rnd, List<T> values, List<int> weights) {
    final total = weights.fold(0, (a, b) => a + b);
    var roll = rnd.nextInt(total);
    for (var i = 0; i < values.length; i++) {
      roll -= weights[i];
      if (roll < 0) return values[i];
    }
    return values.last;
  }
}
