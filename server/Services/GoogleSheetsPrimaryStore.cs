using System.Net.Http.Json;
using System.Net;
using System.Globalization;
using System.Text.Json;
using Attendance.Api.Models;

namespace Attendance.Api.Services;

public sealed record GoogleSheetsConfiguration(string WebAppUrl);

public sealed record GoogleSheetsStoreStatus(
    bool IsConfigured,
    bool IsReachable,
    string? WebAppUrl,
    string DatabaseMode,
    string Message);

public sealed record GoogleSheetsWriteResult(
    bool Success,
    string Message,
    JsonElement? Payload = null);

public sealed record StoredDeviceBinding(
    long Id,
    string DeviceHash,
    string DeviceCode,
    string RollNo,
    DateTime FirstSeen,
    DateTime LastSeen,
    int BlockedAttempts,
    string LastBlockedRollNo,
    DateTime? LastBlockedAt,
    string NetworkHash,
    string UserAgentHash);

public sealed record StoredAttendanceSession(
    AttendanceSnapshot Snapshot,
    IReadOnlyCollection<AuditLogRecord> AuditLogs,
    IReadOnlyCollection<StoredDeviceBinding> DeviceBindings);

public sealed class GoogleSheetsPrimaryStore
{
    private const string LegacyScriptMessage =
        "Apps Script đang là bản cũ (cần phiên bản 7). Mở desktop app → Cấu hình Google Sheets, " +
        "sao chép lại mã Apps Script rồi chọn Deploy → Manage deployments → Edit → New version → Deploy.";

    private sealed record DemoClassDefinition(string ClassCode, string SubjectCode);

    private sealed record DemoScheduleDefinition(
        string SessionId,
        string ClassCode,
        string SubjectCode,
        int Slot,
        DateTime Date,
        int StartHour,
        int StartMinute,
        bool Completed,
        int SessionNumber,
        int TotalSessions = 20);

    private static readonly DemoClassDefinition[] DemoClasses =
    [
        new("SE1917", "PRN232"),
        new("SE1918", "PRM393"),
        new("SE1919", "EXE201"),
        new("SE1920", "HCM202"),
    ];

    private static readonly DemoScheduleDefinition[] DemoSchedule =
    [
        new("DEMO-20260914-SE1918-PRM393-S2", "SE1918", "PRM393", 2, new DateTime(2026, 9, 14), 9, 30, true, 1),
        new("DEMO-20260917-SE1918-PRM393-S2", "SE1918", "PRM393", 2, new DateTime(2026, 9, 17), 9, 30, true, 2),
        new("DEMO-SE1917-PRN232", "SE1917", "PRN232", 1, new DateTime(2026, 9, 21), 7, 0, true, 3),
        new("DEMO-SE1918-PRM393", "SE1918", "PRM393", 2, new DateTime(2026, 9, 21), 9, 30, true, 3),
        new("DEMO-SE1920-HCM202", "SE1920", "HCM202", 1, new DateTime(2026, 9, 22), 7, 0, true, 5),
        new("DEMO-SE1919-EXE201", "SE1919", "EXE201", 2, new DateTime(2026, 9, 23), 9, 30, false, 5),
        new("DEMO-20260924-SE1917-PRN232-S1", "SE1917", "PRN232", 1, new DateTime(2026, 9, 24), 7, 0, false, 4),
        new("DEMO-20260924-SE1918-PRM393-S2", "SE1918", "PRM393", 2, new DateTime(2026, 9, 24), 9, 30, true, 4),
        // Keep the existing opaque ID so previously shared FAP links continue to resolve.
        new("DEMO-20260924-SE1920-HCM202-S4", "SE1920", "HCM202", 1, new DateTime(2026, 9, 25), 7, 0, false, 6),
    ];

