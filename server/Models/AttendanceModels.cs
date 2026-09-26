namespace Attendance.Api.Models;

public static class AttendanceStatuses
{
    public const string Present = "PRESENT";
    public const string Absent = "ABSENT";

    public static readonly HashSet<string> All =
        new(StringComparer.OrdinalIgnoreCase) { Present, Absent };

    // Keep existing Sheets usable after the app moves to a binary status model.
    public static string Normalize(string? status) =>
        status?.Trim().ToUpperInvariant() switch
        {
            Present or "LATE" => Present,
            _ => Absent,
        };
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
    IReadOnlyCollection<StudentSeed>? Students,
    int SessionNumber = 1,
    int TotalSessions = 20);

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

public sealed record AttendanceBatchChange(
    string? RollNo,
    string? Status,
    string? ExpectedStatus);

public sealed record SaveAttendanceBatchRequest(
    string? SessionId,
    string? ClassCode,
    string? SubjectCode,
    int Slot,
    string? Date,
    string? Actor,
    IReadOnlyCollection<AttendanceBatchChange>? Changes,
    int SessionNumber = 1,
    int TotalSessions = 20);

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
    int Absent,
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
    IReadOnlyCollection<DeviceBindingRecord> DeviceBindings,
    int SessionNumber = 0,
    int TotalSessions = 20);

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
