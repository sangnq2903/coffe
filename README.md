# Hệ thống CÂN XE

Phần mềm cân xe cho nhiều kho, dựng bằng Flutter (giao diện) và Dart (máy chủ),
nối các máy với nhau qua mạng Tailscale.

Tính năng đầu tiên: **cân xe** — cân lần 1, cân lần 2, tính khối lượng hàng và
khối lượng thành phẩm quy đổi theo tỷ lệ.

---

## 1. Mô hình hệ thống

```
        ┌──────────────────────────────────────────────────────┐
        │  MÁY CHỦ TRUNG TÂM  —  100.76.81.118:9080            │
        │  • Cơ sở dữ liệu gộp của mọi kho                     │
        │  • Nhận số cân realtime do các trạm đẩy lên          │
        │  • Phục vụ luôn giao diện web                        │
        └───────▲──────────────────▲───────────────────▲───────┘
                │ Tailscale        │ Tailscale         │
    ┌───────────┴──────┐  ┌────────┴─────────┐  ┌──────┴────────┐
    │ TRẠM CÂN KHO 01  │  │ TRẠM CÂN KHO 02  │  │ Máy văn phòng │
    │ COM3 ── đầu cân  │  │ COM1 ── đầu cân  │  │ (chỉ xem/nhập)│
    │ :9080            │  │ :9080            │  └───────────────┘
    └───────▲──────────┘  └──────────────────┘
            │ Wi-Fi / Tailscale
    ┌───────┴────────┐
    │ Điện thoại     │  ← cân và lưu ngay tại bàn cân
    └────────────────┘
```

| Phần | Đáp ứng bởi |
|---|---|
| **Phần 1** — máy nối trạm cân, cân và lưu dữ liệu của trạm đó | `server` chạy vai trò `station`: đọc cổng COM, có cơ sở dữ liệu riêng, cân được cả khi mất mạng |
| **Phần 2** — máy chủ 100.76.81.118 lưu dữ liệu nhiều kho, các máy khác lấy và lưu qua máy chủ này | `server` chạy vai trò `central` + đồng bộ hai chiều theo mốc thời gian |
| **Phần 3** — app điện thoại nối tới server có gắn trạm cân để cân và lưu | Cùng một mã nguồn Flutter, mở bằng trình duyệt điện thoại hoặc build APK |
| **Màn hình số cân nhảy liên tục** | Server trạm đọc COM → WebSocket `/ws/scale?station=` → app vẽ lại mỗi khung |
| **In phiếu cân** | Xuất PDF khổ A5 ngang (có dấu tiếng Việt), in thẳng từ web/Windows/điện thoại hoặc tải file gửi khách |
| **Đăng nhập & phân quyền** | Tài khoản quản lý tổng thấy mọi kho; tài khoản trạm chỉ thấy kho được gán |

---

## 1b. Đăng nhập và phân quyền

Mọi lời gọi API và WebSocket đều bắt đăng nhập. Chỉ file giao diện web là để mở —
chặn cả chúng thì trình duyệt không tải nổi chính màn hình đăng nhập.

### Hai loại tài khoản

| Vai trò | Phạm vi |
|---|---|
| **Quản lý tổng** | Toàn bộ kho, mọi chức năng, tạo và xoá được tài khoản khác |
| **Nhân viên trạm cân** | Chỉ những kho được gán: phiếu cân, số cân realtime, đồng bộ |

Giới hạn được **chặn ở máy chủ**, không phải giấu trên giao diện. Tài khoản kho 1
có gõ thẳng địa chỉ phiếu cân của kho 2 cũng nhận về lỗi 403.

Quan trọng hơn: **luồng đồng bộ cũng bị giới hạn theo phạm vi**, nên ổ cứng máy ở
kho 1 không còn chứa dữ liệu của kho 2 nữa. Nếu chỉ giấu trên màn hình thì ai mở
được file cơ sở dữ liệu vẫn đọc hết.

### Lần chạy đầu tiên