    private static readonly string[] DemoStudentNames =
    [
        "Nguyễn Minh Anh", "Trần Gia Huy", "Lê Hoàng Yến", "Phạm Khánh Linh",
        "Võ Quốc Bảo", "Đỗ Thu Trang", "Bùi Nhật Minh", "Nguyễn Mai Hào Tiến",
        "Phan Thị Thảo Vy", "Chu Vương Mạnh", "Nguyễn Hoàng Nam", "Trương Quỳnh Như",
        "Lý Gia Bảo", "Huỳnh Ngọc Hân", "Đặng Minh Quân", "Hồ Nhật Linh",
        "Phan Tuấn Kiệt", "Vũ Thảo Nguyên", "Nguyễn Đức Anh", "Trần Khánh Vy",
        "Lê Quốc Trung", "Phạm Ngọc Mai", "Võ Minh Khang", "Đỗ Hà My",
        "Bùi Anh Tuấn", "Nguyễn Thanh Trúc", "Trần Gia Minh", "Lê Thu Hương",
        "Phạm Đức Long", "Võ Hoài An", "Đặng Quốc Khánh", "Hồ Ngọc Diệp",
        "Phan Minh Triết", "Vũ Khánh An", "Nguyễn Hải Đăng",
    ];

    private readonly IHttpClientFactory httpClientFactory;
    private readonly ILogger<GoogleSheetsPrimaryStore> logger;
    private readonly string configurationPath;
    private readonly SemaphoreSlim configurationLock = new(1, 1);
    private string? webAppUrl;

    public GoogleSheetsPrimaryStore(
        IHttpClientFactory httpClientFactory,
        IWebHostEnvironment environment,
        ILogger<GoogleSheetsPrimaryStore> logger)
    {
        this.httpClientFactory = httpClientFactory;
        this.logger = logger;
        var dataDirectory = Path.Combine(environment.ContentRootPath, "App_Data");
        Directory.CreateDirectory(dataDirectory);
        configurationPath = Path.Combine(dataDirectory, "google-sheets.json");
        webAppUrl = ReadSavedUrl();
    }

    public bool IsConfigured => !string.IsNullOrWhiteSpace(webAppUrl);

    public string? WebAppUrl => webAppUrl;

    public async Task<GoogleSheetsStoreStatus> GetStatusAsync(
        bool verifyConnection,
        CancellationToken cancellationToken)
    {
        if (!IsConfigured)
        {
            return new GoogleSheetsStoreStatus(
                false,
                false,
                null,
                "GOOGLE_SHEETS_PRIMARY",
                "Chưa cấu hình Google Apps Script Web App URL.");
        }

        if (!verifyConnection)
        {
            return new GoogleSheetsStoreStatus(
                true,
                false,
                webAppUrl,
                "GOOGLE_SHEETS_PRIMARY",
                "Đã lưu cấu hình Google Sheets.");
        }

        var health = await TestConnectionAsync(webAppUrl!, cancellationToken);
        return new GoogleSheetsStoreStatus(
            true,
            health.Success,
            webAppUrl,
            "GOOGLE_SHEETS_PRIMARY",
            health.Message);
    }

    public async Task<GoogleSheetsStoreStatus> ConfigureAsync(
        string? url,
        CancellationToken cancellationToken)
    {
        var normalizedUrl = url?.Trim() ?? string.Empty;
        if (!IsAllowedAppsScriptUrl(normalizedUrl))
        {
            return new GoogleSheetsStoreStatus(
                false,
                false,
                null,
                "GOOGLE_SHEETS_PRIMARY",
                "URL phải là Google Apps Script Web App HTTPS và kết thúc bằng /exec.");
        }

        var health = await TestConnectionAsync(normalizedUrl, cancellationToken);
        if (!health.Success)
        {
            return new GoogleSheetsStoreStatus(
                false,
                false,
                null,
                "GOOGLE_SHEETS_PRIMARY",
                health.Message);
        }

        await configurationLock.WaitAsync(cancellationToken);
        try
        {
            var json = JsonSerializer.Serialize(
                new GoogleSheetsConfiguration(normalizedUrl),
                new JsonSerializerOptions { WriteIndented = true });
            await File.WriteAllTextAsync(configurationPath, json, cancellationToken);
            webAppUrl = normalizedUrl;
        }
        finally
        {
            configurationLock.Release();
        }

        return new GoogleSheetsStoreStatus(
            true,
            true,
            normalizedUrl,
            "GOOGLE_SHEETS_PRIMARY",
            "Google Sheets đã được cấu hình làm database chính.");
    }

