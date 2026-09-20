# FAP Attendance Assistant

Ứng dụng Lab 1 dạng desktop-first giúp giảng viên quản lý một buổi điểm danh bằng QR và OTP. Giao diện giảng viên được viết bằng Flutter Web, API dùng ASP.NET Core 8, dữ liệu lưu bằng SQLite và cập nhật trực tiếp qua SignalR.

> Đây là dự án phục vụ demo học phần. Ứng dụng chưa phải sản phẩm chính thức của FPT/FAP và chưa nên dùng với dữ liệu thật khi chưa bổ sung đăng nhập, phân quyền và HTTPS.

## Chức năng hiện có

- Thời khóa biểu tuần và chọn ca dạy đang thao tác.
- Import danh sách sinh viên từ CSV hoặc cấu hình Google Sheets.
- Mở và đóng từng phiên điểm danh.
- QR và OTP 6 số tự đổi sau mỗi 10 giây.
- Tạm dừng đồng bộ QR, OTP và bộ đếm; mã đang giữ vẫn hợp lệ cho tới khi tiếp tục.
- Cổng web để sinh viên quét QR, nhập MSSV, email và OTP.
- Không giới hạn email FPT; chỉ yêu cầu địa chỉ email hợp lệ.
- Chống một MSSV điểm danh hai lần trong cùng một phiên.
- Dashboard số lượng có mặt, trễ, vắng, chưa điểm danh và tỷ lệ chuyên cần.
- Cập nhật dashboard trực tiếp bằng SignalR, có polling dự phòng.
- Lưu phiên, roster, trạng thái và nhật ký chỉnh sửa trong SQLite.
- Xuất CSV riêng cho từng buổi học.
- Chrome Extension hỗ trợ tích trạng thái lên trang điểm danh FAP.

## Kiến trúc

| Thành phần | Công nghệ | Địa chỉ mặc định |
|---|---|---|
| Dashboard giảng viên | Flutter Web | `http://localhost:3000` |
| API và SignalR | ASP.NET Core 8 | `http://localhost:8080` |
| Cổng sinh viên | HTML/CSS/JavaScript | `http://<IP-LAN>:8080/student/` |
| Database | SQLite | `server/App_Data/attendance.db` |
| Tiện ích FAP | Chrome Extension Manifest V3 | Thư mục `extension/` |

Luồng dữ liệu chính:

```text
Giảng viên mở phiên trên Flutter
            ↓
ASP.NET Core lưu phiên vào SQLite
            ↓
Sinh viên quét QR → nhập OTP → gửi check-in
            ↓
SignalR cập nhật dashboard giảng viên
            ↓
Đóng phiên → xuất CSV hoặc dùng Extension tích P/A lên FAP
```

## Yêu cầu môi trường

- Windows 10/11.
- Flutter SDK với Dart `>= 3.12.0`.
- .NET SDK 8.0 trở lên.
- Google Chrome hoặc Microsoft Edge.
- Điện thoại và máy giảng viên cùng mạng Wi-Fi nếu demo quét QR.

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
4. Mở Flutter Web bằng Chrome tại cổng cố định `3000`.
5. Gắn IP LAN vào QR để điện thoại truy cập được cổng sinh viên.

Nhấn `Ctrl+C` trong cửa sổ chạy để dừng Flutter và backend do script khởi tạo.

### Chạy thủ công

Terminal thứ nhất:

```powershell
dotnet run --project server\Attendance.Api.csproj
```

Terminal thứ hai (thay IP bằng địa chỉ LAN của máy):

```powershell
flutter run -d chrome --web-port=3000 `
  --dart-define=ATTENDANCE_SERVER_URL=http://192.168.1.10:8080
```

Nếu chỉ test trên cùng máy, có thể dùng `http://127.0.0.1:8080`. Không đưa `localhost` vào QR cho điện thoại vì `localhost` trên điện thoại chính là điện thoại, không phải máy giảng viên.

## Luồng demo đề xuất