Chưa có tài khoản nào thì mở web ra sẽ thấy màn hình **Tạo tài khoản quản lý
tổng**. Đường dẫn tạo tài khoản đầu tiên tự khoá lại ngay khi đã có người dùng.

### Máy trạm cân đăng nhập thế nào

Máy trạm cũng qua cửa đăng nhập như người, không có cửa sau riêng. Sau khi có tài
khoản tổng:

1. Vào **Cá nhân → Quản lý tài khoản → Thêm**
2. Chọn quyền **Nhân viên trạm cân**, tích đúng kho của máy đó
3. Điền tên đăng nhập và mật khẩu vừa tạo vào `config.json` của máy trạm:

```jsonc
"central": {
  "url": "http://100.76.81.118:9080",
  "username": "tram01",
  "password": "..."
}
```

Chưa khai thì **trạm vẫn cân và lưu bình thường**, chỉ là chưa đẩy dữ liệu lên
trung tâm — bàn cân không được phép đứng bánh vì một dòng cấu hình chưa điền.

### Bảo mật

- Mật khẩu băm bằng **PBKDF2-HMAC-SHA256**, 120.000 vòng, muối riêng từng người
- Phiên đăng nhập ký bằng HMAC, **giữ 30 ngày** để máy ở bàn cân không phải đăng
  nhập lại mỗi ca
- **Khoá ký sinh ngẫu nhiên lần chạy đầu**, cất trong cơ sở dữ liệu, không nằm
  trong mã nguồn — repo này công khai, khoá mà lọt vào là ai cũng ký được phiên giả
- Mỗi máy chủ một khoá riêng: phiếu phiên cấp ở máy nào chỉ dùng được ở máy đó
- Phiếu phiên đi qua địa chỉ với WebSocket (trình duyệt không cho gắn tiêu đề),
  nên phần ghi nhật ký đã che chuỗi này lại
- Người lập phiếu lấy từ tài khoản đang đăng nhập, client không gửi lên được nữa

---

## 2. Dữ liệu một phiếu cân

| Trường | Ghi chú |
|---|---|
| Thông tin khách hàng | Chọn từ danh mục hoặc gõ tên mới, hệ thống tự thêm vào danh mục |
| Thông tin xe | Biển số (tự chuẩn hoá), tài xế, KL bì đăng ký |
| Loại hàng | Trấu, cà nhân, cà tươi, cà khô — danh mục mở, thêm được loại mới |
| Tỷ lệ thành phẩm | Điền sẵn theo loại hàng, sửa được trên từng phiếu |
| Cân lần 1 | Kèm thời điểm cân |
| Cân lần 2 | Kèm thời điểm cân |
| KL hàng | `|cân lần 1 − cân lần 2|` — đúng cho cả nhập và xuất |
| KL thành phẩm | `KL hàng × tỷ lệ thành phẩm` |

Ngoài ra mỗi phiếu còn có: số phiếu (`KHO01-260903-0001`), mã trạm, chiều
nhập/xuất, trạng thái, ghi chú, người lập.

---

## 3. Cấu trúc dự án

```
coffe/
├── packages/
│   ├── shared/     Model, giải mã khung cân, API client — dùng chung
│   ├── server/     Máy chủ Dart, chạy được vai trò central hoặc station
│   └── app/        Ứng dụng Flutter: web + Windows + Android
└── scripts/        Script build và chạy
```

---

## 4. Chạy lần đầu

### 4.1. Yêu cầu

- Flutter SDK 3.32 trở lên (đã có sẵn Dart 3.8)
- Tailscale đã cài và đăng nhập trên mọi máy
- Windows 10/11 cho máy trạm cân (phần đọc cổng COM dùng API Windows)