    public async Task<(GoogleSheetsWriteResult Result, IReadOnlyCollection<RosterStudentRecord> Students)>
        GetRosterAsync(string classCode, CancellationToken cancellationToken)
    {
        if (!IsConfigured)
        {
            return (NotConfigured(), []);
        }

        try
        {
            var requestUrl = AddQuery(webAppUrl!, new Dictionary<string, string>
            {
                ["action"] = "getRoster",
                ["classCode"] = classCode.Trim().ToUpperInvariant(),
            });
            using var response = await GetWithRetryAsync(requestUrl, cancellationToken);
            var payload = await ReadPayloadAsync(response, cancellationToken);
            if (!response.IsSuccessStatusCode || !IsSuccess(payload))
            {
                return (FailureMessage(payload, response), []);
            }

            if (!payload.TryGetProperty("students", out var studentsElement) ||
                studentsElement.ValueKind != JsonValueKind.Array)
            {
                return (new GoogleSheetsWriteResult(true, "Google Sheet chưa có roster cho lớp này."), []);
            }

            var students = studentsElement.EnumerateArray()
                .Select(item => new RosterStudentRecord(
                    ReadString(item, "rollNo").Trim().ToUpperInvariant(),
                    ReadString(item, "fullName").Trim(),
                    ReadString(item, "email").Trim().ToLowerInvariant()))
                .Where(item => item.RollNo.Length > 0)
                .OrderBy(item => item.RollNo)
                .ToArray();
            return (new GoogleSheetsWriteResult(true, "Đã đọc roster từ Google Sheets."), students);
        }
        catch (Exception exception)
        {
            logger.LogWarning(exception, "Cannot read roster from Google Sheets.");
            return (new GoogleSheetsWriteResult(false, $"Không thể đọc Google Sheets: {exception.Message}"), []);
        }
    }

    public async Task<(GoogleSheetsWriteResult Result, StoredAttendanceSession? Session)>
        GetSessionAsync(string? sessionId, CancellationToken cancellationToken)
    {
        if (!IsConfigured)
        {
            return (NotConfigured(), null);
        }

        try
        {
            var query = new Dictionary<string, string> { ["action"] = "getAttendance" };
            if (!string.IsNullOrWhiteSpace(sessionId))
            {
                query["sessionId"] = sessionId.Trim();
            }
            var requestUrl = AddQuery(webAppUrl!, query);
            using var response = await GetWithRetryAsync(requestUrl, cancellationToken);
            var payload = await ReadPayloadAsync(response, cancellationToken);
            if (!response.IsSuccessStatusCode || !IsSuccess(payload))
            {
                return (FailureMessage(payload, response), null);
            }
            if (payload.TryGetProperty("sessionId", out var idElement) &&
                idElement.ValueKind != JsonValueKind.Null &&
                !payload.TryGetProperty("classCode", out _))
            {
                return (
                    new GoogleSheetsWriteResult(
                        false,
                        LegacyScriptMessage),
                    null);
            }

            return (
                new GoogleSheetsWriteResult(true, "Đã đọc phiên điểm danh từ Google Sheets."),
                ParseStoredSession(payload));
        }
        catch (Exception exception)
        {
            logger.LogWarning(exception, "Cannot read attendance session from Google Sheets.");
            return (new GoogleSheetsWriteResult(false, $"Không thể đọc Google Sheets: {exception.Message}"), null);
        }
    }

