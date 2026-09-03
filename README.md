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
