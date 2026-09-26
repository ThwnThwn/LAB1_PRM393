# Product

## Register

product

## Users

Giảng viên FPT thao tác trên laptop trong lớp học và sinh viên điểm danh bằng điện thoại. Giảng viên cần nhìn nhanh lịch dạy theo tuần, chọn đúng mã lớp và mở phiên điểm danh mà không phải nhập lại dữ liệu.

## Product Purpose

FAP Attendance Assistant mô phỏng luồng FAP phục vụ Lab 1 bằng ba bề mặt độc lập: ứng dụng Windows cho giảng viên, cổng web check-in cho sinh viên và website FAP mô phỏng để chốt Present/Absent. Hệ thống không tích hợp FAP chính thức. Thành công là giảng viên có thể chuẩn bị dữ liệu demo và chạy trọn luồng trong vài phút.

## Brand Personality

Học thuật, tin cậy, thực dụng. Giao diện quen thuộc với FAP nhưng rõ ràng và hiện đại hơn, ưu tiên tốc độ thao tác và khả năng trình chiếu.

## Anti-references

Không giả vờ là FAP chính thức; không dùng Chrome Extension hay phụ thuộc DOM của cổng FAP thật. Không mô phỏng sự cũ kỹ hoặc chữ quá nhỏ của FAP; không dùng dashboard trang trí nặng, hiệu ứng dư thừa, màu bão hòa trên trạng thái không hoạt động hoặc cấu trúc card lồng nhau.

## Design Principles

- Luồng chính luôn theo thứ tự tuần → lớp → phiên điểm danh.
- Mã môn, mã lớp, buổi học trong tiến độ môn (ví dụ 7/20), slot, ngày và trạng thái
  phải đọc được ngay khi trình chiếu.
- Dữ liệu demo phải tạo lại được bằng một thao tác và không phụ thuộc dữ liệu thật.
- Ba bề mặt phải được phân biệt rõ và cùng dùng một backend: desktop giảng viên, web sinh viên, web FAP mô phỏng.
- Trạng thái hệ thống và lỗi kết nối phải giải thích được bước tiếp theo.
- Giữ cách gọi và cấu trúc gần FAP để người dùng nhận ra ngay.

## Accessibility & Inclusion

Hướng tới WCAG 2.1 AA: tương phản chữ tối thiểu 4.5:1, trạng thái không chỉ dựa vào màu, vùng bấm tối thiểu 44 px, hỗ trợ bàn phím/focus rõ ràng và giảm chuyển động theo thiết lập hệ điều hành.
