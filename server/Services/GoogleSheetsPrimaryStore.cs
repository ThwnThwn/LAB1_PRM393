using System.Net.Http.Json;
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

public sealed record GoogleSheetsWriteResult(bool Success, string Message);

public sealed class GoogleSheetsPrimaryStore
{
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
            using var response = await CreateClient().GetAsync(requestUrl, cancellationToken);
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

    public Task<GoogleSheetsWriteResult> SyncSessionAsync(
        AttendanceSnapshot snapshot,
        IReadOnlyCollection<AuditLogRecord> auditLogs,
        CancellationToken cancellationToken) =>
        PostAsync(new
        {
            action = "syncSession",
            session = snapshot,
            auditLogs,
            syncedAt = DateTime.UtcNow,
        }, cancellationToken);

    public Task<GoogleSheetsWriteResult> SeedDemoAsync(
        CancellationToken cancellationToken) =>
        PostAsync(new
        {
            action = "seedDemo",
            seededAt = DateTime.UtcNow,
        }, cancellationToken);

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

            return new GoogleSheetsWriteResult(true, "Đã ghi dữ liệu vào Google Sheets.");
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
            using var response = await CreateClient().GetAsync(
                AddQuery(url, new Dictionary<string, string> { ["action"] = "health" }),
                cancellationToken);
            var payload = await ReadPayloadAsync(response, cancellationToken);
            if (!response.IsSuccessStatusCode || !IsSuccess(payload))
            {
                return FailureMessage(payload, response);
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
        client.Timeout = TimeSpan.FromSeconds(15);
        return client;
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

        return JsonDocument.Parse(content).RootElement.Clone();
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
        message ??= $"Google Apps Script trả về HTTP {(int)response.StatusCode}.";
        return new GoogleSheetsWriteResult(false, message);
    }

    private static string ReadString(JsonElement item, string propertyName) =>
        item.TryGetProperty(propertyName, out var property)
            ? property.ToString()
            : string.Empty;

    private static GoogleSheetsWriteResult NotConfigured() =>
        new(false, "Hãy cấu hình Google Apps Script Web App URL trước khi sử dụng.");
}
