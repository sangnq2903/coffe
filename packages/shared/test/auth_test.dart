import 'package:canxe_shared/canxe_shared.dart';
import 'package:test/test.dart';

void main() {
  // Số vòng thấp cho nhanh; giá trị thật dùng khi chạy là 120.000.
  const iterations = 1000;

  group('PasswordHasher', () {
    test('mật khẩu đúng thì kiểm được', () {
      final salt = PasswordHasher.newSalt();
      final hash = PasswordHasher.hash('mat-khau-cua-toi', salt, iterations: iterations);

      expect(
        PasswordHasher.verify(
          password: 'mat-khau-cua-toi',
          salt: salt,
          expectedHash: hash,
          iterations: iterations,
        ),
        isTrue,
      );
    });

    test('sai một ký tự là không qua', () {
      final salt = PasswordHasher.newSalt();
      final hash = PasswordHasher.hash('mat-khau', salt, iterations: iterations);

      expect(
        PasswordHasher.verify(
          password: 'mat-kha',
          salt: salt,
          expectedHash: hash,
          iterations: iterations,
        ),
        isFalse,
      );
    });

    test('hai người trùng mật khẩu vẫn ra chuỗi băm khác nhau', () {
      // Nhờ muối riêng từng người: lấy được cơ sở dữ liệu cũng không tra bảng
      // sẵn để dò ngược hàng loạt được.
      final a = PasswordHasher.newSalt();
      final b = PasswordHasher.newSalt();
      expect(a, isNot(b));
      expect(
        PasswordHasher.hash('123456', a, iterations: iterations),
        isNot(PasswordHasher.hash('123456', b, iterations: iterations)),
      );
    });

    test('chuỗi băm không chứa mật khẩu gốc', () {
      final salt = PasswordHasher.newSalt();
      final hash = PasswordHasher.hash('caphe2026', salt, iterations: iterations);
      expect(hash.contains('caphe2026'), isFalse);
    });

    test('sai số vòng thì không kiểm ra kết quả đúng', () {
      final salt = PasswordHasher.newSalt();
      final hash = PasswordHasher.hash('abc', salt, iterations: iterations);
      expect(
        PasswordHasher.verify(
          password: 'abc',
          salt: salt,
          expectedHash: hash,
          iterations: iterations + 1,
        ),
        isFalse,
      );
    });

    test('dữ liệu rỗng hoặc hỏng thì trả false chứ không ném lỗi', () {
      expect(
        PasswordHasher.verify(password: 'a', salt: '', expectedHash: '', iterations: 1),
        isFalse,
      );
      expect(
        PasswordHasher.verify(
            password: 'a', salt: '!!!khong-phai-base64!!!', expectedHash: 'x', iterations: 1),
        isFalse,
      );
    });
  });

  group('SessionToken', () {
    final secret = SessionToken.newSecret();

    test('phiếu vừa tạo thì đọc được và đúng người', () {
      final token = SessionToken.create(userId: 'nguoi-1', secret: secret);
      final claims = SessionToken.verify(token, secret);

      expect(claims, isNotNull);
      expect(claims!.userId, 'nguoi-1');
      expect(claims.expired, isFalse);
    });

    test('khoá ký khác thì không đọc được', () {
      // Đây là lớp bảo vệ chính: không có khoá thì không tự ký phiếu giả được.
      final token = SessionToken.create(userId: 'nguoi-1', secret: secret);
      expect(SessionToken.verify(token, SessionToken.newSecret()), isNull);
    });

    test('sửa nội dung phiếu là chữ ký hỏng', () {
      final token = SessionToken.create(userId: 'nguoi-1', secret: secret);
      final parts = token.split('.');
      final giaMao = SessionToken.create(userId: 'nguoi-2', secret: SessionToken.newSecret())
          .split('.')
          .first;
      expect(SessionToken.verify('$giaMao.${parts[1]}', secret), isNull);
    });

    test('phiếu hết hạn bị từ chối', () {
      final token = SessionToken.create(
        userId: 'nguoi-1',
        secret: secret,
        lifetime: const Duration(seconds: 1),
        now: DateTime.now().subtract(const Duration(hours: 2)),
      );
      expect(SessionToken.verify(token, secret), isNull);
    });

    test('phiếu rỗng hoặc sai định dạng trả null chứ không ném lỗi', () {
      for (final xau in [null, '', 'khong-co-dau-cham', 'a.b.c', '!!!.???']) {
        expect(SessionToken.verify(xau, secret), isNull, reason: 'với "$xau"');
      }
    });

    test('mỗi máy chủ sinh khoá ký riêng, không trùng nhau', () {
      expect(SessionToken.newSecret(), isNot(SessionToken.newSecret()));
    });
  });

  group('AppUser — phạm vi kho', () {
    AppUser user(UserRole role, List<String> scope) => AppUser(
          id: 'u',
          username: 'a',
          fullName: 'A',
          role: role,
          stationScope: scope,
          updatedAt: DateTime.now(),
        );

    test('tài khoản tổng vào được mọi kho', () {
      final u = user(UserRole.tong, const []);
      expect(u.canAccessStation('KHO01'), isTrue);
      expect(u.canAccessStation('KHO99'), isTrue);
    });

    test('tài khoản trạm chỉ vào được kho được gán', () {
      final u = user(UserRole.tram, const ['KHO01']);
      expect(u.canAccessStation('KHO01'), isTrue);
      expect(u.canAccessStation('KHO02'), isFalse);
    });

    test('tài khoản trạm không có kho nào thì không vào được gì', () {
      final u = user(UserRole.tram, const []);
      expect(u.canAccessStation('KHO01'), isFalse);
      expect(u.canAccessStation(null), isFalse);
    });

    test('so khớp mã kho không phân biệt hoa thường', () {
      final u = user(UserRole.tram, const ['kho01']);
      expect(u.canAccessStation('KHO01'), isTrue);
    });

    test('chuỗi băm không lọt ra JSON gửi cho trình duyệt', () {
      final u = AppUser.create(
        username: 'chu',
        fullName: 'Chủ',
        role: UserRole.tong,
        passwordHash: 'BAM-MAT-KHAU',
        salt: 'MUOI',
        iterations: 1000,
      );
      expect(u.toJson().containsKey('password_hash'), isFalse);
      expect(u.toJson().toString().contains('BAM-MAT-KHAU'), isFalse);
      // Chỉ luồng đồng bộ giữa máy chủ mới kèm theo.
      expect(u.toJson(includeSecret: true)['password_hash'], 'BAM-MAT-KHAU');
    });

    test('tên đăng nhập luôn viết thường', () {
      final u = AppUser.create(
        username: '  ChU.Kho  ',
        fullName: 'x',
        role: UserRole.tong,
        passwordHash: 'h',
        salt: 's',
        iterations: 1,
      );
      expect(u.username, 'chu.kho');
    });
  });
}