### 4.2. Build giao diện web

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-web.ps1
```

Script build bản web rồi chép vào `packages/server/web` để máy chủ phục vụ luôn.
Chạy lại mỗi khi sửa code trong `packages/app`.

### 4.3. Cài chạy tự động cùng Windows (khuyến nghị cho máy ở kho)

Máy ở kho không nên phụ thuộc vào việc ai đó nhớ mở cửa sổ lệnh. Chạy **một lần**
bằng PowerShell quyền Administrator:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\cai-dat-tu-khoi-dong.ps1
```

Lệnh này đăng ký hai tác vụ Windows chạy dưới tài khoản SYSTEM, khởi động ngay
khi máy bật (không cần ai đăng nhập) và **tự chạy lại sau 1 phút nếu lỗi**:

| Tác vụ | Vai trò |
|---|---|
| `CanXe-TrungTam` | máy chủ trung tâm, cổng 9080 |
| `CanXe-TramCan` | trạm cân đọc cổng COM, cổng 9081 |

Chỉ cài một vai trò: thêm `-ChiTramCan` (máy ở kho) hoặc `-ChiTrungTam` (máy văn phòng).

Tác vụ gọi **thẳng** `packages\serveruild\canxe-server.exe`, không qua
`powershell.exe` — bớt một lớp trung gian, và server tự ghi nhật ký qua tham số
`--log-file`.

> **Đọc trạng thái tác vụ phải dùng PowerShell quyền Administrator.** Tác vụ chạy
> dưới SYSTEM có quyền truy cập hạn chế, nên `Get-ScheduledTask CanXe-*` ở cửa sổ
> thường sẽ trả về **rỗng dù dịch vụ vẫn đang chạy**. Đừng vội kết luận là nó bị
> xoá — kiểm tra bằng cách khác chắc chắn hơn:

```powershell
Get-Process canxe-server; Get-NetTCPConnection -State Listen -LocalPort 9080,9081
```

Nhật ký nằm ở `logs	rung-tam.log` và `logs	ram-can.log`, tự cắt khi vượt 5 MB.

Gỡ bỏ: `.\scripts\go-tu-khoi-dong.ps1` (cũng cần quyền Administrator).

**Nếu web báo "chưa kết nối máy chủ"**, kiểm tra theo thứ tự:

1. `Get-Process canxe-server` — không có tiến trình nào nghĩa là dịch vụ chưa chạy
2. `Get-Content .\logs	ram-can.log -Tail 30` — xem server báo lỗi gì
3. Cổng COM có bị chương trình khác chiếm không (xem mục 5)

### 4.4. Chạy tay (khi phát triển hoặc muốn xem log trực tiếp)

### Máy chủ trung tâm (100.76.81.118)

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\chay-trung-tam.ps1
```

Mở trình duyệt: **http://100.76.81.118:9080**

### Máy trạm cân (máy nối đầu cân)

Chép file mẫu rồi sửa:

```powershell
Copy-Item packages\server\config.station.example.json packages\server\config.json
```

Cần sửa ít nhất:

```jsonc
{
  "station": {
    "code": "KHO01",                                 // mã kho, không trùng kho khác
    "name": "Trạm cân kho 01",
    "public_base_url": "http://100.x.y.z:9080"       // địa chỉ Tailscale của CHÍNH máy này
  },
  "central": { "url": "http://100.76.81.118:9080" },
  "scale":   { "port": "COM3", "baud_rate": 9600 }   // xem Device Manager
}
```

Chạy:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\chay-tram-can.ps1 -Config config.json
```

### 4.5. Chạy thử khi chưa có đầu cân

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\chay-tram-can.ps1 -GiaLap
```

Đầu cân giả lập sẽ diễn một chu kỳ cân xe hoàn chỉnh (xe lên bàn cân → số nhảy
dần → đứng yên → xe xuống) để thử toàn bộ luồng nghiệp vụ.

### 4.6. Điện thoại

Mở trình duyệt điện thoại vào địa chỉ Tailscale của trạm cân hoặc của máy chủ
trung tâm, ví dụ `http://100.76.81.118:9080`. Giao diện tự co theo màn hình.

Muốn có app cài đặt được:

```powershell
cd packages\app
flutter build apk --release
```

Trong app, vào **Cài đặt → Địa chỉ máy chủ** rồi nhập địa chỉ Tailscale.

---

## 5. Cấu hình đầu cân

Mục `scale` trong file cấu hình của trạm:

| Khoá | Ý nghĩa |
|---|---|
| `port` | Cổng COM, ví dụ `COM3`. Xem Device Manager → Ports (COM & LPT) |
| `baud_rate`, `data_bits`, `stop_bits`, `parity` | Phải khớp với cài đặt trên đầu cân |
| `protocol` | `auto` (mặc định: thử Keli → Toledo → ASCII), `keli`, `toledo`, `ascii`, `custom` |
| `divisor` | Đầu cân gửi `0001234` nhưng thực tế là 123.4 kg → đặt `10` |
| `custom_pattern` | Regex tự khai khi đầu cân dùng giao thức lạ, ví dụ `"W=(-?\\d+)"` |
| `stable_tolerance`, `stable_samples` | Khi đầu cân không tự báo ổn định: lệch dưới `stable_tolerance` kg trong `stable_samples` lần đọc liên tiếp thì coi là đứng yên |
| `data_timeout_seconds` | Không nhận được khung nào trong bấy nhiêu giây thì báo mất kết nối (mặc định 5). Cổng COM vẫn mở được kể cả khi đầu cân tắt nguồn, nên nếu thiếu mốc này màn hình sẽ giữ nguyên số cũ như thể vẫn đang cân |

### Đầu cân Keli D2008FA (đang dùng ở kho 01)

```jsonc
"scale": { "port": "COM5", "baud_rate": 2400, "protocol": "keli" }
```

Chú ý **2400 baud**, không phải 9600 như mặc định của phần lớn đầu cân — đây là
thông số dễ mất nhiều giờ để mò ra. Đầu cân phải bật chế độ truyền liên tục
**TF=0**.

Khung dữ liệu: `STX + dấu + 6 chữ số + vị trí thập phân + checksum XOR + ETX`.
Ví dụ 60 kg:

```
02   2b   30 30 30 30 36 30   30   31 44
STX   +    0  0  0  0  6  0    0   "1D"
     dấu  └── 6 chữ số ───┘  thập phân  checksum
```

Byte thứ 8 là **số chữ số thập phân**, không phải một phần của số cân — đọc bằng
chế độ `ascii` sẽ ra sai (60 kg thành 600). Vì vậy phải để `"protocol": "keli"`
(hoặc `auto`, chế độ này thử Keli đầu tiên và có kiểm tra checksum nên không
nhận nhầm).

**Nếu số cân hiện sai hoặc không hiện:** màn hình cân có dòng chữ nhỏ hiển thị
đúng chuỗi thô nhận từ cổng COM. Hoặc chạy công cụ dò cổng — nó thử lần lượt các
tốc độ truyền, in dữ liệu thô kèm mã hex và gợi ý luôn cấu hình đúng:

```bash
cd packages/server && dart run bin/do_cong.dart COM5
```

Lưu ý: phải **tắt máy chủ trạm cân** trước khi dò, vì Windows không cho hai
chương trình cùng mở một cổng COM.

---

## 5b. Chọn trạm cân và in phiếu

**Chọn trạm.** Bấm vào tên kho ở thanh tiêu đề (hoặc ngay trên bảng số cân) để
chuyển sang kho khác. Danh sách chỉ hiện những trạm **có đầu cân** — máy chủ
trung tâm cũng nằm trong danh mục kho nhưng không có bàn cân nên không chọn được.
Khi mở app từ máy chủ trung tâm, hệ thống tự chọn sẵn một trạm đang online.

**In phiếu.** Có ba chỗ in:

- Ngay sau khi chốt cân lần 2, phiếu tự mở ra — bấm **IN PHIẾU CÂN**
- Bấm vào bất kỳ dòng nào trong "Phiếu cân gần đây" hoặc màn hình *Phiếu cân*
- Nút máy in nhỏ ở cuối mỗi dòng phiếu đã hoàn thành