    public async Task<(GoogleSheetsWriteResult Result, IReadOnlyCollection<StoredAttendanceSession> Sessions)>
        GetSessionsAsync(
            int limit,
            CancellationToken cancellationToken,
            string? classCode = null,
            string? subjectCode = null,
            int? slot = null)
    {
        if (!IsConfigured)
        {
            return (NotConfigured(), []);
        }

        try
        {
            var query = new Dictionary<string, string>
            {
                ["action"] = "getSessions",
                ["limit"] = Math.Clamp(limit, 1, 100).ToString(CultureInfo.InvariantCulture),
            };
            if (!string.IsNullOrWhiteSpace(classCode)) query["classCode"] = classCode.Trim().ToUpperInvariant();
            if (!string.IsNullOrWhiteSpace(subjectCode)) query["subjectCode"] = subjectCode.Trim().ToUpperInvariant();
            if (slot is > 0) query["slot"] = slot.Value.ToString(CultureInfo.InvariantCulture);
            var requestUrl = AddQuery(webAppUrl!, query);
            using var response = await GetWithRetryAsync(requestUrl, cancellationToken);
            var payload = await ReadPayloadAsync(response, cancellationToken);
            if (!response.IsSuccessStatusCode || !IsSuccess(payload))
            {
                return (FailureMessage(payload, response), []);
            }

            var sessions = payload.TryGetProperty("sessions", out var sessionsElement) &&
                           sessionsElement.ValueKind == JsonValueKind.Array
                ? sessionsElement.EnumerateArray()
                    .Select(ParseStoredSession)
                    .Where(session => session is not null)
                    .Cast<StoredAttendanceSession>()
                    .ToArray()
                : [];
            return (new GoogleSheetsWriteResult(true, "Đã đọc danh sách phiên từ Google Sheets."), sessions);
        }
        catch (Exception exception)
        {
            logger.LogWarning(exception, "Cannot read attendance sessions from Google Sheets.");
            return (new GoogleSheetsWriteResult(false, $"Không thể đọc Google Sheets: {exception.Message}"), []);
        }
    }

    public Task<GoogleSheetsWriteResult> SyncRosterAsync(
        string classCode,
        IReadOnlyCollection<RosterStudentRecord> students,
        CancellationToken cancellationToken) =>
        PostAsync(new
        {
            action = "syncRoster",
            classCode = classCode.Trim().ToUpperInvariant(),
            updatedAt = DateTime.UtcNow,
            students,
        }, cancellationToken);

    public Task<GoogleSheetsWriteResult> SyncCourseMeetingsAsync(
        IReadOnlyCollection<CourseMeetingPlanItem> meetings,
        CancellationToken cancellationToken) =>
        PostAsync(new
        {
            action = "syncCourseMeetings",
            updatedAt = DateTime.UtcNow,
            meetings = meetings.Select(item => new
            {
                classCode = item.ClassCode?.Trim().ToUpperInvariant() ?? string.Empty,
                subjectCode = item.SubjectCode?.Trim().ToUpperInvariant() ?? string.Empty,
                meetingNumber = item.MeetingNumber,
                totalMeetings = item.TotalMeetings,
                date = item.Date?.Trim() ?? string.Empty,
                slot = item.Slot,
            }),
        }, cancellationToken);

    public Task<GoogleSheetsWriteResult> NormalizeDuplicateSessionsAsync(
        CancellationToken cancellationToken) =>
        PostAsync(new
        {
            action = "normalizeDuplicateSessions",
            requestedAt = DateTime.UtcNow,
        }, cancellationToken);

    public Task<GoogleSheetsWriteResult> SaveSessionAsync(
        StoredAttendanceSession storedSession,
        CancellationToken cancellationToken) =>
        PostAsync(new
        {
            action = "syncSession",
            session = new
            {
                storedSession.Snapshot.Status,
                storedSession.Snapshot.SessionId,
                storedSession.Snapshot.ClassCode,
                storedSession.Snapshot.SubjectCode,
                storedSession.Snapshot.Slot,
                storedSession.Snapshot.Date,
                storedSession.Snapshot.IsOpen,
                storedSession.Snapshot.OpenedAt,
                storedSession.Snapshot.ClosedAt,
                storedSession.Snapshot.LateAfterMinutes,
                storedSession.Snapshot.OtpPaused,
                storedSession.Snapshot.SessionNumber,
                storedSession.Snapshot.TotalSessions,
                storedSession.Snapshot.Students,
                deviceBindings = storedSession.DeviceBindings,
            },
            auditLogs = storedSession.AuditLogs,
            syncedAt = DateTime.UtcNow,
        }, cancellationToken);

