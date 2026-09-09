import 'package:canxe_app/state/data_refresh_controller.dart';
import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kiểm thử bộ điều phối tải lại của app.
///
/// Không chạm tới mạng: chỉ kiểm phần quyết định "màn hình nào phải tải lại,
/// và bao lâu một lần". Đây mới là chỗ dễ làm người dùng khó chịu — tải lại
/// quá tay thì danh sách nhấp nháy trước mắt người đang đọc, tải lại thiếu thì
/// màn hình đứng ở dữ liệu cũ.
void main() {
  late DataRefreshController dieuPhoi;

  setUp(() => dieuPhoi = DataRefreshController());
  tearDown(() => dieuPhoi.dispose());

  /// Đẩy một tín hiệu vào như thể vừa nhận từ máy chủ.
  void bao(Set<String> bang, {bool noiLai = false}) =>
      dieuPhoi.apDung(ThayDoiDuLieu(bang, noiLai: noiLai));

  test('chỉ màn hình quan tâm mới tải lại', () {
    var phieu = 0, cham = 0;
    dieuPhoi.dangKy(const ['tickets'], () => phieu++);
    dieuPhoi.dangKy(const ['cham_cong'], () => cham++);

    bao({'tickets'});

    expect(phieu, 1);
    expect(cham, 0, reason: 'sổ chấm công không đổi thì đừng bắt nó tải lại');
  });

  test('đăng ký danh sách rỗng thì nghe mọi thay đổi', () {
    var n = 0;
    dieuPhoi.dangKy(const [], () => n++);
    bao({'giao_dich'});
    expect(n, 1);
  });

  test('tín hiệu nối lại thì mọi màn hình đều tải lại', () {
    var phieu = 0, cham = 0;
    dieuPhoi.dangKy(const ['tickets'], () => phieu++);
    dieuPhoi.dangKy(const ['cham_cong'], () => cham++);

    bao({}, noiLai: true);

    expect(phieu, 1);
    expect(cham, 1);
  });

  test('huỷ đăng ký rồi thì không gọi nữa', () {
    var n = 0;
    final huy = dieuPhoi.dangKy(const ['tickets'], () => n++);
    bao({'tickets'});
    huy();
    bao({'tickets'});
    expect(n, 1);
  });

  test('màn hình tự huỷ đăng ký ngay trong lúc tải lại cũng không vỡ', () {
    // Xảy ra thật: tín hiệu tới đúng lúc người dùng đóng màn hình.
    var n = 0;
    late final void Function() huy;
    huy = dieuPhoi.dangKy(const ['tickets'], () {
      n++;
      huy();
    });
    expect(() => bao({'tickets'}), returnsNormally);
    expect(n, 1);
  });

  test('một màn hình lỗi không làm màn hình khác mất tín hiệu', () {
    var sau = 0;
    dieuPhoi.dangKy(const ['tickets'], () => throw StateError('hỏng'));
    dieuPhoi.dangKy(const ['tickets'], () => sau++);

    expect(() => bao({'tickets'}), returnsNormally);
    expect(sau, 1);
  });

  test('hai tín hiệu sát nhau chỉ tải lại một lần', () {
    // Máy chủ đã gom rồi, nhưng một lượt đồng bộ dài vẫn đẻ ra nhiều lô liên
    // tiếp. Không chặn thì danh sách nhấp nháy trước mắt người đang đọc.
    var n = 0;
    dieuPhoi.dangKy(const ['tickets'], () => n++);

    bao({'tickets'});
    bao({'tickets'});
    bao({'tickets'});

    expect(n, 1);
  });

  test('tín hiệu bị chặn nhịp vẫn tới, chỉ là tới muộn', () async {
    // Bỏ hẳn tín hiệu cuối thì thay đổi cuối cùng của một trận ghi không bao
    // giờ lên màn hình — đúng tình huống hay gặp nhất.
    var n = 0;
    final thay = <String>{};
    dieuPhoi.dangKy(const ['tickets', 'cham_cong'], () => n++);
    dieuPhoi.dangKy(const [], () => thay.add('co'));

    bao({'tickets'});
    expect(n, 1);

    bao({'cham_cong'});
    expect(n, 1, reason: 'còn trong nhịp chặn');

    await Future<void>.delayed(const Duration(milliseconds: 1800));
    expect(n, 2, reason: 'hết nhịp chặn thì phải gọi bù');
    expect(thay, contains('co'));
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('nhiều tín hiệu bị dồn thì gộp thành một lần gọi bù', () async {
    var n = 0;
    dieuPhoi.dangKy(const ['tickets'], () => n++);

    bao({'tickets'});
    for (var i = 0; i < 20; i++) {
      bao({'tickets'});
    }
    await Future<void>.delayed(const Duration(milliseconds: 1800));

    expect(n, 2, reason: 'một lần ngay, một lần gộp bù — không phải 21 lần');
  }, timeout: const Timeout(Duration(seconds: 20)));
}
