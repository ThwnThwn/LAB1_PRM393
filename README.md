# FAP Attendance Assistant

Ứng dụng Lab 1 mô phỏng trọn luồng điểm danh bằng QR và OTP. Hệ thống gồm ba giao diện độc lập: ứng dụng Flutter Windows cho giảng viên, web check-in cho sinh viên và một web FAP mô phỏng để chốt Present/Absent. API dùng ASP.NET Core 8, Google Sheets là database chính và giao diện được cập nhật trực tiếp qua SignalR.

> Đây là dự án phục vụ demo học phần, không kết nối với FAP chính thức và không giả định người làm bài có quyền truy cập FAP thật. Chỉ nên sử dụng dữ liệu giả lập.

## Chức năng hiện có

- Thời khóa biểu tuần và chọn ca dạy đang thao tác.
- Import danh sách sinh viên từ CSV hoặc cấu hình Google Sheets.
- Mở và đóng từng phiên điểm danh.
- Mỗi lớp, môn, ngày và slot chỉ có một phiên; mở lại sẽ dùng cùng `SessionId` và giữ nguyên kết quả.
- QR và OTP 6 số tự đổi sau mỗi 10 giây.
- Tạm dừng đồng bộ QR, OTP và bộ đếm; mã đang giữ vẫn hợp lệ cho tới khi tiếp tục.
- Cổng web để sinh viên quét QR, nhập MSSV, email và OTP.
- Không giới hạn email FPT; chỉ yêu cầu địa chỉ email hợp lệ.
- Chống một MSSV điểm danh hai lần trong cùng một phiên.
- Chống một điện thoại điểm danh nhiều MSSV trong cùng phiên bằng cookie thiết bị
  `HttpOnly` và dấu vết mạng LAN; desktop cảnh báo realtime và cho phép giảng viên
  mở khóa ngoại lệ có lý do.
- Khi mở phiên, toàn bộ sinh viên mặc định là vắng; check-in thành công chuyển sang có mặt.
- Dashboard chỉ dùng hai trạng thái có mặt và vắng, kèm tỷ lệ chuyên cần.
- Cập nhật dashboard trực tiếp bằng SignalR, có polling dự phòng.
- Lưu roster, phiên, trạng thái, thiết bị và nhật ký chỉnh sửa trực tiếp trong Google Sheets.
- Không dùng database cục bộ; backend chỉ giữ trạng thái OTP và kết nối SignalR tạm thời trong RAM.
- Xuất CSV riêng cho từng buổi học.
- Trang web giảng viên **`/fap-demo/`** là cổng FAP mô phỏng độc lập, tự cập nhật từ desktop/
  điện thoại mỗi 5 giây và cho phép lưu Present/Absent về Google Sheets.

## Kiến trúc

| Thành phần | Công nghệ | Địa chỉ mặc định |
|---|---|---|
| Ứng dụng giảng viên | Flutter Windows Desktop | Ứng dụng `fap_attendance_app` |
| API và SignalR | ASP.NET Core 8 | `http://localhost:8080` |
| Cổng sinh viên | HTML/CSS/JavaScript | `http://<IP-LAN>:8080/student/` |
| Cổng FAP mô phỏng | HTML/CSS/JavaScript | `http://<IP-LAN>:8080/fap-demo/` |
| Database chính | Google Sheets qua Apps Script | Web App URL do giảng viên cấu hình |

Luồng dữ liệu chính:

```text
Giảng viên mở phiên trên Flutter
            ↓
ASP.NET Core ghi dữ liệu nghiệp vụ vào Google Sheets
            ↓
Sinh viên quét QR → nhập OTP → gửi check-in
            ↓
Google Sheets lưu và trả về toàn bộ dữ liệu nghiệp vụ
            ↓
SignalR cập nhật desktop, cổng FAP mô phỏng tự tải snapshot mới
            ↓
Cổng FAP mô phỏng đối chiếu MSSV và lưu P/A vào Google Sheets
```

## Yêu cầu môi trường

- Windows 10/11.
- Flutter SDK với Dart `>= 3.12.0`.
- .NET SDK 8.0 trở lên.
- Google Chrome hoặc Microsoft Edge.
- Điện thoại và máy giảng viên cùng Wi-Fi khi chạy `run.cmd`; hoặc chỉ cần cùng có
  Internet khi chạy `run-public.cmd`.

Kiểm tra nhanh:

```powershell
flutter doctor
dotnet --version
```

## Chạy nhanh trên Windows

Tại thư mục dự án:

```powershell
flutter pub get
.\run.cmd
```

`run.cmd` sẽ tự động:

1. Tìm IP LAN của máy.
2. Khởi động backend C# tại cổng `8080`.
3. Chờ API sẵn sàng.
4. Mở ứng dụng Flutter Windows dành cho giảng viên.
5. Gắn IP LAN vào QR để điện thoại truy cập được cổng sinh viên.
6. Mở cổng FAP mô phỏng trên trình duyệt mặc định.

Nhấn `Ctrl+C` trong cửa sổ chạy để dừng Flutter và backend do script khởi tạo.

### Demo qua Internet, không cần cùng Wi-Fi

Chạy chế độ public bằng Cloudflare Quick Tunnel:

```powershell
.\run-public.cmd
```

Script sẽ tự cài `cloudflared` miễn phí bằng `winget` nếu máy chưa có, khởi động
backend, tạo URL HTTPS tạm thời `*.trycloudflare.com`, sao chép đường dẫn cổng sinh
viên vào clipboard, tự mở cổng FAP mô phỏng cho giảng viên và mở Flutter Windows với
đúng URL public. Sinh viên chỉ cần có Internet, có thể dùng Wi-Fi hoặc 4G/5G ở mạng khác.

Trong chế độ này, API và cổng FAP mô phỏng của giảng viên được bảo vệ bằng token ngẫu
nhiên chỉ tồn tại trong lần chạy hiện tại. Launcher dùng token một lần để thiết lập cookie
`HttpOnly` cho trình duyệt; không chia sẻ đường dẫn này cho sinh viên. Backend cũng đọc
forwarded headers từ tiến trình tunnel cục bộ để phân biệt địa chỉ thiết bị phía sau
Cloudflare. URL hết hiệu lực khi đóng Flutter hoặc nhấn `Ctrl+C`.

> Quick Tunnel chỉ dành cho demo/thử nghiệm. Chỉ sử dụng dữ liệu giả lập và không
> chia sẻ URL sau khi kết thúc buổi demo.

## Đóng gói thành ứng dụng Windows

Tạo bản portable tự chứa Flutter, backend .NET, cổng sinh viên và cổng FAP mô phỏng:

```powershell
.\package-windows.cmd
```

File phát hành được tạo tại:

```text
dist\FAP-Attendance-Windows-x64.zip
```

Máy nhận chỉ cần giải nén toàn bộ file ZIP rồi bấm đúp `Start FAP Attendance.cmd`;
không cần cài Flutter SDK hoặc .NET Runtime. Khi Windows Firewall hỏi quyền ở lần
chạy đầu, cho phép ứng dụng truy cập **Private networks** để điện thoại cùng Wi-Fi
mở được cổng sinh viên trong mã QR.

Nếu sinh viên không ở cùng mạng, bấm đúp `Start FAP Attendance Public.cmd`. Launcher
sẽ tạo tunnel HTTPS và tự truyền URL public vào ứng dụng Windows; không cần build lại.

Không gửi riêng `fap_attendance_app.exe`, vì bản Windows còn cần thư mục `data`,
Flutter DLL, backend và các file web đi kèm. URL trong QR được xác định theo IP LAN
lúc ứng dụng chạy, nên gói có thể chuyển sang máy hoặc mạng khác.

### Chạy thủ công

Terminal thứ nhất:

```powershell
dotnet run --project server\Attendance.Api.csproj
```

Terminal thứ hai (thay IP bằng địa chỉ LAN của máy):

```powershell
flutter run -d windows `
  --dart-define=ATTENDANCE_SERVER_URL=http://192.168.1.10:8080
```

Nếu chỉ test trên cùng máy, có thể dùng `http://127.0.0.1:8080`. Không đưa `localhost` vào QR cho điện thoại vì `localhost` trên điện thoại chính là điện thoại, không phải máy giảng viên.

## Luồng demo đề xuất

1. Trên trang **Thời khóa biểu tuần**, chọn tuần và lọc **Mã lớp điểm danh**
   (`SE1917`–`SE1920`).
2. Bấm đúng ca học trên lưới Slot 1–8 rồi chọn **Điểm danh lớp này**.
3. Nếu ca chưa có phiên, vào **Điểm danh QR & OTP 10s** và bấm **Mở điểm danh**.
   Nếu ca đã có phiên trong Google Sheets, desktop tự tải trạng thái khi chọn ca;
   bấm **Mở lại điểm danh** khi muốn tiếp tục nhận check-in vào chính phiên đó.