    public async Task<GoogleSheetsWriteResult> SeedDemoAsync(
        CancellationToken cancellationToken)
    {
        var initialSeed = await PostAsync(new
        {
            action = "seedDemo",
            seededAt = DateTime.UtcNow,
        }, cancellationToken);
        if (!initialSeed.Success) return initialSeed;

        var roster = DemoStudentNames.Select((name, index) =>
        {
            var rollNo = $"SE{191701 + index}";
            return new RosterStudentRecord(rollNo, name, $"{rollNo.ToLowerInvariant()}@fpt.edu.vn");
        }).ToArray();

        foreach (var demoClass in DemoClasses)
        {
            var rosterResult = await SyncRosterAsync(demoClass.ClassCode, roster, cancellationToken);
            if (!rosterResult.Success) return rosterResult;
        }

        for (var scheduleIndex = 0; scheduleIndex < DemoSchedule.Length; scheduleIndex++)
        {
            var schedule = DemoSchedule[scheduleIndex];
            var openedAt = new DateTimeOffset(
                schedule.Date.Year,
                schedule.Date.Month,
                schedule.Date.Day,
                schedule.StartHour,
                schedule.StartMinute,
                0,
                TimeSpan.FromHours(7)).UtcDateTime;
            DateTime? closedAt = schedule.Completed ? openedAt.AddMinutes(135) : null;
            var students = roster.Select((student, index) =>
            {
                var isAttendanceRiskDemo =
                    schedule.ClassCode == "SE1918" &&
                    schedule.SubjectCode == "PRM393" &&
                    schedule.SessionNumber <= 4 &&
                    index == 0;
                var isSingleSessionDemoAbsence =
                    schedule.ClassCode == "SE1918"
                        ? (schedule.SessionNumber == 3 && index == 6) ||
                          (schedule.SessionNumber == 4 && index == 18)
                        : index is 6 or 18;
                var status = schedule.Completed &&
                             !isAttendanceRiskDemo &&
                             !isSingleSessionDemoAbsence
                    ? AttendanceStatuses.Present
                    : AttendanceStatuses.Absent;

                var checkinTime = status == AttendanceStatuses.Present
                    ? openedAt.AddMinutes(2 + index % 12)
                    : (DateTime?)null;
                return new AttendanceRecord(
                    schedule.SessionId,
                    student.RollNo,
                    student.FullName,
                    student.Email,
                    schedule.ClassCode,
                    schedule.SubjectCode,
                    schedule.Slot,
                    status,
                    checkinTime,
                    status == AttendanceStatuses.Absent ? "Vắng có phép (demo)" : string.Empty,
                    $"DEMO{index + 1:00}");
            }).ToArray();
            var present = students.Count(student => student.Status == AttendanceStatuses.Present);
            var absent = students.Count(student => student.Status == AttendanceStatuses.Absent);
            var stats = new DashboardStats(
                students.Length,
                present,
                absent,
                students.Length == 0 ? 0 : present * 100.0 / students.Length);
            var snapshot = new AttendanceSnapshot(
                "success",
                schedule.SessionId,
                schedule.ClassCode,
                schedule.SubjectCode,
                schedule.Slot,
                schedule.Date.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
                false,
                openedAt,
                closedAt,
                10,
                false,
                null,
                null,
                students.Length,
                stats,
                students,
                [],
                schedule.SessionNumber,
                schedule.TotalSessions);
            var auditLogs = new[]
            {
                new AuditLogRecord(
                    2000 + scheduleIndex,
                    schedule.SessionId,
                    string.Empty,
                    "DEMO_SEEDED",
                    string.Empty,
                    string.Empty,
                    "Giảng viên demo",
                    "Seed lịch tuần 21/09–27/09/2026",
                    openedAt),
            };
            var sessionResult = await SaveSessionAsync(
                new StoredAttendanceSession(snapshot, auditLogs, []),
                cancellationToken);
            if (!sessionResult.Success) return sessionResult;
        }

        return new GoogleSheetsWriteResult(
            true,
            "Đã seed 7 ca trong tuần, 2 phiên lịch sử và một sinh viên vắng 4/20 buổi vào Google Sheets.");
    }

    private async Task<GoogleSheetsWriteResult> PostAsync(
        object payload,
        CancellationToken cancellationToken)
    {
        if (!IsConfigured)
        {
            return NotConfigured();
        }

        try
        {
            using var response = await CreateClient().PostAsJsonAsync(
                webAppUrl,
                payload,
                cancellationToken);
            var body = await ReadPayloadAsync(response, cancellationToken);
            if (!response.IsSuccessStatusCode || !IsSuccess(body))
            {
                return FailureMessage(body, response);
            }

            var message = body.TryGetProperty("message", out var messageElement)
                ? messageElement.ToString()
                : "Đã ghi dữ liệu vào Google Sheets.";
            return new GoogleSheetsWriteResult(true, message, body);
        }
        catch (Exception exception)
        {
            logger.LogWarning(exception, "Cannot write primary data to Google Sheets.");
            return new GoogleSheetsWriteResult(
                false,
                $"Không thể ghi database Google Sheets: {exception.Message}");
        }
    }