Phiếu ra khổ **A5 ngang** (nửa tờ A4) gồm: số phiếu, kho, khách hàng, biển số,
tài xế, loại hàng, tỷ lệ thành phẩm, bảng hai lần cân, KL hàng, KL thành phẩm và
ba ô ký tên. Trên điện thoại có thêm nút **Chia sẻ**, trên web là **Tải PDF**.

---

## 5c. Module chấm công — luật tính lương

Đây là các quy tắc nghiệp vụ đã chốt. Mọi luật dưới đây đều có kiểm thử tự động
trong `packages/shared/test/payroll_calculator_test.dart`; sửa luật mà quên sửa
test thì test sẽ đỏ.

### Cấu trúc

| Khái niệm | Nghĩa |
|---|---|
| **Đoàn** | Một mùa vụ. Đoàn thuộc **công ty**, không thuộc kho nào. Mỗi mùa lập đoàn mới; **một người chỉ thuộc một đoàn** |
| **Kho đang làm** | Thuộc tính của **từng người**, đổi được bất cứ lúc nào bằng chức năng **Chuyển kho** (chuyển một người hoặc cả tổ) |
| **Giai đoạn lương** | Đầu mùa và mùa rộ — khác nhau **mức lương**, dùng chung danh sách người. Mốc chuyển khai bằng ngày |
| **Mức lương** | Bảng dùng chung ("Thợ chính", "Thợ phụ"). Ai có thoả thuận riêng thì **đặt giá riêng**, không bị ảnh hưởng khi sửa bảng chung |
| **Giờ làm** | Khai theo giai đoạn: giờ vào ca, giờ tan ca, tổng giờ nghỉ giữa ca → **giờ chuẩn/ngày**. Đầu mùa 7:00–17:00 nghỉ trưa 1,5 giờ = 8,5 giờ; mùa rộ 7:00–22:00 nghỉ trưa + tối 3 giờ = 12 giờ |

### Tính lương

- **Lương tính theo tháng**, chấm công ghi **theo ngày** (chỉ để biết ai đi ai nghỉ)
- **Ngày công của tháng = số ngày của tháng** (28/29/30/31), kể cả chủ nhật
- **Không có nghỉ phép có lý do** — nghỉ ngày nào mất công ngày đó
- **Nghỉ vài giờ trong ngày** thì ghi số giờ nghỉ; công của ngày = (giờ chuẩn −
  giờ nghỉ) ÷ giờ chuẩn. Đầu mùa nghỉ 2 giờ → hưởng 6,5/8,5 công; cùng 2 giờ đó
  ở mùa rộ chỉ mất 2/12 công. Không làm tròn — nhập bao nhiêu tính bấy nhiêu
- Làm quá giờ tan ca là **tăng ca**, ghi tiền riêng (lớp 4), không cộng vào công
- Tháng vắt qua hai giai đoạn thì cộng hai phần:

```
Lương T10 = 15/31 × lương đầu mùa  +  16/31 × lương mùa rộ
```

### Trần ứng lương

```
Trần ứng   = 50% × (lương đã làm được tới hôm nay + tăng ca + phụ cấp − tiền phạt)
Còn được ứng = Trần ứng − đã ứng trong tháng
```

- Trần **đặt lại mỗi tháng** và **nhích lên theo từng ngày** người đó đi làm
- **Nợ dồn từ tháng trước KHÔNG làm trần tháng sau cao lên.** Tháng 9 ứng hết
  trần rồi treo lại một nửa, sang tháng 10 trần vẫn chỉ là nửa lương tháng 10
- **Ứng lương và thanh toán không tính vào thu nhập.** Lẫn vào thì cứ ứng một
  lần trần lại cao lên, ứng được vô hạn
- Vượt trần: **cảnh báo nhưng vẫn cho ứng** nếu nhập lý do — mọi lần vượt đều
  vào sổ để tra lại
