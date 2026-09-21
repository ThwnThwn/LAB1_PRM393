using System.ComponentModel.DataAnnotations;

namespace Attendance.Api.Models;

public sealed class AttendanceSessionEntity
{
    [Key]
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string ClassCode { get; set; } = string.Empty;
    public string SubjectCode { get; set; } = string.Empty;
    public int Slot { get; set; }
    public string SessionDate { get; set; } = string.Empty;
    public bool IsOpen { get; set; }
    public int LateAfterMinutes { get; set; } = 10;
    public DateTime OpenedAtUtc { get; set; }
    public DateTime? ClosedAtUtc { get; set; }
    public string CreatedBy { get; set; } = "Giảng viên";
    public List<AttendanceEntryEntity> AttendanceEntries { get; set; } = [];
}

public sealed class AttendanceDeviceBindingEntity
{
    public long Id { get; set; }
    public string SessionId { get; set; } = string.Empty;
    public AttendanceSessionEntity? Session { get; set; }
    public string DeviceHash { get; set; } = string.Empty;
    public string RollNo { get; set; } = string.Empty;
    public DateTime FirstSeenUtc { get; set; }
    public DateTime LastSeenUtc { get; set; }
    public int BlockedAttempts { get; set; }
    public string LastBlockedRollNo { get; set; } = string.Empty;
    public DateTime? LastBlockedAtUtc { get; set; }
    public string NetworkHash { get; set; } = string.Empty;
    public string UserAgentHash { get; set; } = string.Empty;
}

public sealed class AttendanceEntryEntity
{
    public long Id { get; set; }
    public string SessionId { get; set; } = string.Empty;
    public AttendanceSessionEntity? Session { get; set; }
    public string RollNo { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string Status { get; set; } = AttendanceStatuses.NotChecked;
    public DateTime? CheckinTimeUtc { get; set; }
    public DateTime UpdatedAtUtc { get; set; }
    public string Notes { get; set; } = string.Empty;
    public string ConfirmationCode { get; set; } = string.Empty;
}

public sealed class ClassRosterStudentEntity
{
    public long Id { get; set; }
    public string ClassCode { get; set; } = string.Empty;
    public string RollNo { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public DateTime UpdatedAtUtc { get; set; }
}

public sealed class AuditLogEntity
{
    public long Id { get; set; }
    public string SessionId { get; set; } = string.Empty;
    public string RollNo { get; set; } = string.Empty;
    public string Action { get; set; } = string.Empty;
    public string PreviousStatus { get; set; } = string.Empty;
    public string NewStatus { get; set; } = string.Empty;
    public string Actor { get; set; } = string.Empty;
    public string Reason { get; set; } = string.Empty;
    public DateTime CreatedAtUtc { get; set; }
}

public static class AttendanceStatuses
{
    public const string NotChecked = "NOT CHECKED";
    public const string Present = "PRESENT";
    public const string Late = "LATE";
    public const string Absent = "ABSENT";

    public static readonly HashSet<string> All =
        new(StringComparer.OrdinalIgnoreCase) { NotChecked, Present, Late, Absent };
}

public sealed record StudentSeed(string? RollNo, string? FullName, string? Email);

public sealed record RosterSyncRequest(
    string? SessionId,
    string? Actor,
    IReadOnlyCollection<StudentSeed>? Students);

public sealed record RosterStudentRecord(
    string RollNo,
    string FullName,
    string Email);

public sealed record RosterSyncSnapshot(
    string Status,
    string ClassCode,
    int Count,
    IReadOnlyCollection<RosterStudentRecord> Students,
    AttendanceSnapshot? Session);

public sealed record OpenSessionRequest(
    string? ClassCode,
    string? SubjectCode,
    int Slot,
    string? Date,
    int LateAfterMinutes,
    string? Actor,
    IReadOnlyCollection<StudentSeed>? Students);

public sealed record StudentCheckinRequest(
    string? SessionId,
    string? Email,
    string? RollNo,
    string? FullName,
    string? ClassCode,
    string? SubjectCode,
    int Slot,
    string? Otp);

public sealed record UpdateAttendanceRequest(
    string? Status,
    string? Actor,
    string? Reason,
    string? ExpectedStatus = null);

public sealed record ReleaseDeviceRequest(string? Actor, string? Reason);

public sealed record GoogleSheetsConfigurationRequest(string? WebAppUrl);

public sealed record DeviceIdentity(
    string DeviceHash,
    string DeviceCode,
    string NetworkHash,
    string UserAgentHash);

public sealed record DeviceBindingRecord(
    long Id,
    string DeviceCode,
    string RollNo,
    DateTime FirstSeen,
    DateTime LastSeen,
    int BlockedAttempts,
    string LastBlockedRollNo,
    DateTime? LastBlockedAt);

public sealed record AttendanceRecord(
    string SessionId,
    string RollNo,
    string FullName,
    string Email,
    string ClassCode,
    string SubjectCode,
    int Slot,
    string Status,
    DateTime? CheckinTime,
    string Notes,
    string ConfirmationCode);

public sealed record DashboardStats(
    int Total,
    int Present,
    int Late,
    int Absent,
    int NotChecked,
    double AttendancePercentage);

public sealed record AttendanceSnapshot(
    string Status,
    string SessionId,
    string ClassCode,
    string SubjectCode,
    int Slot,
    string Date,
    bool IsOpen,
    DateTime OpenedAt,
    DateTime? ClosedAt,
    int LateAfterMinutes,
    bool OtpPaused,
    string? PausedOtp,
    int? OtpRemainingSeconds,
    int Count,
    DashboardStats Stats,
    IReadOnlyCollection<AttendanceRecord> Students,
    IReadOnlyCollection<DeviceBindingRecord> DeviceBindings);

public sealed record AuditLogRecord(
    long Id,
    string SessionId,
    string RollNo,
    string Action,
    string PreviousStatus,
    string NewStatus,
    string Actor,
    string Reason,
    DateTime CreatedAt);

public sealed record ServiceResult<T>(
    bool Success,
    string Message,
    T? Value,
    int StatusCode = StatusCodes.Status200OK,
    string? Code = null);