    private async Task<GoogleSheetsWriteResult> TestConnectionAsync(
        string url,
        CancellationToken cancellationToken)
    {
        try
        {
            using var response = await GetWithRetryAsync(
                AddQuery(url, new Dictionary<string, string> { ["action"] = "health" }),
                cancellationToken);
            var payload = await ReadPayloadAsync(response, cancellationToken);
            if (!response.IsSuccessStatusCode || !IsSuccess(payload))
            {
                return FailureMessage(payload, response);
            }

            if (ReadInt(payload, "version") < 7)
            {
                return new GoogleSheetsWriteResult(
                    false,
                    LegacyScriptMessage);
            }

            return new GoogleSheetsWriteResult(true, "Kết nối Google Sheets thành công.");
        }
        catch (Exception exception)
        {
            logger.LogWarning(exception, "Cannot verify Google Apps Script URL.");
            return new GoogleSheetsWriteResult(false, $"Không thể kết nối Google Sheets: {exception.Message}");
        }
    }

    private HttpClient CreateClient()
    {
        var client = httpClientFactory.CreateClient(nameof(GoogleSheetsPrimaryStore));
        // Apps Script can queue requests briefly while a Sheet write is in progress.
        client.Timeout = TimeSpan.FromSeconds(90);
        return client;
    }

    private async Task<HttpResponseMessage> GetWithRetryAsync(
        string requestUrl,
        CancellationToken cancellationToken)
    {
        var client = CreateClient();
        for (var attempt = 0; ; attempt++)
        {
            var response = await client.GetAsync(requestUrl, cancellationToken);
            var isHtml = response.Content.Headers.ContentType?.MediaType?
                .Equals("text/html", StringComparison.OrdinalIgnoreCase) == true;
            if (attempt == 0 && (response.StatusCode == HttpStatusCode.NotFound || isHtml))
            {
                // Google occasionally returns its HTML 404 page for a valid Apps Script
                // deployment. Retry a read once; never replay a write.
                response.Dispose();
                await Task.Delay(750, cancellationToken);
                continue;
            }

            return response;
        }
    }

