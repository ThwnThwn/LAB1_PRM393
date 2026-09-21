using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using Attendance.Api.Data;
using Attendance.Api.Hubs;
using Attendance.Api.Models;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;

namespace Attendance.Api.Services;

public sealed class AttendanceService(
    AttendanceDbContext dbContext,
    OtpService otpService,
    IHubContext<AttendanceHub> hubContext)
{
    public async Task<IReadOnlyCollection<RosterStudentRecord>> GetClassRosterAsync(
        string classCode,
        CancellationToken cancellationToken)
    {
        var normalizedClassCode = classCode.Trim().ToUpperInvariant();
        if (normalizedClassCode.Length == 0)
        {
            return [];
        }

        return await dbContext.ClassRosterStudents.AsNoTracking()
            .Where(student => student.ClassCode == normalizedClassCode)
            .OrderBy(student => student.RollNo)
            .Select(student => new RosterStudentRecord(
                student.RollNo,
                student.FullName,
                student.Email))
            .ToArrayAsync(cancellationToken);
    }

    public async Task<IReadOnlyDictionary<string, IReadOnlyCollection<RosterStudentRecord>>>
        GetAllClassRostersAsync(CancellationToken cancellationToken)
    {
        var students = await dbContext.ClassRosterStudents.AsNoTracking()
            .OrderBy(student => student.ClassCode)
            .ThenBy(student => student.RollNo)
            .ToListAsync(cancellationToken);
        return students
            .GroupBy(student => student.ClassCode)
            .ToDictionary(
                group => group.Key,
                group => (IReadOnlyCollection<RosterStudentRecord>)group
                    .Select(student => new RosterStudentRecord(
                        student.RollNo,
                        student.FullName,
                        student.Email))
                    .ToArray());
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

        AttendanceSessionEntity? session = null;
        if (!string.IsNullOrWhiteSpace(request.SessionId))
        {
            session = await dbContext.Sessions
                .Include(item => item.AttendanceEntries)
                .FirstOrDefaultAsync(item => item.Id == request.SessionId, cancellationToken);
            if (session is null)
            {
                return Failure<RosterSyncSnapshot>(
                    "Không tìm thấy phiên điểm danh.",
                    StatusCodes.Status404NotFound);
            }
            if (!session.IsOpen)
            {
                return Failure<RosterSyncSnapshot>(
                    "Phiên điểm danh đã đóng.",
                    StatusCodes.Status409Conflict);
            }
            if (!session.ClassCode.Equals(normalizedClassCode, StringComparison.OrdinalIgnoreCase))
            {
                return Failure<RosterSyncSnapshot>("Danh sách CSV không thuộc lớp của phiên đang mở.");
            }
        }

        await ReplaceClassRosterAsync(normalizedClassCode, students, cancellationToken);

        if (session is not null)
        {
            var incomingRollNumbers = students
                .Select(student => student.RollNo!)
                .ToHashSet(StringComparer.OrdinalIgnoreCase);
            var existingEntries = session.AttendanceEntries
                .ToDictionary(entry => entry.RollNo, StringComparer.OrdinalIgnoreCase);
            var now = DateTime.UtcNow;

            foreach (var student in students)
            {
                var rollNo = student.RollNo!;
                if (existingEntries.TryGetValue(rollNo, out var existingEntry))
                {
                    existingEntry.FullName = student.FullName!;
                    existingEntry.Email = student.Email!;
                    existingEntry.UpdatedAtUtc = now;
                }
                else
                {
                    session.AttendanceEntries.Add(new AttendanceEntryEntity
                    {
                        RollNo = rollNo,
                        FullName = student.FullName!,
                        Email = student.Email!,
                        Status = AttendanceStatuses.NotChecked,
                        UpdatedAtUtc = now,
                    });
                }
            }

            var removableEntries = session.AttendanceEntries
                .Where(entry =>
                    !incomingRollNumbers.Contains(entry.RollNo) &&
                    !entry.CheckinTimeUtc.HasValue)
                .ToArray();
            dbContext.AttendanceEntries.RemoveRange(removableEntries);

            dbContext.AuditLogs.Add(CreateAudit(
                session.Id,
                string.Empty,
                "ROSTER_SYNCED",
                existingEntries.Count.ToString(CultureInfo.InvariantCulture),
                students.Length.ToString(CultureInfo.InvariantCulture),
                CleanActor(request.Actor),
                $"Đồng bộ {students.Length} sinh viên từ CSV"));
        }

        await dbContext.SaveChangesAsync(cancellationToken);

        var roster = await GetClassRosterAsync(normalizedClassCode, cancellationToken);
        var sessionSnapshot = session is null
            ? null
            : await GetSnapshotAsync(session.Id, cancellationToken);
        if (sessionSnapshot is not null)
        {
            await BroadcastAsync(session!.Id, "RosterUpdated", sessionSnapshot, cancellationToken);
        }

        var snapshot = new RosterSyncSnapshot(
            "success",
            normalizedClassCode,
            roster.Count,
            roster,
            sessionSnapshot);
        return new ServiceResult<RosterSyncSnapshot>(
            true,
            $"Đã lưu {roster.Count} sinh viên vào database.",
            snapshot);
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

        var existing = await dbContext.Sessions
            .AsNoTracking()
            .Where(session => session.IsOpen &&
                              session.ClassCode == classCode &&
                              session.SubjectCode == subjectCode &&
                              session.Slot == request.Slot)
            .OrderByDescending(session => session.OpenedAtUtc)
            .FirstOrDefaultAsync(cancellationToken);

        if (existing is not null)
        {
            var existingSnapshot = await GetSnapshotAsync(existing.Id, cancellationToken);
            return new ServiceResult<AttendanceSnapshot>(
                true,
                "Phiên điểm danh này đang mở.",
                existingSnapshot);
        }

        var now = DateTime.UtcNow;
        var session = new AttendanceSessionEntity
        {
            ClassCode = classCode,
            SubjectCode = subjectCode,
            Slot = request.Slot,
            SessionDate = ParseDate(request.Date, now),
            IsOpen = true,
            LateAfterMinutes = request.LateAfterMinutes <= 0 ? 10 : request.LateAfterMinutes,
            OpenedAtUtc = now,
            CreatedBy = CleanActor(request.Actor),
        };

        var students = NormalizeStudents(request.Students);
        await ReplaceClassRosterAsync(classCode, students, cancellationToken);

        foreach (var student in students)
        {
            session.AttendanceEntries.Add(new AttendanceEntryEntity
            {
                RollNo = student.RollNo!.Trim().ToUpperInvariant(),
                FullName = student.FullName?.Trim() ?? student.RollNo.Trim().ToUpperInvariant(),
                Email = student.Email?.Trim().ToLowerInvariant() ?? string.Empty,
                Status = AttendanceStatuses.NotChecked,
                UpdatedAtUtc = now,
            });
        }

        dbContext.Sessions.Add(session);
        otpService.Resume(session.Id);
        dbContext.AuditLogs.Add(CreateAudit(
            session.Id,
            string.Empty,
            "SESSION_OPENED",
            string.Empty,
            string.Empty,
            session.CreatedBy,
            $"Mở phiên {subjectCode} - {classCode}, Slot {request.Slot}"));
        await dbContext.SaveChangesAsync(cancellationToken);

        var snapshot = await GetSnapshotAsync(session.Id, cancellationToken);
        await BroadcastAsync(session.Id, "SessionOpened", snapshot, cancellationToken);
        return new ServiceResult<AttendanceSnapshot>(true, "Đã mở phiên điểm danh.", snapshot);
    }

    public async Task<ServiceResult<AttendanceSnapshot>> CloseSessionAsync(
        string sessionId,
        string? actor,
        CancellationToken cancellationToken)
    {
        var session = await dbContext.Sessions
            .Include(item => item.AttendanceEntries)
            .FirstOrDefaultAsync(item => item.Id == sessionId, cancellationToken);

        if (session is null)
        {
            return Failure<AttendanceSnapshot>("Không tìm thấy phiên điểm danh.", StatusCodes.Status404NotFound);
        }

        if (!session.IsOpen)
        {
            var closedSnapshot = await GetSnapshotAsync(session.Id, cancellationToken);
            return new ServiceResult<AttendanceSnapshot>(true, "Phiên điểm danh đã đóng.", closedSnapshot);
        }

        var now = DateTime.UtcNow;
        var changedBy = CleanActor(actor);
        foreach (var entry in session.AttendanceEntries.Where(entry => entry.Status == AttendanceStatuses.NotChecked))
        {
            entry.Status = AttendanceStatuses.Absent;
            entry.UpdatedAtUtc = now;
            entry.Notes = "Tự động đánh vắng khi đóng phiên";
            dbContext.AuditLogs.Add(CreateAudit(
                session.Id,
                entry.RollNo,
                "STATUS_CHANGED",
                AttendanceStatuses.NotChecked,
                AttendanceStatuses.Absent,
                changedBy,
                entry.Notes));
        }

        session.IsOpen = false;
        session.ClosedAtUtc = now;
        otpService.Resume(session.Id);
        dbContext.AuditLogs.Add(CreateAudit(
            session.Id,
            string.Empty,
            "SESSION_CLOSED",
            string.Empty,
            string.Empty,
            changedBy,
            "Đóng phiên điểm danh"));
        await dbContext.SaveChangesAsync(cancellationToken);

        var snapshot = await GetSnapshotAsync(session.Id, cancellationToken);
        await BroadcastAsync(session.Id, "SessionClosed", snapshot, cancellationToken);
        return new ServiceResult<AttendanceSnapshot>(true, "Đã đóng phiên điểm danh.", snapshot);
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

        var session = await dbContext.Sessions
            .FirstOrDefaultAsync(item => item.Id == request.SessionId, cancellationToken);
        if (session is null)
        {
            return Failure<AttendanceSnapshot>("Phiên điểm danh không tồn tại.", StatusCodes.Status404NotFound);
        }

        if (!session.IsOpen)
        {
            return Failure<AttendanceSnapshot>("Phiên điểm danh đã đóng.", StatusCodes.Status409Conflict);
        }

        if (!otpService.ValidateForSession(session.Id, request.Otp))
        {
            return Failure<AttendanceSnapshot>("Mã OTP không hợp lệ hoặc đã hết hạn.");
        }

        var rollNo = request.RollNo!.Trim().ToUpperInvariant();
        var email = request.Email!.Trim().ToLowerInvariant();
        var rosterStudent = await dbContext.ClassRosterStudents
            .AsNoTracking()
            .FirstOrDefaultAsync(
                item => item.ClassCode == session.ClassCode && item.RollNo == rollNo,
                cancellationToken);
        var entry = await dbContext.AttendanceEntries
            .AsNoTracking()
            .FirstOrDefaultAsync(
                item => item.SessionId == session.Id && item.RollNo == rollNo,
                cancellationToken);

        if (entry is null && rosterStudent is null)
        {
            return Failure<AttendanceSnapshot>(
                "MSSV không có trong danh sách lớp của phiên điểm danh.",
                StatusCodes.Status404NotFound,
                "STUDENT_NOT_IN_ROSTER");
        }

        if (rosterStudent is not null &&
            !string.IsNullOrWhiteSpace(rosterStudent.Email) &&
            !rosterStudent.Email.Equals(email, StringComparison.OrdinalIgnoreCase))
        {
            return Failure<AttendanceSnapshot>(
                "Email không khớp với MSSV trong danh sách lớp.",
                StatusCodes.Status403Forbidden,
                "STUDENT_EMAIL_MISMATCH");
        }

        var now = DateTime.UtcNow;
        var deviceBinding = await dbContext.AttendanceDeviceBindings
            .FirstOrDefaultAsync(
                item => item.SessionId == session.Id &&
                        item.DeviceHash == deviceIdentity.DeviceHash,
                cancellationToken);
        // A cleared cookie or private browser window still originates from the
        // same phone address on the lecturer's local hotspot/LAN. Use that as a
        // secondary signal while keeping the signed cookie as the primary key.
        deviceBinding ??= await dbContext.AttendanceDeviceBindings
            .FirstOrDefaultAsync(
                item => item.SessionId == session.Id &&
                        item.NetworkHash == deviceIdentity.NetworkHash,
                cancellationToken);

        if (deviceBinding is not null &&
            !deviceBinding.RollNo.Equals(rollNo, StringComparison.OrdinalIgnoreCase))
        {
            deviceBinding.LastSeenUtc = now;
            deviceBinding.BlockedAttempts += 1;
            deviceBinding.LastBlockedRollNo = rollNo;
            deviceBinding.LastBlockedAtUtc = now;
            deviceBinding.NetworkHash = deviceIdentity.NetworkHash;
            deviceBinding.UserAgentHash = deviceIdentity.UserAgentHash;
            dbContext.AuditLogs.Add(CreateAudit(
                session.Id,
                rollNo,
                "DEVICE_CHECKIN_BLOCKED",
                deviceBinding.RollNo,
                rollNo,
                $"Thiết bị {deviceIdentity.DeviceCode}",
                $"Thiết bị đã được gắn với {deviceBinding.RollNo}"));
            await dbContext.SaveChangesAsync(cancellationToken);

            var blockedSnapshot = await GetSnapshotAsync(session.Id, cancellationToken);
            await BroadcastAsync(session.Id, "DeviceConflict", blockedSnapshot, cancellationToken);
            return new ServiceResult<AttendanceSnapshot>(
                false,
                "Thiết bị này đã được dùng cho một MSSV khác trong phiên. Hãy liên hệ giảng viên để mở khóa.",
                blockedSnapshot,
                StatusCodes.Status409Conflict,
                "DEVICE_ALREADY_USED");
        }

        if (deviceBinding is null)
        {
            deviceBinding = new AttendanceDeviceBindingEntity
            {
                SessionId = session.Id,
                DeviceHash = deviceIdentity.DeviceHash,
                RollNo = rollNo,
                FirstSeenUtc = now,
                LastSeenUtc = now,
                NetworkHash = deviceIdentity.NetworkHash,
                UserAgentHash = deviceIdentity.UserAgentHash,
            };
            dbContext.AttendanceDeviceBindings.Add(deviceBinding);
        }
        else
        {
            deviceBinding.LastSeenUtc = now;
            deviceBinding.NetworkHash = deviceIdentity.NetworkHash;
            deviceBinding.UserAgentHash = deviceIdentity.UserAgentHash;
        }

        if (entry is not null && entry.CheckinTimeUtc.HasValue)
        {
            await dbContext.SaveChangesAsync(cancellationToken);
            var duplicateSnapshot = await GetSnapshotAsync(session.Id, cancellationToken);
            return new ServiceResult<AttendanceSnapshot>(
                false,
                $"{rollNo} đã điểm danh lúc {entry.CheckinTimeUtc.Value.ToLocalTime():HH:mm:ss}.",
                duplicateSnapshot,
                StatusCodes.Status409Conflict);
        }

        var status = now > session.OpenedAtUtc.AddMinutes(session.LateAfterMinutes)
            ? AttendanceStatuses.Late
            : AttendanceStatuses.Present;
        var previousStatus = entry?.Status ?? string.Empty;
        var confirmationCode = CreateConfirmationCode(email, session.Id, rollNo, now);

        if (entry is null)
        {
            var submittedName = request.FullName?.Trim();
            var fullName = rosterStudent?.FullName
                ?? (!string.IsNullOrWhiteSpace(submittedName) &&
                    !submittedName.Equals(rollNo, StringComparison.OrdinalIgnoreCase)
                        ? submittedName
                        : rollNo);
            entry = new AttendanceEntryEntity
            {
                SessionId = session.Id,
                RollNo = rollNo,
                FullName = fullName,
                Email = email,
            };
            dbContext.AttendanceEntries.Add(entry);
        }
        else
        {
            // The imported roster is authoritative. Never let a student-submitted
            // value (often just the MSSV) overwrite the saved full name.
            var fullName = rosterStudent?.FullName ?? entry.FullName;
            var affected = await dbContext.AttendanceEntries
                .Where(item => item.Id == entry.Id && item.CheckinTimeUtc == null)
                .ExecuteUpdateAsync(
                    setters => setters
                        .SetProperty(item => item.FullName, fullName)
                        .SetProperty(item => item.Email, email)
                        .SetProperty(item => item.Status, status)
                        .SetProperty(item => item.CheckinTimeUtc, now)
                        .SetProperty(item => item.UpdatedAtUtc, now)
                        .SetProperty(item => item.Notes, "Điểm danh bằng QR/OTP")
                        .SetProperty(item => item.ConfirmationCode, confirmationCode),
                    cancellationToken);

            if (affected == 0)
            {
                var duplicateSnapshot = await GetSnapshotAsync(session.Id, cancellationToken);
                return new ServiceResult<AttendanceSnapshot>(
                    false,
                    $"{rollNo} đã điểm danh trong phiên này.",
                    duplicateSnapshot,
                    StatusCodes.Status409Conflict);
            }
        }

        if (entry.Id == 0)
        {
            entry.Status = status;
            entry.CheckinTimeUtc = now;
            entry.UpdatedAtUtc = now;
            entry.Notes = "Điểm danh bằng QR/OTP";
            entry.ConfirmationCode = confirmationCode;
        }
        dbContext.AuditLogs.Add(CreateAudit(
            session.Id,
            rollNo,
            "STUDENT_CHECKIN",
            previousStatus,
            status,
            rollNo,
            "Điểm danh bằng QR/OTP"));

        try
        {
            await dbContext.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateException)
        {
            return Failure<AttendanceSnapshot>(
                $"{rollNo} đã điểm danh trong phiên này.",
                StatusCodes.Status409Conflict);
        }

        var snapshot = await GetSnapshotAsync(session.Id, cancellationToken);
        await BroadcastAsync(session.Id, "AttendanceUpdated", snapshot, cancellationToken);
        return new ServiceResult<AttendanceSnapshot>(true, "Điểm danh thành công.", snapshot);
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

        var binding = await dbContext.AttendanceDeviceBindings
            .FirstOrDefaultAsync(
                item => item.Id == bindingId && item.SessionId == sessionId,
                cancellationToken);
        if (binding is null)
        {
            return Failure<AttendanceSnapshot>(
                "Không tìm thấy thiết bị cần mở khóa.",
                StatusCodes.Status404NotFound);
        }

        dbContext.AuditLogs.Add(CreateAudit(
            sessionId,
            binding.RollNo,
            "DEVICE_BINDING_RELEASED",
            binding.RollNo,
            string.Empty,
            CleanActor(request.Actor),
            $"{reason} • Thiết bị {binding.DeviceHash[..8]}"));
        dbContext.AttendanceDeviceBindings.Remove(binding);
        await dbContext.SaveChangesAsync(cancellationToken);

        var snapshot = await GetSnapshotAsync(sessionId, cancellationToken);
        await BroadcastAsync(sessionId, "DeviceBindingReleased", snapshot, cancellationToken);
        return new ServiceResult<AttendanceSnapshot>(
            true,
            "Đã mở khóa thiết bị. Thiết bị có thể điểm danh lại cho một MSSV khác.",
            snapshot);
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

        var normalizedRollNo = rollNo.Trim().ToUpperInvariant();
        var entry = await dbContext.AttendanceEntries
            .FirstOrDefaultAsync(
                item => item.SessionId == sessionId && item.RollNo == normalizedRollNo,
                cancellationToken);
        if (entry is null)
        {
            return Failure<AttendanceSnapshot>("Không tìm thấy sinh viên trong phiên.", StatusCodes.Status404NotFound);
        }

        var expectedStatus = request.ExpectedStatus?.Trim().ToUpperInvariant();
        if (!string.IsNullOrEmpty(expectedStatus) &&
            !entry.Status.Equals(expectedStatus, StringComparison.OrdinalIgnoreCase))
        {
            return Failure<AttendanceSnapshot>(
                "Trạng thái đã được thay đổi ở cửa sổ khác. Hãy nạp lại dữ liệu trước khi lưu.",
                StatusCodes.Status409Conflict);
        }

        var previousStatus = entry.Status;
        DateTime? checkinTime = normalizedStatus is AttendanceStatuses.Present or AttendanceStatuses.Late
            ? entry.CheckinTimeUtc ?? DateTime.UtcNow
            : null;
        var updatedAt = DateTime.UtcNow;
        var notes = request.Reason?.Trim() ?? "Giảng viên cập nhật thủ công";

        // Compare-and-update in the database so two windows cannot both save
        // edits based on the same stale status.
        await using var transaction = await dbContext.Database.BeginTransactionAsync(cancellationToken);
        var updateQuery = dbContext.AttendanceEntries.Where(item => item.Id == entry.Id);
        if (!string.IsNullOrEmpty(expectedStatus))
        {
            updateQuery = updateQuery.Where(item => item.Status == expectedStatus);
        }

        var updated = await updateQuery.ExecuteUpdateAsync(
            setters => setters
                .SetProperty(item => item.Status, normalizedStatus)
                .SetProperty(item => item.CheckinTimeUtc, checkinTime)
                .SetProperty(item => item.UpdatedAtUtc, updatedAt)
                .SetProperty(item => item.Notes, notes),
            cancellationToken);
        if (updated == 0)
        {
            return Failure<AttendanceSnapshot>(
                "Trạng thái đã được thay đổi ở cửa sổ khác. Hãy nạp lại dữ liệu trước khi lưu.",
                StatusCodes.Status409Conflict);
        }

        dbContext.AuditLogs.Add(CreateAudit(
            sessionId,
            entry.RollNo,
            "MANUAL_UPDATE",
            previousStatus,
            normalizedStatus,
            CleanActor(request.Actor),
            notes));
        await dbContext.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);

        var snapshot = await GetSnapshotAsync(sessionId, cancellationToken);
        await BroadcastAsync(sessionId, "AttendanceUpdated", snapshot, cancellationToken);
        return new ServiceResult<AttendanceSnapshot>(true, "Đã cập nhật trạng thái.", snapshot);
    }

    public async Task<AttendanceSnapshot?> GetSnapshotAsync(
        string? sessionId,
        CancellationToken cancellationToken)
    {
        var session = string.IsNullOrWhiteSpace(sessionId)
            ? await dbContext.Sessions.AsNoTracking()
                // FAP Demo must keep showing the same latest session after it
                // closes, even when an older session was left open.
                .OrderByDescending(item => item.OpenedAtUtc)
                .FirstOrDefaultAsync(cancellationToken)
            : await dbContext.Sessions.AsNoTracking()
                .FirstOrDefaultAsync(item => item.Id == sessionId, cancellationToken);

        if (session is null)
        {
            return null;
        }

        var entries = await dbContext.AttendanceEntries.AsNoTracking()
            .Where(item => item.SessionId == session.Id)
            .OrderBy(item => item.RollNo)
            .ToListAsync(cancellationToken);
        var deviceBindings = await dbContext.AttendanceDeviceBindings.AsNoTracking()
            .Where(item => item.SessionId == session.Id)
            .OrderByDescending(item => item.BlockedAttempts)
            .ThenByDescending(item => item.LastBlockedAtUtc)
            .Select(item => new DeviceBindingRecord(
                item.Id,
                item.DeviceHash.Substring(0, 8),
                item.RollNo,
                AsUtc(item.FirstSeenUtc),
                AsUtc(item.LastSeenUtc),
                item.BlockedAttempts,
                item.LastBlockedRollNo,
                item.LastBlockedAtUtc == null ? null : AsUtc(item.LastBlockedAtUtc.Value)))
            .ToArrayAsync(cancellationToken);

        var records = entries.Select(entry => ToRecord(entry, session)).ToArray();
        var present = entries.Count(entry => entry.Status == AttendanceStatuses.Present);
        var late = entries.Count(entry => entry.Status == AttendanceStatuses.Late);
        var absent = entries.Count(entry => entry.Status == AttendanceStatuses.Absent);
        var notChecked = entries.Count(entry => entry.Status == AttendanceStatuses.NotChecked);
        var percentage = entries.Count == 0 ? 0 : (present + late) * 100.0 / entries.Count;
        var stats = new DashboardStats(entries.Count, present, late, absent, notChecked, percentage);
        var pausedOtp = otpService.GetPausedState(session.Id);

        return new AttendanceSnapshot(
            "success",
            session.Id,
            session.ClassCode,
            session.SubjectCode,
            session.Slot,
            session.SessionDate,
            session.IsOpen,
            AsUtc(session.OpenedAtUtc),
            session.ClosedAtUtc is null ? null : AsUtc(session.ClosedAtUtc.Value),
            session.LateAfterMinutes,
            pausedOtp is not null,
            pausedOtp?.Otp,
            pausedOtp?.RemainingSeconds,
            entries.Count,
            stats,
            records,
            deviceBindings);
    }

    public async Task<ServiceResult<AttendanceSnapshot>> PauseOtpAsync(
        string sessionId,
        string? actor,
        CancellationToken cancellationToken)
    {
        var session = await dbContext.Sessions
            .AsNoTracking()
            .FirstOrDefaultAsync(item => item.Id == sessionId, cancellationToken);
        if (session is null)
        {
            return Failure<AttendanceSnapshot>("Không tìm thấy phiên điểm danh.", StatusCodes.Status404NotFound);
        }

        if (!session.IsOpen)
        {
            return Failure<AttendanceSnapshot>("Phiên điểm danh đã đóng.", StatusCodes.Status409Conflict);
        }

        otpService.Pause(sessionId);
        dbContext.AuditLogs.Add(CreateAudit(
            sessionId,
            string.Empty,
            "OTP_PAUSED",
            string.Empty,
            string.Empty,
            CleanActor(actor),
            "Tạm dừng QR, OTP và bộ đếm"));
        await dbContext.SaveChangesAsync(cancellationToken);

        var snapshot = await GetSnapshotAsync(sessionId, cancellationToken);
        await BroadcastAsync(sessionId, "OtpPaused", snapshot, cancellationToken);
        return new ServiceResult<AttendanceSnapshot>(true, "Đã tạm dừng QR và OTP.", snapshot);
    }

    public async Task<ServiceResult<AttendanceSnapshot>> ResumeOtpAsync(
        string sessionId,
        string? actor,
        CancellationToken cancellationToken)
    {
        var session = await dbContext.Sessions
            .AsNoTracking()
            .FirstOrDefaultAsync(item => item.Id == sessionId, cancellationToken);
        if (session is null)
        {
            return Failure<AttendanceSnapshot>("Không tìm thấy phiên điểm danh.", StatusCodes.Status404NotFound);
        }

        if (!session.IsOpen)
        {
            return Failure<AttendanceSnapshot>("Phiên điểm danh đã đóng.", StatusCodes.Status409Conflict);
        }

        otpService.Resume(sessionId);
        dbContext.AuditLogs.Add(CreateAudit(
            sessionId,
            string.Empty,
            "OTP_RESUMED",
            string.Empty,
            string.Empty,
            CleanActor(actor),
            "Tiếp tục xoay QR, OTP và bộ đếm"));
        await dbContext.SaveChangesAsync(cancellationToken);

        var snapshot = await GetSnapshotAsync(sessionId, cancellationToken);
        await BroadcastAsync(sessionId, "OtpResumed", snapshot, cancellationToken);
        return new ServiceResult<AttendanceSnapshot>(true, "Đã tiếp tục xoay QR và OTP.", snapshot);
    }

    public async Task<IReadOnlyCollection<AttendanceSnapshot>> GetRecentSessionsAsync(
        int limit,
        CancellationToken cancellationToken)
    {
        var safeLimit = Math.Clamp(limit, 1, 100);
        var sessionIds = await dbContext.Sessions.AsNoTracking()
            .OrderByDescending(session => session.OpenedAtUtc)
            .Select(session => session.Id)
            .Take(safeLimit)
            .ToListAsync(cancellationToken);
        var sessions = new List<AttendanceSnapshot>(sessionIds.Count);
        foreach (var sessionId in sessionIds)
        {
            var snapshot = await GetSnapshotAsync(sessionId, cancellationToken);
            if (snapshot is not null)
            {
                sessions.Add(snapshot);
            }
        }

        return sessions;
    }

    public async Task<IReadOnlyCollection<AuditLogRecord>> GetAuditLogsAsync(
        string sessionId,
        CancellationToken cancellationToken)
    {
        var logs = await dbContext.AuditLogs.AsNoTracking()
            .Where(log => log.SessionId == sessionId)
            .OrderByDescending(log => log.CreatedAtUtc)
            .ToListAsync(cancellationToken);

        return logs.Select(log => new AuditLogRecord(
                log.Id,
                log.SessionId,
                log.RollNo,
                log.Action,
                log.PreviousStatus,
                log.NewStatus,
                log.Actor,
                log.Reason,
                AsUtc(log.CreatedAtUtc)))
            .ToArray();
    }

    public async Task<(byte[] Content, string FileName)?> ExportCsvAsync(
        string sessionId,
        CancellationToken cancellationToken)
    {
        var snapshot = await GetSnapshotAsync(sessionId, cancellationToken);
        if (snapshot is null)
        {
            return null;
        }

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
        var fileName = $"attendance-{snapshot.SubjectCode}-{snapshot.ClassCode}-slot{snapshot.Slot}-{snapshot.Date}.csv";
        return (content, fileName);
    }

    private async Task BroadcastAsync(
        string sessionId,
        string eventName,
        AttendanceSnapshot? snapshot,
        CancellationToken cancellationToken)
    {
        await hubContext.Clients.Group(AttendanceHub.GetGroupName(sessionId))
            .SendAsync(eventName, snapshot, cancellationToken);
    }

    private async Task ReplaceClassRosterAsync(
        string classCode,
        IReadOnlyCollection<StudentSeed> students,
        CancellationToken cancellationToken)
    {
        var existing = await dbContext.ClassRosterStudents
            .Where(student => student.ClassCode == classCode)
            .ToListAsync(cancellationToken);
        var existingByRollNo = existing
            .ToDictionary(student => student.RollNo, StringComparer.OrdinalIgnoreCase);
        var incomingRollNumbers = students
            .Select(student => student.RollNo!)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var now = DateTime.UtcNow;

        foreach (var student in students)
        {
            var rollNo = student.RollNo!;
            if (existingByRollNo.TryGetValue(rollNo, out var existingStudent))
            {
                existingStudent.FullName = student.FullName!;
                existingStudent.Email = student.Email!;
                existingStudent.UpdatedAtUtc = now;
            }
            else
            {
                dbContext.ClassRosterStudents.Add(new ClassRosterStudentEntity
                {
                    ClassCode = classCode,
                    RollNo = rollNo,
                    FullName = student.FullName!,
                    Email = student.Email!,
                    UpdatedAtUtc = now,
                });
            }
        }

        dbContext.ClassRosterStudents.RemoveRange(
            existing.Where(student => !incomingRollNumbers.Contains(student.RollNo)));
    }

    private static StudentSeed[] NormalizeStudents(
        IReadOnlyCollection<StudentSeed>? students) =>
        (students ?? [])
            .Where(student => !string.IsNullOrWhiteSpace(student.RollNo))
            .Select(student =>
            {
                var rollNo = student.RollNo!.Trim().ToUpperInvariant();
                return new StudentSeed(
                    rollNo,
                    string.IsNullOrWhiteSpace(student.FullName)
                        ? rollNo
                        : student.FullName.Trim(),
                    student.Email?.Trim().ToLowerInvariant() ?? string.Empty);
            })
            .DistinctBy(student => student.RollNo, StringComparer.OrdinalIgnoreCase)
            .ToArray();

    private static AttendanceRecord ToRecord(
        AttendanceEntryEntity entry,
        AttendanceSessionEntity session) => new(
            session.Id,
            entry.RollNo,
            entry.FullName,
            entry.Email,
            session.ClassCode,
            session.SubjectCode,
            session.Slot,
            entry.Status,
            entry.CheckinTimeUtc is null ? null : AsUtc(entry.CheckinTimeUtc.Value),
            entry.Notes,
            entry.ConfirmationCode);

    private static AuditLogEntity CreateAudit(
        string sessionId,
        string rollNo,
        string action,
        string previousStatus,
        string newStatus,
        string actor,
        string reason) => new()
        {
            SessionId = sessionId,
            RollNo = rollNo,
            Action = action,
            PreviousStatus = previousStatus,
            NewStatus = newStatus,
            Actor = actor,
            Reason = reason,
            CreatedAtUtc = DateTime.UtcNow,
        };

    private static string CreateConfirmationCode(
        string email,
        string sessionId,
        string rollNo,
        DateTime checkinTime)
    {
        var payload = $"{email}|{sessionId}|{rollNo}|{checkinTime:O}";
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(payload));
        return Convert.ToHexString(hash)[..16];
    }

    private static string FormatCsvDateTime(DateTime? value)
    {
        return value?.ToLocalTime().ToString(
            "dd/MM/yyyy HH:mm:ss",
            CultureInfo.InvariantCulture) ?? string.Empty;
    }

    private static string EscapeCsv(string value)
    {
        if (value.IndexOfAny([',', '"', '\r', '\n']) < 0)
        {
            return value;
        }

        return $"\"{value.Replace("\"", "\"\"")}\"";
    }

    private static string ParseDate(string? value, DateTime fallback)
    {
        return DateTime.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.None, out var parsed)
            ? parsed.ToString("yyyy-MM-dd")
            : fallback.ToString("yyyy-MM-dd");
    }

    private static string CleanActor(string? actor) =>
        string.IsNullOrWhiteSpace(actor) ? "Giảng viên" : actor.Trim();

    private static DateTime AsUtc(DateTime value) =>
        DateTime.SpecifyKind(value, DateTimeKind.Utc);

    private static ServiceResult<T> Failure<T>(
        string message,
        int statusCode = StatusCodes.Status400BadRequest,
        string? code = null) =>
        new(false, message, default, statusCode, code);
}
