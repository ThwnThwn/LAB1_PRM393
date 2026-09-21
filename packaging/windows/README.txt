FAP ATTENDANCE ASSISTANT - WINDOWS
==================================

Khoi dong
----------
1. Giai nen toan bo goi vao mot thu muc tren may.
2. Bam dup "Start FAP Attendance.cmd".
3. Neu Windows Firewall hoi quyen, chon Allow access cho Private networks.
4. O che do local nay, may giang vien va dien thoai sinh vien phai cung mang Wi-Fi.

Khoi dong qua Internet (khong can cung Wi-Fi)
---------------------------------------------
1. Bam dup "Start FAP Attendance Public.cmd".
2. Lan dau launcher se cai cloudflared mien phi bang winget neu can.
3. Cho den khi hien "PUBLIC DEMO DA SAN SANG".
4. QR trong app se dung URL HTTPS tam thoi; dien thoai co the dung Wi-Fi khac hoac 4G/5G.
5. Dong app de tat backend va tunnel. URL public cu se het hieu luc.

Che do public tao token quan tri ngau nhien cho tung lan chay. Quick Tunnel chi dung
cho demo voi du lieu gia lap, khong phai phuong an production.

Luu y
-----
- Khong tach rieng file .exe khoi cac thu muc app, server va docs.
- Google Sheets la database chinh. Cau hinh Apps Script Web App URL trong app truoc khi import/mo phien.
- SQLite trong server\App_Data\attendance.db chi la cache runtime cuc bo.
- Log khoi dong nam trong %LOCALAPPDATA%\FAP Attendance\Logs.
- Dong cua so ung dung de backend do goi nay khoi dong cung duoc tat.

Trang web demo
--------------
- Sinh vien diem danh: http://<IP-LAN>:8080/student/
- Giao vien xem cong FAP mo phong: http://<IP-LAN>:8080/fap-demo/
- Launcher tu mo cong FAP mo phong tren trinh duyet.
- Cong mo phong tu cap nhat khi desktop hoac dien thoai thay doi va luu P/A ve Google Sheets.
- Day la website cua bai tap, khong ket noi FAP chinh thuc.