- Tiền ứng làm tròn xuống bội số 10.000 đ cho khớp việc đưa tiền mặt

### Thanh toán và cảnh báo

- **Trong mùa chỉ ứng; quyết toán một lần vào cuối mùa.** Máy chủ chặn khoản
  thanh toán khi đoàn còn đang diễn ra — phải đóng đoàn trước
- Ai **đã nhận vượt** công đã làm thì số dư âm và bị cảnh báo — không im lặng.
  Tab **Tiền** đếm ra số người như vậy ngay trên đầu danh sách

### Màn hình tiền

Tab **Tiền** của đoàn: tổng thu nhập / đã ứng / đã thanh toán / còn phải trả,
kèm từng người với trần ứng và số còn được ứng của tháng đang xem.

- Bấm vào một người ra **sổ tiền**: công nợ cả mùa, từng tháng bung ra xem chi
  tiết (lương theo công, tăng ca, phụ cấp, trừ tiền, trần ứng, đã ứng, còn ứng)
  và danh sách từng khoản
- Hộp thoại **ứng lương vừa nhập vừa hỏi máy chủ** còn được ứng bao nhiêu, nên
  thấy cảnh báo *trước* khi bấm ghi. Có nút "Ứng tối đa" điền sẵn số tròn bội
  số 10.000
- Vượt trần thì nút đổi thành **"Vẫn ứng"** màu đỏ và **bắt nhập lý do** — chủ
  quyết định phá luật thì phải để lại vết, vì đây là chỗ dễ thất thoát nhất
- Sửa một khoản ứng **không bị đếm tiền cũ hai lần**: kiểm tra trần loại chính
  khoản đang sửa ra khỏi phép tính

### Báo cáo và quyết toán cuối mùa

Tab **Báo cáo** có hai bảng, cả hai **in được ra giấy** (PDF A4, có ô ký) — bảng
lương là thứ đưa cho người ta xem rồi ký nhận, xem trên màn hình thôi chưa dùng
được.

- **Bảng lương tháng**: mỗi người một dòng — công, lương, tăng ca, phụ cấp, trừ
  tiền, thu nhập, đã ứng, còn lại — kèm dòng tổng
- **Quyết toán mùa**: gộp mọi tháng, cột còn lại và trạng thái từng người (chưa
  trả / đã quyết toán / đã nhận đủ / nhận vượt)
- **Tiền công theo kho**: chia theo **số công làm ở từng kho**, nên người chuyển
  kho giữa mùa vẫn tách được và tổng các kho luôn khớp tổng lương. Đây là chỗ
  cái quyết định "mỗi ngày chấm công ghi kèm kho" trả lãi

Luồng cuối mùa:

1. **Chốt mùa** — chỉ đóng đoàn để mở cửa cho quyết toán, *không* tự trả tiền.
   Chốt rồi không ứng lương được nữa; bấm nhầm thì **mở lại mùa** được
2. **Quyết toán** — ghi khoản thanh toán bằng **đúng số còn phải trả** của từng
   người, không nhận số tự nhập: quyết toán là phép trừ, gõ tay chỉ thêm chỗ sai
3. Ai **đã nhận vượt** thì bị bỏ qua kèm lý do "phải thu lại chứ không trả thêm";
   ai đã nhận đủ cũng bỏ qua thay vì ghi khoản 0 đồng

### Hai điều dễ làm sai

**Sửa bảng giá không được làm đổi lương đã tính.** Mỗi ngày chấm công lưu kèm
mức lương tháng tại thời điểm chấm. Lương đã trả rồi mà con số trong máy tự
nhảy thì không ai đối chiếu nổi. Muốn tính lại quá khứ phải bấm nút riêng.

**Lương tháng phải gộp rồi mới chia, không cộng tiền từng ngày.** Chia
8.000.000 cho 30 ngày ra số lẻ vô hạn; cộng từng ngày lại thì đi làm đủ tháng
không ra đúng 8.000.000. Người ta đếm tiền nên lệch vài đồng cũng thành thắc mắc.

