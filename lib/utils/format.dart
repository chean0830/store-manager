import 'package:intl/intl.dart';

final _number = NumberFormat('#,##0');
final _time = DateFormat('HH:mm');
const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

String won(int amount) => '${_number.format(amount)}원';

String percent(double ratio) => '${(ratio * 100).toStringAsFixed(1)}%';

String weekday(DateTime date) => _weekdays[date.weekday - 1];

String shortDate(DateTime date) => '${date.month}/${date.day}';

String fullDate(DateTime date) =>
    '${date.year}년 ${date.month}월 ${date.day}일 (${weekday(date)})';

String timeOf(DateTime date) => _time.format(date);