4. Sinh viên cùng Wi-Fi quét QR trên màn hình giảng viên.
5. Sinh viên nhập MSSV, email và OTP đang hiển thị rồi xác nhận.
6. Tên sinh viên xuất hiện ngay trên dashboard.
7. Nếu cùng điện thoại thử MSSV thứ hai, backend chặn yêu cầu; giảng viên chỉ mở
   khóa từ panel cảnh báo khi có lý do hợp lệ.
8. Có thể bấm **Tạm dừng QR & OTP** để giữ nguyên QR, OTP và số giây còn lại.
9. Bấm **Đóng điểm danh**; kết quả `PRESENT`/`ABSENT` hiện tại được giữ nguyên.
10. Chuyển sang cổng FAP mô phỏng mà launcher đã mở trên trình duyệt.
11. Trang tự nhận dữ liệu mới từ desktop/điện thoại. Có thể chọn Present/Absent rồi
    bấm **Lưu điểm danh**; thay đổi được ghi vào Google Sheets của bài demo.
12. Giữ desktop ở **Danh sách sinh viên**: sau khi bấm **Lưu điểm danh** trên web,
    trạng thái sẽ hiện trên desktop; đổi trạng thái trên desktop thì web cũng cập nhật
    trong tối đa 5 giây.
    Hai chiều vẫn đồng bộ sau khi đóng phiên, miễn là đang xem cùng một ca học.

## Google Sheets làm database chính

1. Tạo một Google Sheet mới, mở **Extensions → Apps Script**.
2. Trong ứng dụng, mở **Cấu hình Google Sheets** và sao chép đoạn Apps Script mẫu.
3. Deploy script dưới dạng Web App, quyền truy cập phù hợp với môi trường demo. Nếu đã
   deploy bản cũ, chọn **Manage deployments → Edit → New version → Deploy** để cập nhật.
4. Dán Web App URL vào ứng dụng và bấm **Kiểm tra & lưu**.
5. Backend kiểm tra kết nối rồi lưu URL. Các thao tác import, mở/đóng phiên và
   check-in chỉ được xác nhận thành công sau khi ghi được Google Sheets.
6. Apps Script tự tạo năm tab: `Rosters`, `Sessions`, `Attendance`,
   `DeviceBindings` và `AuditLog`.
7. Sau khi cấu hình, Sheet là nguồn duy nhất cho roster, phiên, điểm danh, thiết bị
   và audit log. Desktop và cổng FAP mô phỏng đều đọc cùng nguồn này.
8. Để có dữ liệu ngay khi demo, bấm **Tạo dữ liệu demo**. Lệnh tạo lịch tuần
   21/09–27/09/2026 gồm 7 ca và một roster chung 35 sinh viên áp dụng cho 4 lớp.
   HCM202 học Slot 1 vào Thứ 3 và Thứ 6.
   Dữ liệu điểm danh mẫu được ghi trong cả năm tab. Có thể chạy lại;
   chỉ các dòng có khóa `DEMO-*` và roster `SE1917`–`SE1920` được thay thế.
9. Mở `/fap-demo/` để xem dữ liệu cập nhật tự động hoặc chỉnh Present/Absent thủ công.

Nếu kết nối tạm lỗi, FAP demo tự thử lại sau 5–60 giây và thử ngay khi quay lại
tab; nút **Nạp lại** chỉ để yêu cầu kiểm tra tức thì. Khi mã Apps Script thay đổi,
vẫn cần triển khai **New version** một lần để Google chạy mã mới.
Sau khi một thay đổi được ghi thành công vào Sheet (kể cả đóng phiên trên desktop),
máy chủ cũng đẩy bản cập nhật trực tiếp tới trang FAP đang mở; Google Sheets vẫn
là nơi lưu dữ liệu duy nhất. Nếu luồng trực tiếp ngắt, trang tiếp tục tự đọc lại.

Cổng mô phỏng luôn hiển thị đúng trạng thái nhị phân từ phiên hiện tại. Với link
CSV công khai, Google Sheets không cung cấp trạng thái mở/đóng; nên dùng Apps
Script Web App cho luồng đầy đủ.

## Quy đổi trạng thái trên cổng FAP mô phỏng

Cả desktop app, API và cổng mô phỏng chỉ dùng hai trạng thái:

| Trạng thái trong ứng dụng | Trạng thái trên cổng mô phỏng |
|---|---|
| `PRESENT` | Present |
| `ABSENT` | Absent |