### Chấm công theo ngày

Màn hình đoàn mở ra là vào ngay tab **Chấm công** — đó là việc làm hằng ngày.

- Một ngày có **ba trạng thái** cho mỗi người: đi làm (✓), nghỉ (✕) và **chưa
  chấm** (ô trống). "Chưa chấm" là việc còn dở, "nghỉ" là đã chốt — lẫn hai cái
  này thì cuối mùa không biết đã chấm đủ chưa.
- Đoàn đông thì dùng **ô tìm tên** để chấm riêng một người (gõ không dấu cũng
  ra: "tinh" tìm được "Tình") và ba nhóm **Tất cả / Chưa chấm / Đã chấm**. Nhóm
  "Chưa chấm" là danh sách việc còn phải làm — chấm xong ai thì người đó rời
  khỏi nhóm, hết danh sách là xong ngày.
- Hai nút chấm hàng loạt chỉ tác động lên **những người đang hiện**, và nhãn ghi
  rõ số người ("Đi làm 5 người") khi đang lọc hoặc đang tìm.
- Người đi làm nhưng không đủ ca thì bấm nút đồng hồ, nhập **số giờ nghỉ**. Giờ
  nghỉ bằng hoặc vượt giờ chuẩn thì bị chặn — nghỉ hết ca thì chấm là nghỉ.
  Bấm "đi làm" lại (kể cả "đi làm hết") **không xoá** giờ nghỉ đã ghi; chấm là
  nghỉ cả ngày thì giờ nghỉ tự về 0.
- Mỗi ngày chấm công **chép lại giờ chuẩn lúc chấm**, giống mức lương: đổi giờ
  làm của giai đoạn hôm nay không làm đổi công tháng trước, trừ khi bấm "Tính
  lại lương".
- Bấm là ghi ngay, không có nút "Lưu". Chấm cả chục người mà dồn lại rồi lưu thì
  chỉ cần đóng màn hình là mất hết mà không ai biết.
- **Ngày chưa thuộc giai đoạn lương nào thì không chấm được** — không tra ra
  lương thì ghi vào cũng vô nghĩa. Màn hình chỉ thẳng sang tab cấu hình.
- **Người chưa khai giá thì bị bỏ qua, kèm tên và lý do.** Một người mới vào
  chưa gán mức lương không được làm cả đoàn không chấm công được, nhưng phải báo
  rõ chứ không im lặng.
- Người **vào làm sau** không hiện ở ngày trước đó, người **đã nghỉ** không hiện
  ở ngày sau khi nghỉ. Ai đã có bản ghi ngày đó thì luôn hiện, kể cả nay đã nghỉ.

Tab **Bảng tháng** là bảng người × ngày để đối chiếu và trả lương: mỗi ô một
ngày, cuối dòng là số công và lương đã làm được, cuối bảng là tổng.

**Nút "Tính lại lương"** ở tab bảng tháng là cái nút riêng mà mục "Hai điều dễ
làm sai" bên dưới nói tới: bình thường ngày đã chấm giữ nguyên mức lương lúc
chấm, bấm nút này mới lấy lại theo bảng giá hiện tại. Dùng khi khai sai giá rồi
mới phát hiện; nó báo lại đúng những ngày nào đổi từ số nào sang số nào.

### Chuyển kho

Người trong đoàn chuyển qua lại giữa kho 1 và kho 2 tuỳ thời điểm, nên:

- **Kho gắn với từng người, không gắn với đoàn.** Chuyển kho chỉ đổi kho *hiện
  tại* của người đó.
- **Mỗi ngày chấm công lưu kèm kho tại thời điểm chấm.** Chuyển kho hôm nay
  không làm đổi số liệu tháng trước, và sau này cộng ra được tiền công mà từng
  kho đã gánh.
