using System.Collections.Concurrent;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using Attendance.Api.Hubs;
using Attendance.Api.Models;
using Microsoft.AspNetCore.SignalR;

namespace Attendance.Api.Services;

public sealed class AttendanceService(
    GoogleSheetsPrimaryStore sheetsStore,
    OtpService otpService,
    IHubContext<AttendanceHub> hubContext,
    AttendanceUpdateStream updateStream)
{
    private static readonly ConcurrentDictionary<string, SemaphoreSlim> SessionLocks =
        new(StringComparer.OrdinalIgnoreCase);
    private static long generatedId = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() * 1000;

    public async Task<IReadOnlyCollection<RosterStudentRecord>> GetClassRosterAsync(
        string classCode,
        CancellationToken cancellationToken)
    {
        var (_, students) = await sheetsStore.GetRosterAsync(classCode, cancellationToken);
        return students;
    }

    public async Task<ServiceResult<RosterSyncSnapshot>> SyncRosterAsync(
        string classCode,
        RosterSyncRequest request,
        CancellationToken cancellationToken)
    {
        var normalizedClassCode = classCode.Trim().ToUpperInvariant();
        if (normalizedClassCode.Length == 0)
        {
            return Failure<RosterSyncSnapshot>("Mã lớp không hợp lệ.");
        }

        var students = NormalizeStudents(request.Students);
        if (students.Length == 0)
        {
            return Failure<RosterSyncSnapshot>("Danh sách sinh viên đang trống.");
        }

        var roster = students.Select(student => new RosterStudentRecord(
            student.RollNo!,
            student.FullName!,
            student.Email!)).ToArray();
        var rosterWrite = await sheetsStore.SyncRosterAsync(
            normalizedClassCode,
            roster,
            cancellationToken);
        if (!rosterWrite.Success)
        {
            return StoreFailure<RosterSyncSnapshot>(rosterWrite.Message);
        }

        AttendanceSnapshot? sessionSnapshot = null;
        if (!string.IsNullOrWhiteSpace(request.SessionId))
        {
            var gate = GetSessionLock(request.SessionId);
            await gate.WaitAsync(cancellationToken);
            try
            {
                var load = await sheetsStore.GetSessionAsync(request.SessionId, cancellationToken);
                if (!load.Result.Success)
                {
                    return StoreFailure<RosterSyncSnapshot>(load.Result.Message);
                }
                if (load.Session is null)
                {
                    return Failure<RosterSyncSnapshot>(
                        "Không tìm thấy phiên điểm danh.",
                        StatusCodes.Status404NotFound);
                }
                if (!load.Session.Snapshot.IsOpen)
                {
                    return Failure<RosterSyncSnapshot>(
                        "Phiên điểm danh đã đóng.",
                        StatusCodes.Status409Conflict);
                }
                if (!load.Session.Snapshot.ClassCode.Equals(normalizedClassCode, StringComparison.OrdinalIgnoreCase))
                {
                    return Failure<RosterSyncSnapshot>("Danh sách CSV không thuộc lớp của phiên đang mở.");
                }

                var existing = load.Session.Snapshot.Students.ToDictionary(
                    student => student.RollNo,
                    StringComparer.OrdinalIgnoreCase);
                var records = roster.Select(student => existing.TryGetValue(student.RollNo, out var current)
                    ? current with { FullName = student.FullName, Email = student.Email }
                    : new AttendanceRecord(
                        load.Session.Snapshot.SessionId,
                        student.RollNo,
                        student.FullName,
                        student.Email,
                        normalizedClassCode,
                        load.Session.Snapshot.SubjectCode,
                        load.Session.Snapshot.Slot,
                        AttendanceStatuses.NotChecked,
                        null,
                        string.Empty,
                        string.Empty)).ToArray();
                var auditLogs = load.Session.AuditLogs.Append(CreateAudit(
                    load.Session.Snapshot.SessionId,
                    string.Empty,
                    "ROSTER_SYNCED",
                    load.Session.Snapshot.Count.ToString(CultureInfo.InvariantCulture),
                    records.Length.ToString(CultureInfo.InvariantCulture),
                    CleanActor(request.Actor),
                    $"Đồng bộ {records.Length} sinh viên từ CSV")).ToArray();
                sessionSnapshot = RebuildSnapshot(
                    load.Session.Snapshot with { Students = records, Count = records.Length },
                    load.Session.DeviceBindings);
                var save = await sheetsStore.SaveSessionAsync(
                    new StoredAttendanceSession(sessionSnapshot, auditLogs, load.Session.DeviceBindings),
                    cancellationToken);
                if (!save.Success)
                {
                    return StoreFailure<RosterSyncSnapshot>(save.Message);
                }
                await BroadcastAsync(sessionSnapshot.SessionId, "RosterUpdated", sessionSnapshot, cancellationToken);
            }
            finally
            {
                gate.Release();
            }
        }

        return new ServiceResult<RosterSyncSnapshot>(
            true,
            $"Đã lưu {roster.Length} sinh viên vào Google Sheets.",
            new RosterSyncSnapshot(
                "success",
                normalizedClassCode,
                roster.Length,
                roster,
                sessionSnapshot));
    }

    public async Task<ServiceResult<AttendanceSnapshot>> OpenSessionAsync(
        OpenSessionRequest request,
        CancellationToken cancellationToken)
    {
        var classCode = request.ClassCode?.Trim().ToUpperInvariant() ?? string.Empty;
        var subjectCode = request.SubjectCode?.Trim().ToUpperInvariant() ?? string.Empty;
        if (classCode.Length == 0 || subjectCode.Length == 0 || request.Slot is < 1 or > 8)
        {
            return Failure<AttendanceSnapshot>("Thông tin lớp, môn học hoặc slot không hợp lệ.");
        }

        var list = await sheetsStore.GetSessionsAsync(100, cancellationToken);
        if (!list.Result.Success)
        {
            return StoreFailure<AttendanceSnapshot>(
                $"{list.Result.Message} Hãy cập nhật Apps Script lên phiên bản Google-Sheets-only mới nhất.");
        }
        var existing = list.Sessions.FirstOrDefault(item =>
            item.Snapshot.IsOpen &&
            item.Snapshot.ClassCode.Equals(classCode, StringComparison.OrdinalIgnoreCase) &&
            item.Snapshot.SubjectCode.Equals(subjectCode, StringComparison.OrdinalIgnoreCase) &&
            item.Snapshot.Slot == request.Slot);
        if (existing is not null)
        {
            return new ServiceResult<AttendanceSnapshot>(
                true,
                "Phiên điểm danh này đang mở.",
                ApplyOtpState(existing.Snapshot));
        }

        var students = NormalizeStudents(request.Students);
        if (students.Length == 0)
        {
            return Failure<AttendanceSnapshot>("Không thể mở phiên khi danh sách sinh viên đang trống.");
        }
        var roster = students.Select(student => new RosterStudentRecord(
            student.RollNo!,
            student.FullName!,
            student.Email!)).ToArray();
        var rosterWrite = await sheetsStore.SyncRosterAsync(classCode, roster, cancellationToken);
        if (!rosterWrite.Success)
        {
            return StoreFailure<AttendanceSnapshot>(rosterWrite.Message);
        }

        var now = DateTime.UtcNow;
        var sessionId = Guid.NewGuid().ToString("N");
        var records = roster.Select(student => new AttendanceRecord(
            sessionId,
            student.RollNo,
            student.FullName,
            student.Email,
            classCode,
            subjectCode,
            request.Slot,
            AttendanceStatuses.NotChecked,
            null,
            string.Empty,
            string.Empty)).ToArray();
        var snapshot = RebuildSnapshot(new AttendanceSnapshot(
            "success",
            sessionId,
            classCode,
            subjectCode,
            request.Slot,
            ParseDate(request.Date, now),
            true,
            now,
            null,
            request.LateAfterMinutes <= 0 ? 10 : request.LateAfterMinutes,
            false,
            null,
            null,
            records.Length,
            new DashboardStats(0, 0, 0, 0, 0, 0),
            records,
            []), []);
        var audits = new[]
        {
            CreateAudit(
                sessionId,
                string.Empty,
                "SESSION_OPENED",
                string.Empty,
                string.Empty,
                CleanActor(request.Actor),
                $"Mở phiên {subjectCode} - {classCode}, Slot {request.Slot}"),
        };
        var save = await sheetsStore.SaveSessionAsync(
            new StoredAttendanceSession(snapshot, audits, []),
            cancellationToken);
        if (!save.Success)
        {
            return StoreFailure<AttendanceSnapshot>(save.Message);
        }

        otpService.Resume(sessionId);
        await BroadcastAsync(sessionId, "SessionOpened", snapshot, cancellationToken);
        return new ServiceResult<AttendanceSnapshot>(true, "Đã mở phiên điểm danh.", snapshot);
    }

    public async Task<ServiceResult<AttendanceSnapshot>> CloseSessionAsync(
        string sessionId,
        string? actor,
        CancellationToken cancellationToken)
    {
        var gate = GetSessionLock(sessionId);
        await gate.WaitAsync(cancellationToken);
        try
        {
            var load = await sheetsStore.GetSessionAsync(sessionId, cancellationToken);
            if (!load.Result.Success) return StoreFailure<AttendanceSnapshot>(load.Result.Message);
            if (load.Session is null)
            {
                return Failure<AttendanceSnapshot>("Không tìm thấy phiên điểm danh.", StatusCodes.Status404NotFound);
            }
            if (!load.Session.Snapshot.IsOpen)
            {
                var closedSnapshot = ApplyOtpState(load.Session.Snapshot);
                await BroadcastAsync(sessionId, "SessionClosed", closedSnapshot, cancellationToken);
                return new ServiceResult<AttendanceSnapshot>(
                    true,
                    "Phiên điểm danh đã đóng.",
                    closedSnapshot);
            }

            var now = DateTime.UtcNow;
            var changedBy = CleanActor(actor);
            var audits = load.Session.AuditLogs.ToList();
            var records = load.Session.Snapshot.Students.Select(student =>
            {
                if (student.Status != AttendanceStatuses.NotChecked) return student;
                audits.Add(CreateAudit(
                    sessionId,
                    student.RollNo,
                    "STATUS_CHANGED",
                    AttendanceStatuses.NotChecked,
                    AttendanceStatuses.Absent,
                    changedBy,
                    "Tự động đánh vắng khi đóng phiên"));
                return student with
                {
                    Status = AttendanceStatuses.Absent,
                    CheckinTime = null,
                    Notes = "Tự động đánh vắng khi đóng phiên",
                };
            }).ToArray();
            audits.Add(CreateAudit(
                sessionId,
                string.Empty,
                "SESSION_CLOSED",
                string.Empty,
                string.Empty,
                changedBy,
                "Đóng phiên điểm danh"));
            otpService.Resume(sessionId);
            var snapshot = RebuildSnapshot(
                load.Session.Snapshot with
                {
                    IsOpen = false,
                    ClosedAt = now,
                    OtpPaused = false,
                    PausedOtp = null,
                    OtpRemainingSeconds = null,
                    Students = records,
                },
                load.Session.DeviceBindings);
            var save = await sheetsStore.SaveSessionAsync(
                new StoredAttendanceSession(snapshot, audits, load.Session.DeviceBindings),
                cancellationToken);
            if (!save.Success) return StoreFailure<AttendanceSnapshot>(save.Message);
            await BroadcastAsync(sessionId, "SessionClosed", snapshot, cancellationToken);
            return new ServiceResult<AttendanceSnapshot>(true, "Đã đóng phiên điểm danh.", snapshot);
        }
        finally
        {
            gate.Release();
        }
    }

    public async Task<ServiceResult<AttendanceSnapshot>> CheckinAsync(
        StudentCheckinRequest request,
        DeviceIdentity deviceIdentity,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.SessionId))
        {
            return Failure<AttendanceSnapshot>("QR không chứa mã phiên điểm danh.");
        }

        var sessionId = request.SessionId.Trim();
        var gate = GetSessionLock(sessionId);
        await gate.WaitAsync(cancellationToken);
        try
        {
            var load = await sheetsStore.GetSessionAsync(sessionId, cancellationToken);
            if (!load.Result.Success) return StoreFailure<AttendanceSnapshot>(load.Result.Message);
            if (load.Session is null)
            {
                return Failure<AttendanceSnapshot>("Phiên điểm danh không tồn tại.", StatusCodes.Status404NotFound);
            }
            var current = ApplyOtpState(load.Session.Snapshot);
            if (!current.IsOpen)
            {
                return Failure<AttendanceSnapshot>("Phiên điểm danh đã đóng.", StatusCodes.Status409Conflict);
            }
            if (!otpService.ValidateForSession(sessionId, request.Otp))
            {
                return Failure<AttendanceSnapshot>("Mã OTP không hợp lệ hoặc đã hết hạn.");
            }

            var rollNo = request.RollNo!.Trim().ToUpperInvariant();
            var email = request.Email!.Trim().ToLowerInvariant();
            var records = current.Students.ToArray();
            var entryIndex = Array.FindIndex(records, student =>
                student.RollNo.Equals(rollNo, StringComparison.OrdinalIgnoreCase));
            if (entryIndex < 0)
            {
                return Failure<AttendanceSnapshot>(
                    "MSSV không có trong danh sách lớp của phiên điểm danh.",
                    StatusCodes.Status404NotFound,
                    "STUDENT_NOT_IN_ROSTER");
            }
            var entry = records[entryIndex];
            if (!string.IsNullOrWhiteSpace(entry.Email) &&
                !entry.Email.Equals(email, StringComparison.OrdinalIgnoreCase))
            {
                return Failure<AttendanceSnapshot>(
                    "Email không khớp với MSSV trong danh sách lớp.",
                    StatusCodes.Status403Forbidden,
                    "STUDENT_EMAIL_MISMATCH");
            }

            var now = DateTime.UtcNow;
            var bindings = load.Session.DeviceBindings.ToList();
            var bindingIndex = bindings.FindIndex(binding =>
                (!string.IsNullOrWhiteSpace(binding.DeviceHash) &&
                 binding.DeviceHash.Equals(deviceIdentity.DeviceHash, StringComparison.OrdinalIgnoreCase)) ||
                (!string.IsNullOrWhiteSpace(binding.NetworkHash) &&
                 binding.NetworkHash.Equals(deviceIdentity.NetworkHash, StringComparison.OrdinalIgnoreCase)));
            var audits = load.Session.AuditLogs.ToList();
            if (bindingIndex >= 0 &&
                !bindings[bindingIndex].RollNo.Equals(rollNo, StringComparison.OrdinalIgnoreCase))
            {
                var binding = bindings[bindingIndex];
                binding = binding with
                {
                    LastSeen = now,
                    BlockedAttempts = binding.BlockedAttempts + 1,
                    LastBlockedRollNo = rollNo,
                    LastBlockedAt = now,
                    NetworkHash = deviceIdentity.NetworkHash,
                    UserAgentHash = deviceIdentity.UserAgentHash,
                };
                bindings[bindingIndex] = binding;
                audits.Add(CreateAudit(
                    sessionId,
                    rollNo,
                    "DEVICE_CHECKIN_BLOCKED",
                    binding.RollNo,
                    rollNo,
                    $"Thiết bị {deviceIdentity.DeviceCode}",
                    $"Thiết bị đã được gắn với {binding.RollNo}"));
                var blockedSnapshot = RebuildSnapshot(current, bindings);
                var blockedSave = await sheetsStore.SaveSessionAsync(
                    new StoredAttendanceSession(blockedSnapshot, audits, bindings),
                    cancellationToken);
                if (!blockedSave.Success) return StoreFailure<AttendanceSnapshot>(blockedSave.Message);
                await BroadcastAsync(sessionId, "DeviceConflict", blockedSnapshot, cancellationToken);
                return new ServiceResult<AttendanceSnapshot>(
                    false,
                    "Thiết bị này đã được dùng cho một MSSV khác trong phiên. Hãy liên hệ giảng viên để mở khóa.",
                    blockedSnapshot,
                    StatusCodes.Status409Conflict,
                    "DEVICE_ALREADY_USED");
            }

            if (bindingIndex < 0)
            {
                bindings.Add(new StoredDeviceBinding(
                    NewId(),
                    deviceIdentity.DeviceHash,
                    deviceIdentity.DeviceCode,
                    rollNo,
                    now,
                    now,
                    0,
                    string.Empty,
                    null,
                    deviceIdentity.NetworkHash,
                    deviceIdentity.UserAgentHash));
            }
            else
            {
                bindings[bindingIndex] = bindings[bindingIndex] with
                {
                    LastSeen = now,
                    NetworkHash = deviceIdentity.NetworkHash,
                    UserAgentHash = deviceIdentity.UserAgentHash,
                };
            }

            if (entry.CheckinTime.HasValue)
            {
                var duplicateSnapshot = RebuildSnapshot(current, bindings);
                var bindingSave = await sheetsStore.SaveSessionAsync(
                    new StoredAttendanceSession(duplicateSnapshot, audits, bindings),
                    cancellationToken);
                if (!bindingSave.Success) return StoreFailure<AttendanceSnapshot>(bindingSave.Message);
                return new ServiceResult<AttendanceSnapshot>(
                    false,
                    $"{rollNo} đã điểm danh lúc {entry.CheckinTime.Value.ToLocalTime():HH:mm:ss}.",
                    duplicateSnapshot,
                    StatusCodes.Status409Conflict);
            }

            var status = now > current.OpenedAt.AddMinutes(current.LateAfterMinutes)
                ? AttendanceStatuses.Late
                : AttendanceStatuses.Present;
            records[entryIndex] = entry with
            {
                Email = email,
                Status = status,
                CheckinTime = now,
                Notes = "Điểm danh bằng QR/OTP",
                ConfirmationCode = CreateConfirmationCode(email, sessionId, rollNo, now),
            };
            audits.Add(CreateAudit(
                sessionId,
                rollNo,
                "STUDENT_CHECKIN",
                entry.Status,
                status,
                rollNo,
                "Điểm danh bằng QR/OTP"));
            var snapshot = RebuildSnapshot(current with { Students = records }, bindings);
            var save = await sheetsStore.SaveSessionAsync(
                new StoredAttendanceSession(snapshot, audits, bindings),
                cancellationToken);
            if (!save.Success) return StoreFailure<AttendanceSnapshot>(save.Message);
            await BroadcastAsync(sessionId, "AttendanceUpdated", snapshot, cancellationToken);
            return new ServiceResult<AttendanceSnapshot>(true, "Điểm danh thành công.", snapshot);
        }
        finally
        {
            gate.Release();
        }
    }

    public async Task<ServiceResult<AttendanceSnapshot>> ReleaseDeviceBindingAsync(
        string sessionId,
        long bindingId,
        ReleaseDeviceRequest request,
        CancellationToken cancellationToken)
    {
        var reason = request.Reason?.Trim() ?? string.Empty;
        if (reason.Length < 3)
        {
            return Failure<AttendanceSnapshot>("Vui lòng nhập lý do mở khóa thiết bị.");
        }

        var gate = GetSessionLock(sessionId);
        await gate.WaitAsync(cancellationToken);
        try
        {
            var load = await sheetsStore.GetSessionAsync(sessionId, cancellationToken);
            if (!load.Result.Success) return StoreFailure<AttendanceSnapshot>(load.Result.Message);
            if (load.Session is null)
            {
                return Failure<AttendanceSnapshot>("Không tìm thấy phiên điểm danh.", StatusCodes.Status404NotFound);
            }
            var bindings = load.Session.DeviceBindings.ToList();
            var binding = bindings.FirstOrDefault(item => item.Id == bindingId);
            if (binding is null)
            {
                return Failure<AttendanceSnapshot>("Không tìm thấy thiết bị cần mở khóa.", StatusCodes.Status404NotFound);
            }
            bindings.Remove(binding);
            var audits = load.Session.AuditLogs.Append(CreateAudit(
                sessionId,
                binding.RollNo,
                "DEVICE_BINDING_RELEASED",
                binding.RollNo,
                string.Empty,
                CleanActor(request.Actor),
                $"{reason} • Thiết bị {binding.DeviceCode}")).ToArray();
            var snapshot = RebuildSnapshot(ApplyOtpState(load.Session.Snapshot), bindings);
            var save = await sheetsStore.SaveSessionAsync(
                new StoredAttendanceSession(snapshot, audits, bindings),
                cancellationToken);
            if (!save.Success) return StoreFailure<AttendanceSnapshot>(save.Message);
            await BroadcastAsync(sessionId, "DeviceBindingReleased", snapshot, cancellationToken);
            return new ServiceResult<AttendanceSnapshot>(
                true,
                "Đã mở khóa thiết bị. Thiết bị có thể điểm danh lại cho một MSSV khác.",
                snapshot);
        }
        finally
        {
            gate.Release();
        }
    }

    public async Task<ServiceResult<AttendanceSnapshot>> UpdateAttendanceAsync(
        string sessionId,
        string rollNo,
        UpdateAttendanceRequest request,
        CancellationToken cancellationToken)
    {
        var normalizedStatus = request.Status?.Trim().ToUpperInvariant() ?? string.Empty;
        if (!AttendanceStatuses.All.Contains(normalizedStatus))
        {
            return Failure<AttendanceSnapshot>("Trạng thái điểm danh không hợp lệ.");
        }

        var gate = GetSessionLock(sessionId);
        await gate.WaitAsync(cancellationToken);
        try
        {
            var load = await sheetsStore.GetSessionAsync(sessionId, cancellationToken);
            if (!load.Result.Success) return StoreFailure<AttendanceSnapshot>(load.Result.Message);
            if (load.Session is null)
            {
                return Failure<AttendanceSnapshot>("Không tìm thấy phiên điểm danh.", StatusCodes.Status404NotFound);
            }
            var records = load.Session.Snapshot.Students.ToArray();
            var normalizedRollNo = rollNo.Trim().ToUpperInvariant();
            var index = Array.FindIndex(records, student =>
                student.RollNo.Equals(normalizedRollNo, StringComparison.OrdinalIgnoreCase));
            if (index < 0)
            {
                return Failure<AttendanceSnapshot>("Không tìm thấy sinh viên trong phiên.", StatusCodes.Status404NotFound);
            }
            var entry = records[index];
            var expectedStatus = request.ExpectedStatus?.Trim().ToUpperInvariant();
            if (!string.IsNullOrEmpty(expectedStatus) &&
                !entry.Status.Equals(expectedStatus, StringComparison.OrdinalIgnoreCase))
            {
                return Failure<AttendanceSnapshot>(
                    "Trạng thái đã được thay đổi ở cửa sổ khác. Hãy nạp lại dữ liệu trước khi lưu.",
                    StatusCodes.Status409Conflict);
            }

            var notes = request.Reason?.Trim() ?? "Giảng viên cập nhật thủ công";
            records[index] = entry with
            {
                Status = normalizedStatus,
                CheckinTime = normalizedStatus is AttendanceStatuses.Present or AttendanceStatuses.Late
                    ? entry.CheckinTime ?? DateTime.UtcNow
                    : null,
                Notes = notes,
            };
            var audits = load.Session.AuditLogs.Append(CreateAudit(
                sessionId,
                entry.RollNo,
                "MANUAL_UPDATE",
                entry.Status,
                normalizedStatus,
                CleanActor(request.Actor),
                notes)).ToArray();
            var snapshot = RebuildSnapshot(
                ApplyOtpState(load.Session.Snapshot) with { Students = records },
                load.Session.DeviceBindings);
            var save = await sheetsStore.SaveSessionAsync(
                new StoredAttendanceSession(snapshot, audits, load.Session.DeviceBindings),
                cancellationToken);
            if (!save.Success) return StoreFailure<AttendanceSnapshot>(save.Message);
            await BroadcastAsync(sessionId, "AttendanceUpdated", snapshot, cancellationToken);
            return new ServiceResult<AttendanceSnapshot>(true, "Đã cập nhật trạng thái.", snapshot);
        }
        finally
        {
            gate.Release();
        }
    }

    /// <summary>
    /// Applies a teacher's draft in one Google Sheets write. A slot without a
    /// session gets a closed session so manual attendance does not start QR/OTP.
    /// </summary>
    public async Task<ServiceResult<AttendanceSnapshot>> SaveAttendanceBatchAsync(
        SaveAttendanceBatchRequest request,
        CancellationToken cancellationToken)
    {
        var classCode = request.ClassCode?.Trim().ToUpperInvariant() ?? string.Empty;
        var subjectCode = request.SubjectCode?.Trim().ToUpperInvariant() ?? string.Empty;
        if (classCode.Length == 0 || subjectCode.Length == 0 || request.Slot is < 1 or > 8 ||
            !DateOnly.TryParseExact(request.Date, "yyyy-MM-dd", CultureInfo.InvariantCulture,
                DateTimeStyles.None, out var date))
        {
            return Failure<AttendanceSnapshot>("Thông tin lớp, môn học, slot hoặc ngày học không hợp lệ.");
        }

        var changes = request.Changes?.ToArray() ?? [];
        if (changes.Length is < 1 or > 200 || changes.Any(change =>
                string.IsNullOrWhiteSpace(change.RollNo) ||
                !AttendanceStatuses.All.Contains(change.Status?.Trim() ?? string.Empty) ||
                !AttendanceStatuses.All.Contains(change.ExpectedStatus?.Trim() ?? string.Empty)) ||
            changes.Select(change => change.RollNo!.Trim()).Distinct(StringComparer.OrdinalIgnoreCase).Count() != changes.Length)
        {
            return Failure<AttendanceSnapshot>("Danh sách thay đổi không hợp lệ hoặc bị trùng MSSV.");
        }

        var requestedSessionId = request.SessionId?.Trim();
        var gateKey = requestedSessionId is { Length: > 0 }
            ? requestedSessionId
            : $"draft:{classCode}:{subjectCode}:{request.Slot}:{date:yyyy-MM-dd}";
        var gate = GetSessionLock(gateKey);
        await gate.WaitAsync(cancellationToken);
        try
        {
            StoredAttendanceSession? stored;
            if (requestedSessionId is { Length: > 0 })
            {
                var load = await sheetsStore.GetSessionAsync(requestedSessionId, cancellationToken);
                if (!load.Result.Success) return StoreFailure<AttendanceSnapshot>(load.Result.Message);
                if (load.Session is null)
                    return Failure<AttendanceSnapshot>("Không tìm thấy phiên điểm danh.", StatusCodes.Status404NotFound);
                stored = load.Session;
            }
            else
            {
                var list = await sheetsStore.GetSessionsAsync(100, cancellationToken, classCode, subjectCode, request.Slot);
                if (!list.Result.Success) return StoreFailure<AttendanceSnapshot>(list.Result.Message);
                if (list.Sessions.Any(item => SameVietnamCalendarDate(item.Snapshot.Date, date)))
                {
                    return Failure<AttendanceSnapshot>(
                        "Ca học đã có phiên trên Google Sheets. Hãy chọn lại ca để nạp dữ liệu mới trước khi lưu.",
                        StatusCodes.Status409Conflict);
                }

                var (rosterResult, roster) = await sheetsStore.GetRosterAsync(classCode, cancellationToken);
                if (!rosterResult.Success) return StoreFailure<AttendanceSnapshot>(rosterResult.Message);
                if (roster.Count == 0)
                    return Failure<AttendanceSnapshot>("Lớp chưa có sinh viên trên Google Sheets.");
                var now = DateTime.UtcNow;
                var sessionId = Guid.NewGuid().ToString("N");
                var records = roster.Select(student => new AttendanceRecord(
                    sessionId, student.RollNo, student.FullName, student.Email,
                    classCode, subjectCode, request.Slot, AttendanceStatuses.NotChecked,
                    null, string.Empty, string.Empty)).ToArray();
                var initial = RebuildSnapshot(new AttendanceSnapshot(
                    "success", sessionId, classCode, subjectCode, request.Slot,
                    date.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
                    false, now, now, 10, false, null, null,
                    records.Length, new DashboardStats(0, 0, 0, 0, 0, 0), records, []), []);
                stored = new StoredAttendanceSession(initial, [], []);
            }

            var current = stored.Snapshot;
            if (!current.ClassCode.Equals(classCode, StringComparison.OrdinalIgnoreCase) ||
                !current.SubjectCode.Equals(subjectCode, StringComparison.OrdinalIgnoreCase) ||
                current.Slot != request.Slot || !SameVietnamCalendarDate(current.Date, date))
            {
                return Failure<AttendanceSnapshot>("Phiên không khớp với ca học đã chọn.", StatusCodes.Status409Conflict);
            }
            if (current.IsOpen)
                return Failure<AttendanceSnapshot>("Phiên đang mở. Hãy nạp lại trước khi sửa hàng loạt.", StatusCodes.Status409Conflict);

            var recordsToSave = current.Students.ToArray();
            var audits = stored.AuditLogs.ToList();
            foreach (var change in changes)
            {
                var rollNo = change.RollNo!.Trim().ToUpperInvariant();
                var index = Array.FindIndex(recordsToSave, student =>
                    student.RollNo.Equals(rollNo, StringComparison.OrdinalIgnoreCase));
                if (index < 0)
                    return Failure<AttendanceSnapshot>($"Không tìm thấy sinh viên {rollNo} trong lớp.", StatusCodes.Status409Conflict);
                var previous = recordsToSave[index];
                if (!previous.Status.Equals(change.ExpectedStatus!.Trim(), StringComparison.OrdinalIgnoreCase))
                {
                    return Failure<AttendanceSnapshot>(
                        $"Trạng thái của {rollNo} đã đổi trên Google Sheets. Hãy kiểm tra lại trước khi lưu.",
                        StatusCodes.Status409Conflict);
                }
                var status = change.Status!.Trim().ToUpperInvariant();
                if (previous.Status.Equals(status, StringComparison.OrdinalIgnoreCase)) continue;
                recordsToSave[index] = previous with
                {
                    Status = status,
                    CheckinTime = status is AttendanceStatuses.Present or AttendanceStatuses.Late
                        ? previous.CheckinTime ?? DateTime.UtcNow : null,
                    Notes = "Giảng viên cập nhật thủ công (lưu hàng loạt)",
                };
                audits.Add(CreateAudit(current.SessionId, rollNo, "MANUAL_UPDATE",
                    previous.Status, status, CleanActor(request.Actor), "Lưu hàng loạt từ desktop"));
            }

            var snapshot = RebuildSnapshot(current with { Students = recordsToSave }, stored.DeviceBindings);
            var save = await sheetsStore.SaveSessionAsync(
                new StoredAttendanceSession(snapshot, audits, stored.DeviceBindings), cancellationToken);
            if (!save.Success) return StoreFailure<AttendanceSnapshot>(save.Message);
            await BroadcastAsync(snapshot.SessionId, "AttendanceUpdated", snapshot, cancellationToken);
            return new ServiceResult<AttendanceSnapshot>(true,
                $"Đã lưu {changes.Length} thay đổi lên Google Sheets.", snapshot);
        }
        finally
        {
            gate.Release();
        }
    }

    public async Task<AttendanceSnapshot?> GetSnapshotAsync(
        string? sessionId,
        CancellationToken cancellationToken)
    {
        var load = await sheetsStore.GetSessionAsync(sessionId, cancellationToken);
        if (!load.Result.Success)
        {
            throw new InvalidOperationException(load.Result.Message);
        }
        return load.Session is null ? null : ApplyOtpState(load.Session.Snapshot);
    }

    public async Task<ServiceResult<AttendanceSnapshot>> PauseOtpAsync(
        string sessionId,
        string? actor,
        CancellationToken cancellationToken)
    {
        var gate = GetSessionLock(sessionId);
        await gate.WaitAsync(cancellationToken);
        try
        {
            var load = await sheetsStore.GetSessionAsync(sessionId, cancellationToken);
            if (!load.Result.Success) return StoreFailure<AttendanceSnapshot>(load.Result.Message);
            if (load.Session is null)
            {
                return Failure<AttendanceSnapshot>("Không tìm thấy phiên điểm danh.", StatusCodes.Status404NotFound);
            }
            if (!load.Session.Snapshot.IsOpen)
            {
                return Failure<AttendanceSnapshot>("Phiên điểm danh đã đóng.", StatusCodes.Status409Conflict);
            }

            var paused = otpService.Pause(sessionId);
            var snapshot = RebuildSnapshot(load.Session.Snapshot with
            {
                OtpPaused = true,
                PausedOtp = paused.Otp,
                OtpRemainingSeconds = paused.RemainingSeconds,
            }, load.Session.DeviceBindings);
            var audits = load.Session.AuditLogs.Append(CreateAudit(
                sessionId,
                string.Empty,
                "OTP_PAUSED",
                string.Empty,
                string.Empty,
                CleanActor(actor),
                "Tạm dừng xoay QR, OTP và bộ đếm")).ToArray();
            var save = await sheetsStore.SaveSessionAsync(
                new StoredAttendanceSession(snapshot, audits, load.Session.DeviceBindings),
                cancellationToken);
            if (!save.Success) return StoreFailure<AttendanceSnapshot>(save.Message);
            await BroadcastAsync(sessionId, "OtpPaused", snapshot, cancellationToken);
            return new ServiceResult<AttendanceSnapshot>(true, "Đã tạm dừng QR và OTP.", snapshot);
        }
        finally
        {
            gate.Release();
        }
    }

    public async Task<ServiceResult<AttendanceSnapshot>> ResumeOtpAsync(
        string sessionId,
        string? actor,
        CancellationToken cancellationToken)
    {
        var gate = GetSessionLock(sessionId);
        await gate.WaitAsync(cancellationToken);
        try
        {
            var load = await sheetsStore.GetSessionAsync(sessionId, cancellationToken);
            if (!load.Result.Success) return StoreFailure<AttendanceSnapshot>(load.Result.Message);
            if (load.Session is null)
            {
                return Failure<AttendanceSnapshot>("Không tìm thấy phiên điểm danh.", StatusCodes.Status404NotFound);
            }
            if (!load.Session.Snapshot.IsOpen)
            {
                return Failure<AttendanceSnapshot>("Phiên điểm danh đã đóng.", StatusCodes.Status409Conflict);
            }

            otpService.Resume(sessionId);
            var snapshot = RebuildSnapshot(load.Session.Snapshot with
            {
                OtpPaused = false,
                PausedOtp = null,
                OtpRemainingSeconds = null,
            }, load.Session.DeviceBindings);
            var audits = load.Session.AuditLogs.Append(CreateAudit(
                sessionId,
                string.Empty,
                "OTP_RESUMED",
                string.Empty,
                string.Empty,
                CleanActor(actor),
                "Tiếp tục xoay QR, OTP và bộ đếm")).ToArray();
            var save = await sheetsStore.SaveSessionAsync(
                new StoredAttendanceSession(snapshot, audits, load.Session.DeviceBindings),
                cancellationToken);
            if (!save.Success) return StoreFailure<AttendanceSnapshot>(save.Message);
            await BroadcastAsync(sessionId, "OtpResumed", snapshot, cancellationToken);
            return new ServiceResult<AttendanceSnapshot>(true, "Đã tiếp tục xoay QR và OTP.", snapshot);
        }
        finally
        {
            gate.Release();
        }
    }

    public async Task<IReadOnlyCollection<AttendanceSnapshot>> GetRecentSessionsAsync(
        int limit,
        CancellationToken cancellationToken,
        string? classCode = null,
        string? subjectCode = null,
        int? slot = null)
    {
        var load = await sheetsStore.GetSessionsAsync(
            limit,
            cancellationToken,
            classCode,
            subjectCode,
            slot);
        if (!load.Result.Success)
        {
            throw new InvalidOperationException(load.Result.Message);
        }
        return load.Sessions.Select(item => ApplyOtpState(item.Snapshot)).ToArray();
    }

    public async Task<IReadOnlyCollection<AuditLogRecord>> GetAuditLogsAsync(
        string sessionId,
        CancellationToken cancellationToken)
    {
        var load = await sheetsStore.GetSessionAsync(sessionId, cancellationToken);
        if (!load.Result.Success)
        {
            throw new InvalidOperationException(load.Result.Message);
        }
        return load.Session is null
            ? []
            : load.Session.AuditLogs.OrderByDescending(log => log.CreatedAt).ToArray();
    }

    public async Task<(byte[] Content, string FileName)?> ExportCsvAsync(
        string sessionId,
        CancellationToken cancellationToken)
    {
        var snapshot = await GetSnapshotAsync(sessionId, cancellationToken);
        if (snapshot is null) return null;

        var csv = new StringBuilder();
        csv.AppendLine("RollNo,FullName,Email,ClassCode,SubjectCode,Slot,Date,Status,CheckinTime,Notes");
        foreach (var student in snapshot.Students)
        {
            csv.AppendLine(string.Join(',', new[]
            {
                EscapeCsv(student.RollNo),
                EscapeCsv(student.FullName),
                EscapeCsv(student.Email),
                EscapeCsv(student.ClassCode),
                EscapeCsv(student.SubjectCode),
                student.Slot.ToString(CultureInfo.InvariantCulture),
                EscapeCsv(snapshot.Date),
                EscapeCsv(student.Status),
                EscapeCsv(FormatCsvDateTime(student.CheckinTime)),
                EscapeCsv(student.Notes),
            }));
        }
        var content = Encoding.UTF8.GetPreamble().Concat(Encoding.UTF8.GetBytes(csv.ToString())).ToArray();
        return (content, $"attendance-{snapshot.SubjectCode}-{snapshot.ClassCode}-slot{snapshot.Slot}-{snapshot.Date}.csv");
    }

    private AttendanceSnapshot ApplyOtpState(AttendanceSnapshot snapshot)
    {
        if (!snapshot.OtpPaused)
        {
            otpService.Resume(snapshot.SessionId);
            return snapshot with { PausedOtp = null, OtpRemainingSeconds = null };
        }
        var paused = otpService.GetPausedState(snapshot.SessionId) ?? otpService.Pause(snapshot.SessionId);
        return snapshot with
        {
            OtpPaused = true,
            PausedOtp = paused.Otp,
            OtpRemainingSeconds = paused.RemainingSeconds,
        };
    }

    private static AttendanceSnapshot RebuildSnapshot(
        AttendanceSnapshot snapshot,
        IReadOnlyCollection<StoredDeviceBinding> bindings)
    {
        var students = snapshot.Students.ToArray();
        var present = students.Count(student => student.Status == AttendanceStatuses.Present);
        var late = students.Count(student => student.Status == AttendanceStatuses.Late);
        var absent = students.Count(student => student.Status == AttendanceStatuses.Absent);
        var notChecked = students.Count(student => student.Status == AttendanceStatuses.NotChecked);
        var stats = new DashboardStats(
            students.Length,
            present,
            late,
            absent,
            notChecked,
            students.Length == 0 ? 0 : (present + late) * 100.0 / students.Length);
        var publicBindings = bindings.Select(binding => new DeviceBindingRecord(
            binding.Id,
            binding.DeviceCode,
            binding.RollNo,
            binding.FirstSeen,
            binding.LastSeen,
            binding.BlockedAttempts,
            binding.LastBlockedRollNo,
            binding.LastBlockedAt)).ToArray();
        return snapshot with
        {
            Count = students.Length,
            Stats = stats,
            Students = students,
            DeviceBindings = publicBindings,
        };
    }

    private async Task BroadcastAsync(
        string sessionId,
        string eventName,
        AttendanceSnapshot? snapshot,
        CancellationToken cancellationToken)
    {
        updateStream.Publish(eventName, snapshot);
        await hubContext.Clients.Group(AttendanceHub.GetGroupName(sessionId))
            .SendAsync(eventName, snapshot, cancellationToken);
    }

    private static SemaphoreSlim GetSessionLock(string sessionId) =>
        SessionLocks.GetOrAdd(sessionId, _ => new SemaphoreSlim(1, 1));

    private static long NewId() => Interlocked.Increment(ref generatedId);

    private static StudentSeed[] NormalizeStudents(IReadOnlyCollection<StudentSeed>? students) =>
        (students ?? [])
            .Where(student => !string.IsNullOrWhiteSpace(student.RollNo))
            .Select(student =>
            {
                var rollNo = student.RollNo!.Trim().ToUpperInvariant();
                return new StudentSeed(
                    rollNo,
                    string.IsNullOrWhiteSpace(student.FullName) ? rollNo : student.FullName.Trim(),
                    student.Email?.Trim().ToLowerInvariant() ?? string.Empty);
            })
            .DistinctBy(student => student.RollNo, StringComparer.OrdinalIgnoreCase)
            .ToArray();

    private static AuditLogRecord CreateAudit(
        string sessionId,
        string rollNo,
        string action,
        string previousStatus,
        string newStatus,
        string actor,
        string reason) => new(
            NewId(),
            sessionId,
            rollNo,
            action,
            previousStatus,
            newStatus,
            actor,
            reason,
            DateTime.UtcNow);

    private static string CreateConfirmationCode(
        string email,
        string sessionId,
        string rollNo,
        DateTime checkinTime)
    {
        var payload = $"{email}|{sessionId}|{rollNo}|{checkinTime:O}";
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(payload)))[..16];
    }

    private static string FormatCsvDateTime(DateTime? value) =>
        value?.ToLocalTime().ToString("dd/MM/yyyy HH:mm:ss", CultureInfo.InvariantCulture) ?? string.Empty;

    private static string EscapeCsv(string value) =>
        value.IndexOfAny([',', '"', '\r', '\n']) < 0
            ? value
            : $"\"{value.Replace("\"", "\"\"")}\"";

    private static string ParseDate(string? value, DateTime fallback) =>
        DateTime.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.None, out var parsed)
            ? parsed.ToString("yyyy-MM-dd")
            : fallback.ToString("yyyy-MM-dd");

    private static bool SameVietnamCalendarDate(string? value, DateOnly date)
    {
        if (DateOnly.TryParseExact(value, "yyyy-MM-dd", CultureInfo.InvariantCulture,
                DateTimeStyles.None, out var plainDate))
            return plainDate == date;
        return DateTimeOffset.TryParse(value, CultureInfo.InvariantCulture,
                   DateTimeStyles.AssumeUniversal, out var instant) &&
               DateOnly.FromDateTime(instant.ToOffset(TimeSpan.FromHours(7)).DateTime) == date;
    }

    private static string CleanActor(string? actor) =>
        string.IsNullOrWhiteSpace(actor) ? "Giảng viên" : actor.Trim();

    private static ServiceResult<T> StoreFailure<T>(string message) =>
        new(false, message, default, StatusCodes.Status502BadGateway, "GOOGLE_SHEETS_ERROR");

    private static ServiceResult<T> Failure<T>(
        string message,
        int statusCode = StatusCodes.Status400BadRequest,
        string? code = null) =>
        new(false, message, default, statusCode, code);
}