    private string? ReadSavedUrl()
    {
        try
        {
            if (!File.Exists(configurationPath)) return null;
            var content = File.ReadAllText(configurationPath);
            return JsonSerializer.Deserialize<GoogleSheetsConfiguration>(
                content,
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true })?.WebAppUrl;
        }
        catch (Exception exception)
        {
            logger.LogWarning(exception, "Cannot read Google Sheets configuration.");
            return null;
        }
    }

    private static bool IsAllowedAppsScriptUrl(string value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri)) return false;
        return uri.Scheme == Uri.UriSchemeHttps &&
               uri.Host.Equals("script.google.com", StringComparison.OrdinalIgnoreCase) &&
               uri.AbsolutePath.StartsWith("/macros/s/", StringComparison.OrdinalIgnoreCase) &&
               uri.AbsolutePath.EndsWith("/exec", StringComparison.OrdinalIgnoreCase);
    }

    private static string AddQuery(string url, IReadOnlyDictionary<string, string> values)
    {
        var builder = new UriBuilder(url);
        var pairs = builder.Query.TrimStart('?')
            .Split('&', StringSplitOptions.RemoveEmptyEntries)
            .ToList();
        pairs.AddRange(values.Select(item =>
            $"{Uri.EscapeDataString(item.Key)}={Uri.EscapeDataString(item.Value)}"));
        builder.Query = string.Join('&', pairs);
        return builder.Uri.ToString();
    }

    private static async Task<JsonElement> ReadPayloadAsync(
        HttpResponseMessage response,
        CancellationToken cancellationToken)
    {
        var content = await response.Content.ReadAsStringAsync(cancellationToken);
        if (string.IsNullOrWhiteSpace(content))
        {
            return JsonDocument.Parse("{}").RootElement.Clone();
        }

        try
        {
            return JsonDocument.Parse(content).RootElement.Clone();
        }
        catch (JsonException exception)
        {
            var status = (int)response.StatusCode;
            var contentType = response.Content.Headers.ContentType?.MediaType ?? "không rõ";
            throw new InvalidDataException(
                $"Google Apps Script trả về HTTP {status} ({contentType}) thay vì JSON. " +
                "Kiểm tra URL /exec và bản triển khai Web App (quyền truy cập: Anyone); " +
                "nếu vẫn lỗi, cập nhật mã Apps Script và triển khai New version.",
                exception);
        }
    }

    private static bool IsSuccess(JsonElement payload) =>
        payload.TryGetProperty("status", out var status) &&
        status.GetString()?.Equals("success", StringComparison.OrdinalIgnoreCase) == true;

    private static GoogleSheetsWriteResult FailureMessage(
        JsonElement payload,
        HttpResponseMessage response)
    {
        var message = payload.TryGetProperty("error", out var error)
            ? error.GetString()
            : null;
        message ??= payload.TryGetProperty("message", out var detail)
            ? detail.GetString()
            : null;
        if (message?.Equals("Unsupported action", StringComparison.OrdinalIgnoreCase) == true)
        {
            message = LegacyScriptMessage;
        }
        message ??= $"Google Apps Script trả về HTTP {(int)response.StatusCode}.";
        return new GoogleSheetsWriteResult(false, message);
    }

    private static string ReadString(JsonElement item, string propertyName) =>
        item.TryGetProperty(propertyName, out var property)
            ? property.ToString()
            : string.Empty;

    private static StoredAttendanceSession? ParseStoredSession(JsonElement payload)
    {
        var sessionId = ReadString(payload, "sessionId").Trim();
        if (sessionId.Length == 0)
        {
            return null;
        }

        var classCode = ReadString(payload, "classCode").Trim().ToUpperInvariant();
        var subjectCode = ReadString(payload, "subjectCode").Trim().ToUpperInvariant();
        var slot = ReadInt(payload, "slot");
        var sessionNumber = ReadInt(payload, "sessionNumber");
        var totalSessions = Math.Max(sessionNumber, ReadInt(payload, "totalSessions", 20));
        var studentsElement = payload.TryGetProperty("students", out var studentArray) &&
                              studentArray.ValueKind == JsonValueKind.Array
            ? studentArray
            : default;
        var students = studentsElement.ValueKind == JsonValueKind.Array
            ? studentsElement.EnumerateArray().Select(item =>
            {
                var studentClass = ReadString(item, "classCode").Trim().ToUpperInvariant();
                if (studentClass.Length == 0) studentClass = ReadString(item, "group").Trim().ToUpperInvariant();
                if (studentClass.Length == 0) studentClass = classCode;
                var studentSubject = ReadString(item, "subjectCode").Trim().ToUpperInvariant();
                if (studentSubject.Length == 0) studentSubject = subjectCode;
                var studentSlot = ReadInt(item, "slot");
                if (studentSlot == 0) studentSlot = slot;
                return new AttendanceRecord(
                    sessionId,
                    ReadString(item, "rollNo").Trim().ToUpperInvariant(),
                    ReadString(item, "fullName").Trim(),
                    ReadString(item, "email").Trim().ToLowerInvariant(),
                    studentClass,
                    studentSubject,
                    studentSlot,
                    NormalizeStatus(ReadString(item, "status")),
                    ReadNullableDateTime(item, "checkinTime"),
                    ReadString(item, "notes"),
                    ReadString(item, "confirmationCode"));
            }).Where(student => student.RollNo.Length > 0).ToArray()
            : [];

        if (classCode.Length == 0) classCode = students.FirstOrDefault()?.ClassCode ?? string.Empty;
        if (subjectCode.Length == 0) subjectCode = students.FirstOrDefault()?.SubjectCode ?? string.Empty;
        if (slot == 0) slot = students.FirstOrDefault()?.Slot ?? 0;

        var bindings = payload.TryGetProperty("deviceBindings", out var bindingArray) &&
                       bindingArray.ValueKind == JsonValueKind.Array
            ? bindingArray.EnumerateArray().Select(item => new StoredDeviceBinding(
                ReadLong(item, "id"),
                ReadString(item, "deviceHash"),
                ReadString(item, "deviceCode"),
                ReadString(item, "rollNo").Trim().ToUpperInvariant(),
                ReadDateTime(item, "firstSeen", DateTime.UtcNow),
                ReadDateTime(item, "lastSeen", DateTime.UtcNow),
                ReadInt(item, "blockedAttempts"),
                ReadString(item, "lastBlockedRollNo").Trim().ToUpperInvariant(),
                ReadNullableDateTime(item, "lastBlockedAt"),
                ReadString(item, "networkHash"),
                ReadString(item, "userAgentHash"))).ToArray()
            : [];

        var auditLogs = payload.TryGetProperty("auditLogs", out var auditArray) &&
                        auditArray.ValueKind == JsonValueKind.Array
            ? auditArray.EnumerateArray().Select(item => new AuditLogRecord(
                ReadLong(item, "id"),
                sessionId,
                ReadString(item, "rollNo").Trim().ToUpperInvariant(),
                ReadString(item, "action"),
                ReadString(item, "previousStatus"),
                ReadString(item, "newStatus"),
                ReadString(item, "actor"),
                ReadString(item, "reason"),
                ReadDateTime(item, "createdAt", DateTime.UtcNow))).ToArray()
            : [];

        var present = students.Count(student => student.Status == AttendanceStatuses.Present);
        var absent = students.Count(student => student.Status == AttendanceStatuses.Absent);
        var stats = new DashboardStats(
            students.Length,
            present,
            absent,
            students.Length == 0 ? 0 : present * 100.0 / students.Length);
        var publicBindings = bindings.Select(binding => new DeviceBindingRecord(
            binding.Id,
            binding.DeviceCode,
            binding.RollNo,
            binding.FirstSeen,
            binding.LastSeen,
            binding.BlockedAttempts,
            binding.LastBlockedRollNo,
            binding.LastBlockedAt)).ToArray();
        var openedAt = ReadDateTime(payload, "openedAt", DateTime.UtcNow);
        var snapshot = new AttendanceSnapshot(
            "success",
            sessionId,
            classCode,
            subjectCode,
            slot,
            ReadString(payload, "date"),
            ReadBool(payload, "isOpen"),
            openedAt,
            ReadNullableDateTime(payload, "closedAt"),
            Math.Max(1, ReadInt(payload, "lateAfterMinutes", 10)),
            ReadBool(payload, "otpPaused"),
            null,
            null,
            students.Length,
            stats,
            students,
            publicBindings,
            sessionNumber,
            totalSessions);
        return new StoredAttendanceSession(snapshot, auditLogs, bindings);
    }

    private static string NormalizeStatus(string value)
    {
        return AttendanceStatuses.Normalize(value);
    }

    private static bool ReadBool(JsonElement item, string propertyName)
    {
        if (!item.TryGetProperty(propertyName, out var property)) return false;
        return property.ValueKind == JsonValueKind.True ||
               (property.ValueKind == JsonValueKind.String && bool.TryParse(property.GetString(), out var parsed) && parsed);
    }

    private static int ReadInt(JsonElement item, string propertyName, int fallback = 0) =>
        item.TryGetProperty(propertyName, out var property) &&
        int.TryParse(property.ToString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var value)
            ? value
            : fallback;

    private static long ReadLong(JsonElement item, string propertyName) =>
        item.TryGetProperty(propertyName, out var property) &&
        long.TryParse(property.ToString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var value)
            ? value
            : 0;

    private static DateTime ReadDateTime(JsonElement item, string propertyName, DateTime fallback) =>
        ReadNullableDateTime(item, propertyName) ?? fallback;

    private static DateTime? ReadNullableDateTime(JsonElement item, string propertyName)
    {
        var value = ReadString(item, propertyName);
        return DateTime.TryParse(
            value,
            CultureInfo.InvariantCulture,
            DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
            out var parsed)
            ? parsed
            : null;
    }

    private static GoogleSheetsWriteResult NotConfigured() =>
        new(false, "Hãy cấu hình Google Apps Script Web App URL trước khi sử dụng.");
}