- **Phần lương không giới hạn theo kho.** Tài khoản nào đăng nhập được cũng chấm
  công và xem lương của cả công ty — người làm ở hai kho thì cắt theo kho sẽ
  tính thiếu ngày. Riêng **phiếu cân vẫn tách theo kho** như cũ.

Hệ quả cần biết: gói đồng bộ phần lương đi về **mọi** kho, nên dữ liệu lương của
cả công ty nằm trên ổ cứng máy ở từng kho. Phiếu cân thì không.

---

## 6. Cách hệ thống giữ dữ liệu an toàn

- **Mất mạng vẫn cân được.** Trạm cân có cơ sở dữ liệu riêng. Bản ghi mới được
  đánh dấu chờ đẩy, mạng thông trở lại là tự đồng bộ lên trung tâm.
- **Không trùng số phiếu.** Số phiếu do server cấp theo bộ đếm từng trạm, từng
  ngày, trong một transaction.
- **Không lẫn dữ liệu giữa các kho.** Khoá chính là UUID, mỗi phiếu mang mã trạm.
- **Không có phiếu mồ côi.** Một xe chỉ được có một phiếu chờ cân lần 2 tại một
  trạm; lập phiếu trùng biển số sẽ bị chặn kèm số phiếu đang dở dang.
- **Không chốt nhầm lúc số đang nhảy.** Nút chốt chỉ bật khi đầu cân báo số đã
  đứng yên. Khi đầu cân hỏng, có công tắc "Nhập số cân bằng tay" để không phải
  dừng cả kho.
- **Mất tín hiệu là báo ngay.** Quá 5 giây không có khung mới, màn hình chuyển
  sang trạng thái mất kết nối thay vì giữ số cũ.

---

## 7. Kiểm thử

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\kiem-tra.ps1
```

Chạy phân tích mã cả ba package và bộ kiểm thử của `canxe_shared` (giải mã
khung cân theo từng giao thức, ghép khung từ luồng byte, phát hiện số đứng yên,
công thức tính khối lượng).

---

## 8. Mở cổng tường lửa

Máy chủ và máy trạm phải cho phép cổng 9080 đi qua Windows Firewall (chạy
PowerShell với quyền Administrator):

```powershell
New-NetFirewallRule -DisplayName "Can xe 9080" -Direction Inbound -Protocol TCP -LocalPort 9080 -Action Allow
```

---

## 8b. Tham số dòng lệnh của máy chủ

| Tham số | Ý nghĩa |
|---|---|
| `--config <file>` | File cấu hình JSON (mặc định `config.json`) |
| `--role central\|station` | Ghi đè vai trò trong file cấu hình |
| `--port <số>` | Ghi đè cổng HTTP |
| `--log-file <đường dẫn>` | Ghi nhật ký ra file — bắt buộc khi chạy dưới dạng tác vụ Windows vì lúc đó không có cửa sổ nào để xem |
| `--simulate` | Giả lập đầu cân, dùng khi chưa đấu nối phần cứng |
| `--web-root <thư mục>` | Thư mục chứa bản build Flutter web |

---

## 9. API tóm tắt

| Phương thức | Đường dẫn | Công dụng |
|---|---|---|
| GET | `/api/health` | Vai trò server, mã trạm, tình trạng đầu cân |
| GET | `/api/scale/current?station=` | Số cân hiện tại |
| WS | `/ws/scale?station=` | Luồng số cân realtime |
| WS | `/ws/station` | Trạm đẩy số cân lên trung tâm (chỉ có ở central) |
| GET/POST | `/api/customers`, `/api/vehicles`, `/api/goods-types` | Danh mục |
| GET/POST | `/api/tickets` | Danh sách và lập phiếu (cân lần 1) |
| POST | `/api/tickets/<id>/second-weigh` | Ghi cân lần 2 và chốt phiếu |
| POST | `/api/tickets/<id>/cancel` | Huỷ phiếu |
| GET/POST | `/api/sync/pull`, `/api/sync/push` | Đồng bộ giữa trạm và trung tâm |
