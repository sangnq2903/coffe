import 'dart:async';

/// Báo cho mọi máy đang mở app biết dữ liệu vừa đổi, để chúng tự tải lại.
///
/// **Chỉ báo tên bảng vừa đổi, không gửi dữ liệu.** Gửi kèm bản ghi thì phải
/// dựng lại toàn bộ luật phân quyền ở đây một lần nữa — trạm nào xem được kho
/// nào, ai xem được sổ mua bán — và hai chỗ ấy sẽ trôi xa nhau. Máy nhận được
/// tín hiệu thì gọi lại đúng cửa API cũ, nơi luật phân quyền đã có sẵn.
///
/// **Gom tín hiệu lại rồi mới phát.** Móc báo của SQLite bắn ra từng dòng một:
/// một lượt đồng bộ ghi 500 dòng là 500 tín hiệu, mà mỗi tín hiệu làm mọi máy
/// ở kho gọi lại API. Gom trong [gom] rồi phát một lần thì cả trận ghi đó chỉ
/// tốn đúng một lượt tải lại.
class ChangeBroker {
  ChangeBroker({this.gom = const Duration(milliseconds: 400)});

  /// Khoảng gom tín hiệu. Đủ ngắn để người dùng thấy như tức thì, đủ dài để
  /// một trận ghi hàng loạt không thành một trận tải lại hàng loạt.
  final Duration gom;

  final _controller = StreamController<Set<String>>.broadcast();
  final Set<String> _cho = {};
  Timer? _hen;
  bool _dongRoi = false;

  Stream<Set<String>> get thayDoi => _controller.stream;

  /// Ghi nhận một bảng vừa bị ghi. Gọi rất nhiều lần nên phải thật rẻ.
  void ghiNhan(String bang) {
    if (_dongRoi || bang.isEmpty || _bangBoQua.contains(bang)) return;
    _cho.add(bang);
    _hen ??= Timer(gom, _phat);
  }

  void _phat() {
    _hen = null;
    if (_cho.isEmpty || _dongRoi || _controller.isClosed) return;
    final lo = Set<String>.unmodifiable(_cho);
    _cho.clear();
    _controller.add(lo);
  }

  /// Bảng không đáng làm cả kho tải lại.
  ///
  /// `cai_dat` là thiết lập riêng của máy chủ, `sync_state` và `ticket_counters`
  /// là sổ nội bộ của việc đồng bộ — chúng đổi liên tục mà không màn hình nào
  /// hiện. Không lọc thì mỗi lượt đồng bộ 15 giây lại bắt mọi máy tải lại một
  /// lần dù chẳng có gì mới để xem.
  static const _bangBoQua = {'sync_state', 'ticket_counters', 'cai_dat'};

  Future<void> dispose() async {
    _dongRoi = true;
    _hen?.cancel();
    await _controller.close();
  }
}