1. Chọn một ca trên trang **Lịch dạy FAP**.
2. Vào **Điểm danh QR & OTP 10s** và bấm **Mở điểm danh**.
3. Sinh viên cùng Wi-Fi quét QR trên màn hình giảng viên.
4. Sinh viên nhập MSSV, email và OTP đang hiển thị rồi xác nhận.
5. Tên sinh viên xuất hiện ngay trên dashboard.
6. Có thể bấm **Tạm dừng QR & OTP** để giữ nguyên QR, OTP và số giây còn lại.
7. Bấm **Đóng điểm danh**; sinh viên chưa check-in được chuyển thành `ABSENT`.
8. Tải CSV của phiên hoặc dùng Chrome Extension để hỗ trợ cập nhật FAP.

## Quy đổi trạng thái sang FAP

FAP chỉ có hai trạng thái `Present` và `Absent`, nên Extension quy đổi như sau:

| Trạng thái trong ứng dụng | Trạng thái trên FAP |
|---|---|
| `PRESENT` | Present |
| `LATE` | Present |
| `ABSENT` | Absent |
| `NOT CHECKED` | Không nên áp dụng khi phiên còn mở; khi đóng phiên sẽ đổi thành `ABSENT` |

Extension chặn tự động tích khi phiên điểm danh vẫn còn mở. Giảng viên vẫn cần kiểm tra kết quả trước khi bấm nút lưu trên FAP.

## Cài Chrome Extension

1. Mở `chrome://extensions/` hoặc `edge://extensions/`.
2. Bật **Developer mode**.
3. Chọn **Load unpacked**.
4. Chọn thư mục `extension/` của dự án.
5. Mở trang điểm danh trên FAP.
6. Nhập Google Apps Script URL nếu dùng Google Sheets; để trống để Extension thử đọc API local tại `http://localhost:8080`.
7. Đồng bộ dữ liệu, đóng phiên điểm danh rồi mới dùng chức năng tự động tích.

> Extension phụ thuộc vào cấu trúc HTML hiện tại của FAP. Nếu FAP thay đổi giao diện hoặc tên radio button thì selector trong `extension/content.js` có thể cần cập nhật.

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
| `PATCH` | `/api/sessions/{id}/attendance/{rollNo}` | Sửa trạng thái thủ công |
| `GET` | `/api/sessions/{id}/audit` | Xem nhật ký chỉnh sửa |
| `GET` | `/api/sessions/{id}/export.csv` | Xuất CSV của phiên |
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
├── docs/                        # Cổng web dành cho sinh viên
├── extension/                   # Chrome Extension hỗ trợ FAP
├── server/                      # ASP.NET Core API
│   ├── Data/                    # EF Core DbContext
│   ├── Hubs/                    # SignalR hub
│   ├── Models/
│   └── Services/
├── test/                        # Flutter tests
├── run.cmd                      # Lệnh chạy nhanh trên Windows
├── run.ps1                      # Script điều phối backend và Flutter
└── pubspec.yaml
```

## Kiểm thử

```powershell
flutter test
flutter analyze
dotnet build server\Attendance.Api.csproj
```

`flutter analyze` hiện có thể hiển thị cảnh báo mức `info` cho các file triển khai riêng cho Flutter Web; đây không phải lỗi build.

## Dữ liệu không đưa lên Git

`.gitignore` đã loại các dữ liệu chỉ thuộc máy local:

- `.dart_tool/`, `build/`, `coverage/`.
- `server/bin/`, `server/obj/`.
- `server/App_Data/` và các file SQLite.
- `.env`, `appsettings.Development.json`.
- cấu hình DevTools/Visual Studio và thư mục export/download thử nghiệm.

Không commit database điểm danh thật, khóa API, credential Google hoặc dữ liệu cá nhân của sinh viên.

## Giới hạn hiện tại

- Dữ liệu thời khóa biểu ban đầu phục vụ demo; chưa tự đăng nhập và lấy lịch trực tiếp từ FAP.
- Luồng import ổn định hiện tại là CSV; đọc trực tiếp file Excel `.xlsx` chưa được hoàn thiện.
- API local chưa có cơ chế đăng nhập/phân quyền.
- HTTP trong mạng LAN phù hợp demo, chưa phù hợp triển khai Internet.
- Chưa triển khai hosting công khai; điện thoại phải cùng mạng với máy chạy backend.
- Extension cần được kiểm tra lại nếu FAP thay đổi DOM.

---

Lab 1 — Desktop Application, FPT University.
