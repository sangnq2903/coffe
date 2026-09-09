import 'dart:async';

import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/foundation.dart';

/// Nghe tín hiệu "dữ liệu vừa đổi" từ máy chủ và gọi các màn hình tự tải lại.
///
/// Màn hình đăng ký quan tâm tới bảng nào, và trả lại một hàm để huỷ đăng ký:
///
/// ```dart
/// _huy = context.read<DataRefreshController>().dangKy(['tickets'], _load);
/// ...
/// _huy?.call();   // trong dispose
/// ```
///
/// Máy chủ chỉ gửi **tên bảng**, không gửi dữ liệu — màn hình nhận tín hiệu thì
/// gọi lại đúng cửa API cũ. Nhờ vậy luật phân quyền chỉ có một bản, và màn hình
/// không phải biết gì thêm ngoài việc "tải lại đi".
class DataRefreshController extends ChangeNotifier {
  /// Hai lượt tải lại phải cách nhau ít nhất chừng này.
  ///
  /// Máy chủ đã gom tín hiệu rồi, nhưng một lượt đồng bộ dài vẫn đẻ ra nhiều
  /// lô liên tiếp. Không chặn ở đây thì màn hình danh sách gọi API liên tục và
  /// nhấp nháy trước mắt người đang đọc.
  static const Duration _nhipToiThieu = Duration(milliseconds: 1500);

  LiveChangeClient? _live;
  StreamSubscription<ThayDoiDuLieu>? _sub;
  Uri? _uriHienTai;

  final List<_NguoiNghe> _nguoiNghe = [];
  DateTime? _lanCuoi;
  DateTime? _thoiDiemGoiCuoi;
  Timer? _henTraiTuyen;
  ThayDoiDuLieu? _donTreo;

  bool get dangNoi => _live?.dangNoi ?? false;

  /// Lần cuối nhận được tín hiệu từ máy chủ.
  DateTime? get lanCuoi => _lanCuoi;

  /// Mở (hoặc chuyển sang) kênh tín hiệu của một máy chủ.
  void connectTo(Uri? wsUri) {
    if (wsUri == null) {
      disconnect();
      return;
    }
    if (_uriHienTai == wsUri && _live != null) return;

    disconnect();
    _uriHienTai = wsUri;
    final live = LiveChangeClient(wsUrl: wsUri);
    _live = live;
    _sub = live.thayDoi.listen(apDung);
    live.start();
  }

  void disconnect() {
    _sub?.cancel();
    _sub = null;
    _live?.dispose();
    _live = null;
    _uriHienTai = null;
    _henTraiTuyen?.cancel();
    _henTraiTuyen = null;
    _donTreo = null;
  }

  /// Đăng ký tải lại khi một trong các [bang] đổi. Trả về hàm huỷ đăng ký.
  ///
  /// Danh sách rỗng nghĩa là nghe mọi thay đổi.
  VoidCallback dangKy(List<String> bang, VoidCallback taiLai) {
    final nguoi = _NguoiNghe(bang.toSet(), taiLai);
    _nguoiNghe.add(nguoi);
    return () => _nguoiNghe.remove(nguoi);
  }

  /// Nhận một tín hiệu và gọi những màn hình có liên quan.
  ///
  /// Để công khai vì đây là cửa vào duy nhất của cả lớp: mọi tín hiệu, dù đến
  /// từ WebSocket hay do chỗ khác trong app tự phát, đều đi qua đây.
  void apDung(ThayDoiDuLieu tin) {
    _lanCuoi = DateTime.now();
    notifyListeners();

    final cuoiCung = _thoiDiemGoiCuoi;
    final daQua =
        cuoiCung == null ? _nhipToiThieu : DateTime.now().difference(cuoiCung);

    if (daQua >= _nhipToiThieu) {
      _goi(tin);
      return;
    }

    // Còn trong nhịp chặn: dồn tín hiệu lại và gọi một lần ở cuối. Bỏ hẳn tín
    // hiệu này thì thay đổi cuối cùng của một trận ghi sẽ không bao giờ tới
    // màn hình — đúng cái tình huống hay gặp nhất.
    _donTreo = _donTreo == null
        ? tin
        : ThayDoiDuLieu(
            {..._donTreo!.bang, ...tin.bang},
            noiLai: _donTreo!.noiLai || tin.noiLai,
          );
    _henTraiTuyen ??= Timer(_nhipToiThieu - daQua, () {
      _henTraiTuyen = null;
      final don = _donTreo;
      _donTreo = null;
      if (don != null) _goi(don);
    });
  }

  void _goi(ThayDoiDuLieu tin) {
    _thoiDiemGoiCuoi = DateTime.now();
    // Chép danh sách trước khi duyệt: hàm tải lại có thể huỷ đăng ký ngay
    // trong lúc chạy (màn hình bị đóng), làm vỡ vòng lặp.
    for (final n in List<_NguoiNghe>.from(_nguoiNghe)) {
      if (n.bang.isEmpty || tin.coBang(n.bang)) {
        try {
          n.taiLai();
        } catch (_) {
          // Một màn hình lỗi không được làm các màn hình khác mất tín hiệu.
        }
      }
    }
  }

  @override
  void dispose() {
    disconnect();
    _nguoiNghe.clear();
    super.dispose();
  }
}

class _NguoiNghe {
  _NguoiNghe(this.bang, this.taiLai);

  final Set<String> bang;
  final VoidCallback taiLai;
}
