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

        var students = (request.Students ?? [])
            .Where(student => !string.IsNullOrWhiteSpace(student.RollNo))
            .DistinctBy(student => student.RollNo!.Trim(), StringComparer.OrdinalIgnoreCase);

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
        var entry = await dbContext.AttendanceEntries
            .AsNoTracking()
            .FirstOrDefaultAsync(
                item => item.SessionId == session.Id && item.RollNo == rollNo,
                cancellationToken);

        if (entry is not null && entry.CheckinTimeUtc.HasValue)
        {
            var duplicateSnapshot = await GetSnapshotAsync(session.Id, cancellationToken);
            return new ServiceResult<AttendanceSnapshot>(
                false,
                $"{rollNo} đã điểm danh lúc {entry.CheckinTimeUtc.Value.ToLocalTime():HH:mm:ss}.",
                duplicateSnapshot,
                StatusCodes.Status409Conflict);
        }

        var now = DateTime.UtcNow;
        var status = now > session.OpenedAtUtc.AddMinutes(session.LateAfterMinutes)
            ? AttendanceStatuses.Late
            : AttendanceStatuses.Present;
        var previousStatus = entry?.Status ?? string.Empty;
        var confirmationCode = CreateConfirmationCode(email, session.Id, rollNo, now);

        if (entry is null)
        {
            entry = new AttendanceEntryEntity
            {
                SessionId = session.Id,
                RollNo = rollNo,
                FullName = string.IsNullOrWhiteSpace(request.FullName) ? rollNo : request.FullName.Trim(),
                Email = email,
            };
            dbContext.AttendanceEntries.Add(entry);
        }
        else
        {
            var fullName = string.IsNullOrWhiteSpace(request.FullName)
                ? entry.FullName
                : request.FullName.Trim();
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

        var previousStatus = entry.Status;
        entry.Status = normalizedStatus;
        entry.CheckinTimeUtc = normalizedStatus is AttendanceStatuses.Present or AttendanceStatuses.Late
            ? entry.CheckinTimeUtc ?? DateTime.UtcNow
            : null;
        entry.UpdatedAtUtc = DateTime.UtcNow;
        entry.Notes = request.Reason?.Trim() ?? "Giảng viên cập nhật thủ công";

        dbContext.AuditLogs.Add(CreateAudit(
            sessionId,
            entry.RollNo,
            "MANUAL_UPDATE",
            previousStatus,
            normalizedStatus,
            CleanActor(request.Actor),
            entry.Notes));
        await dbContext.SaveChangesAsync(cancellationToken);

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
                .OrderByDescending(item => item.IsOpen)
                .ThenByDescending(item => item.OpenedAtUtc)
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
            records);
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
                EscapeCsv(student.CheckinTime?.ToString("O") ?? string.Empty),
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
        int statusCode = StatusCodes.Status400BadRequest) =>
        new(false, message, default, statusCode);
}