Dữ liệu cũ vẫn tương thích: `LATE` được đọc thành `PRESENT`, còn `NOT CHECKED`
được đọc thành `ABSENT`.

## API chính

| Method | Endpoint | Mục đích |
|---|---|---|
| `GET` | `/api/health` | Kiểm tra backend |
| `POST` | `/api/sessions` | Mở phiên và lưu roster |
| `GET` | `/api/sessions` | Danh sách phiên gần đây |
| `GET` | `/api/sessions/{id}` | Snapshot dashboard |
| `POST` | `/api/sessions/{id}/close` | Đóng phiên |
| `POST` | `/api/sessions/{id}/otp/pause` | Giữ QR, OTP và bộ đếm |
| `POST` | `/api/sessions/{id}/otp/resume` | Tiếp tục xoay QR và OTP |
| `POST` | `/api/attendance` | Sinh viên check-in |
| `POST` | `/api/sessions/{id}/devices/{bindingId}/release` | Giảng viên mở khóa thiết bị có lý do |
| `PATCH` | `/api/sessions/{id}/attendance/{rollNo}` | Sửa trạng thái thủ công |
| `GET` | `/api/sessions/{id}/audit` | Xem nhật ký chỉnh sửa |
| `GET` | `/api/sessions/{id}/export.csv` | Xuất CSV của phiên |
| `POST` | `/api/google-sheets/seed-demo` | Tạo lại bộ dữ liệu demo trong Google Sheets |
| SignalR | `/hubs/attendance` | Cập nhật dashboard trực tiếp |

## Cấu trúc thư mục

```text
lab1-prm/
├── lib/                         # Flutter dashboard giảng viên
│   ├── dialogs/                 # Dialog chi tiết và thêm ca dạy
│   ├── models/                  # Session, sinh viên, thời khóa biểu
│   ├── providers/               # State và luồng nghiệp vụ
│   ├── screens/                 # Các màn hình chính
│   ├── services/                # API, SignalR, OTP, tải file
│   └── widgets/                 # QR, roster, audit log, Google Sheets
├── student-portal/              # Cổng web dành cho sinh viên
├── fap-demo/                    # Cổng FAP mô phỏng độc lập cho giảng viên
├── server/                      # ASP.NET Core API
│   ├── Hubs/                    # SignalR hub
│   ├── Models/
│   └── Services/
├── test/                        # Flutter tests
├── scripts/                     # PowerShell điều phối và đóng gói
├── run.cmd                      # Lệnh chạy nhanh trên Windows
├── run-public.cmd               # Chạy demo qua Cloudflare Quick Tunnel
├── package-windows.cmd          # Tạo gói Windows
└── pubspec.yaml
```

## Kiểm thử

```powershell
flutter test
flutter analyze
dotnet build server\Attendance.Api.csproj
node --test test\fap_demo_web_test.cjs
```

`flutter analyze` hiện có thể hiển thị cảnh báo mức `info` cho các file triển khai riêng cho Flutter Web; đây không phải lỗi build.

## Dữ liệu không đưa lên Git

`.gitignore` đã loại các dữ liệu chỉ thuộc máy local:

- `.dart_tool/`, `build/`, `coverage/`.
- `server/bin/`, `server/obj/`.
- `server/App_Data/` và file cấu hình Web App URL cục bộ.
- `.env`, `appsettings.Development.json`.
- cấu hình DevTools/Visual Studio và thư mục export/download thử nghiệm.

Không commit cache điểm danh, URL Apps Script, credential Google hoặc dữ liệu cá nhân của sinh viên.

## Giới hạn hiện tại

- Dữ liệu thời khóa biểu phục vụ demo và được seed sẵn; hệ thống chủ động không đăng nhập hay lấy dữ liệu từ FAP chính thức.
- Luồng import ổn định hiện tại là CSV; đọc trực tiếp file Excel `.xlsx` chưa được hoàn thiện.
- API local chưa có cơ chế đăng nhập/phân quyền.
- HTTP trong mạng LAN phù hợp demo, chưa phù hợp triển khai Internet.
- Nhận diện thiết bị trên web giúp chặn các trường hợp dùng chung điện thoại thông
  thường, kể cả tab ẩn danh trên cùng mạng. Đây không phải định danh phần cứng tuyệt
  đối; triển khai Internet cần thêm FPT SSO, HTTPS và WebAuthn/App Attest.
- Chế độ public hiện dùng URL Quick Tunnel tạm thời, thay đổi sau mỗi lần chạy và
  không phù hợp làm hosting production.

---

Lab 1 — Desktop Application, FPT University.
