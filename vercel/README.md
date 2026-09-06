# Sao lưu cơ sở dữ liệu lên Vercel

## Vercel làm được gì và không làm được gì ở đây

Máy chủ cân xe **không chạy được trên Vercel**, và đó không phải chuyện cấu hình
cho khéo là xong:

- Vercel chạy Node, Python, Go, Ruby — **không chạy Dart**.
- Hàm trên Vercel **không có ổ đĩa giữ được**. Mỗi lần gọi là một môi trường mới,
  ghi gì vào đĩa cũng mất. Một file SQLite không sống được ở đó.
- Máy chủ còn phải **mở cổng COM** nối đầu cân. Cổng COM nằm ở kho, không nằm
  trên mây.

Nên máy chủ vẫn chạy ở nhà như cũ. Vercel ở đây đóng đúng một vai: **cái két sắt
để xa** — mỗi đêm nhận một bản sao lưu đã mã hoá, giữ 30 bản gần nhất.

Như vậy vẫn giải quyết được đúng thứ đang lo: cháy máy, hỏng ổ cứng, mất trộm,
hay ai đó xoá nhầm — dữ liệu vẫn còn một bản ở chỗ khác.

## Dữ liệu được bảo vệ thế nào

Hai lớp khoá, cố ý chồng lên nhau:

1. **Blob riêng tư** — file cất trên Vercel không có địa chỉ công khai, phải có
   chìa khoá mới đọc được.
2. **Mã hoá từ nhà** — gói được nén rồi mã hoá AES-256 **trước khi rời máy chủ**,
   ký HMAC-SHA256 để phát hiện sửa đổi. Khoá sinh từ câu mật khẩu bằng PBKDF2
   200.000 vòng.

Lớp 2 mới là lớp đáng kể. Trong cơ sở dữ liệu có lương từng người và sổ mua bán
— giá vốn, lãi từng chuyến — thứ mà trong phần mềm chỉ tài khoản chủ mới xem
được. Chỉ dựa vào lớp 1 là đem toàn bộ chỗ đó đặt vào tay cấu hình đúng của một
dịch vụ bên ngoài. Có lớp 2 thì kể cả Vercel đọc file, hay kho lưu trữ bị lộ,
cũng chỉ thấy byte ngẫu nhiên.

> **Mất câu mật khẩu là mất luôn dữ liệu đã sao lưu.** Không có cửa sau nào mở
> được. Chép ra giấy, cất chỗ khác với cái máy chạy server.

## Cài đặt

### 1. Triển khai lên Vercel

Lấy chìa khoá ở <https://vercel.com/account/tokens>, đặt vào file
`.secrets/vercel-token.txt` (thư mục này đã bị gitignore).

Không cần cài Node.js — công cụ gửi thẳng qua API của Vercel:

```bash
cd packages/server && dart run bin/trien_khai_vercel.dart
```

Nó tạo dự án, tự sinh chìa khoá `CANXE_TOKEN` (cất ở `.secrets/canxe-token.txt`),
gửi mã nguồn lên, chờ dựng xong rồi gọi thử.

### 2. Nối kho Blob

Bước này phải bấm tay trên trang Vercel: mở dự án > **Storage** > **Create
Database** > **Blob** > nối vào dự án. Vercel tự thêm biến
`BLOB_READ_WRITE_TOKEN`.

### 3. Khai báo phía máy chủ

Chép `packages/server/config.sao-luu.example.json` thành `config.sao-luu.json`
(đặt cạnh `config.central.json`), rồi điền `url`, `token` và `mat_khau`.

File đó **đã bị gitignore** — cố ý tách khỏi `config.central.json` vì file kia
đang được đưa lên git, mà lỡ tay commit chìa khoá một lần là nó nằm vĩnh viễn
trong lịch sử kho mã.

### 4. Thử trọn vòng

```bash
cd packages/server && dart run bin/sao_luu.dart --config config.central.json thu
```

Lệnh này đẩy một bản lên, tải chính bản đó về, giải mã, so từng byte, và thử
luôn xem mật khẩu sai có bị từ chối không. Chạy được là đường về thông.

## Dùng hằng ngày

Máy chủ tự sao lưu mỗi đêm theo giờ khai trong cấu hình. Ngoài ra:

```bash
dart run bin/sao_luu.dart -c config.central.json kiem-tra    # thử kết nối
dart run bin/sao_luu.dart -c config.central.json chay        # sao lưu ngay
dart run bin/sao_luu.dart -c config.central.json liet-ke     # xem có những bản nào
dart run bin/sao_luu.dart -c config.central.json khoi-phuc <ten-ban>
dart run bin/sao_luu.dart -c config.central.json mo data/sao-luu/<ten>.canxe
```

Trong phần mềm, tài khoản chủ xem được trạng thái ở `/api/sao-luu/trang-thai` và
bấm chạy ngay bằng `/api/sao-luu/chay`.

**Khôi phục không tự đè lên cơ sở dữ liệu đang chạy.** Nó ghi ra một file mới rồi
bảo bạn tự đổi chỗ. Khôi phục nhầm bản là mất trắng dữ liệu từ lúc sao lưu tới
giờ — mà đúng phần đó lại là phần chưa có bản sao nào.

## Vài điều nên biết

- **Gói được cắt thành nhiều phần** ~2 MB. Hàm trên Vercel chỉ nhận tối đa 4,5 MB
  mỗi lần gọi; không cắt thì hôm nay chạy được, vài năm nữa dữ liệu lớn lên là
  sao lưu hỏng trong im lặng.
- **Phần mô tả được ghi sau cùng.** Bản chưa có nó bị coi là chưa xong và bị bỏ
  qua, nên đứt mạng giữa chừng chỉ để lại rác vô hại chứ không tạo ra một bản
  thiếu ruột mà trông vẫn lành lặn.
- **Bản chụp dùng `VACUUM INTO`**, không chép file. Cơ sở dữ liệu đang bật WAL:
  chép mỗi file `.db` là ra một bản thiếu giao dịch gần đây, mà mở lên vẫn không
  báo lỗi gì.
- **Vẫn giữ 7 bản ngay trên ổ đĩa** máy chủ. Hỏng lúc 8 giờ sáng mà mạng đứt thì
  bản ở ổ đĩa là thứ duy nhất dùng được ngay.
- **Gói tài khoản Vercel**: bản Hobby ghi rõ chỉ dành cho việc phi thương mại.
  Dùng cho kho hàng là việc kinh doanh, nên nếu định chạy lâu dài thì tính tới
  bản Pro, hoặc đổi sang chỗ khác — phần mã ở đây chỉ cần đổi `url` và `token`.
