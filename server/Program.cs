using System.Net.Mail;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using Attendance.Api.Data;
using Attendance.Api.Hubs;
using Attendance.Api.Models;
using Attendance.Api.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.FileProviders;
using Microsoft.AspNetCore.HttpOverrides;

var builder = WebApplication.CreateBuilder(args);

builder.WebHost.UseUrls(builder.Configuration["Urls"] ?? "http://0.0.0.0:8080");

var repositoryRoot = Path.GetFullPath(Path.Combine(builder.Environment.ContentRootPath, ".."));
var dataDirectory = Path.Combine(builder.Environment.ContentRootPath, "App_Data");
Directory.CreateDirectory(dataDirectory);
var databasePath = Path.Combine(dataDirectory, "attendance.db");

builder.Services.AddDbContext<AttendanceDbContext>(options =>
    options.UseSqlite($"Data Source={databasePath}"));
builder.Services.AddScoped<AttendanceService>();
builder.Services.AddHttpClient(nameof(GoogleSheetsPrimaryStore));
builder.Services.AddSingleton<GoogleSheetsPrimaryStore>();
builder.Services.AddSingleton<OtpService>();
builder.Services.AddSingleton<DeviceIdentityService>();
builder.Services.AddSignalR();
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders =
        ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    options.KnownProxies.Add(IPAddress.Loopback);
    options.KnownProxies.Add(IPAddress.IPv6Loopback);
});
builder.Services.ConfigureHttpJsonOptions(options =>
    options.SerializerOptions.PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase);
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy => policy
        .AllowAnyOrigin()
        .AllowAnyHeader()
        .AllowAnyMethod());
});

var app = builder.Build();
app.UseForwardedHeaders();
app.UseCors();

var publicTunnelEnabled = string.Equals(
    Environment.GetEnvironmentVariable("ATTENDANCE_PUBLIC_TUNNEL"),
    "true",
    StringComparison.OrdinalIgnoreCase);
var teacherToken = Environment.GetEnvironmentVariable("ATTENDANCE_TEACHER_TOKEN")?.Trim() ?? string.Empty;
const string teacherAccessCookie = "FapAttendanceTeacher";

if (publicTunnelEnabled && teacherToken.Length < 32)
{
    throw new InvalidOperationException(
        "ATTENDANCE_TEACHER_TOKEN phải có ít nhất 32 ký tự khi bật public tunnel.");
}

app.Use(async (context, next) =>
{
    if (!publicTunnelEnabled ||
        HttpMethods.IsOptions(context.Request.Method) ||
        IsLoopback(context.Connection.RemoteIpAddress) ||
        IsPublicStudentRequest(context.Request))
    {
        await next();
        return;
    }

    var suppliedToken = context.Request.Headers["X-Attendance-Teacher-Token"].ToString();
    var queryToken = context.Request.Query["teacherToken"].ToString();
    if (string.IsNullOrWhiteSpace(suppliedToken))
    {
        suppliedToken = queryToken;
    }
    if (string.IsNullOrWhiteSpace(suppliedToken))
    {
        suppliedToken = context.Request.Cookies[teacherAccessCookie] ?? string.Empty;
    }

    if (!FixedTimeEquals(suppliedToken, teacherToken))
    {
        context.Response.StatusCode = StatusCodes.Status401Unauthorized;
        await context.Response.WriteAsJsonAsync(new
        {
            success = false,
            code = "TEACHER_AUTH_REQUIRED",
            message = "Đường dẫn quản trị yêu cầu mã truy cập của giảng viên.",
        });
        return;
    }

    if (!string.IsNullOrWhiteSpace(queryToken))
    {
        context.Response.Cookies.Append(
            teacherAccessCookie,
            teacherToken,
            new CookieOptions
            {
                HttpOnly = true,
                Secure = context.Request.IsHttps,
                SameSite = SameSiteMode.Strict,
                IsEssential = true,
                MaxAge = TimeSpan.FromHours(8),
            });
    }

    await next();
});

await using (var scope = app.Services.CreateAsyncScope())
{
    var database = scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();
    await database.Database.EnsureCreatedAsync();
    await database.Database.ExecuteSqlRawAsync("""
        CREATE TABLE IF NOT EXISTS "ClassRosterStudents" (
            "Id" INTEGER NOT NULL CONSTRAINT "PK_ClassRosterStudents" PRIMARY KEY AUTOINCREMENT,
            "ClassCode" TEXT NOT NULL,
            "RollNo" TEXT NOT NULL,
            "FullName" TEXT NOT NULL,
            "Email" TEXT NOT NULL,
            "UpdatedAtUtc" TEXT NOT NULL
        );
        CREATE UNIQUE INDEX IF NOT EXISTS "IX_ClassRosterStudents_ClassCode_RollNo"
            ON "ClassRosterStudents" ("ClassCode", "RollNo");
        CREATE TABLE IF NOT EXISTS "AttendanceDeviceBindings" (
            "Id" INTEGER NOT NULL CONSTRAINT "PK_AttendanceDeviceBindings" PRIMARY KEY AUTOINCREMENT,
            "SessionId" TEXT NOT NULL,
            "DeviceHash" TEXT NOT NULL,
            "RollNo" TEXT NOT NULL,
            "FirstSeenUtc" TEXT NOT NULL,
            "LastSeenUtc" TEXT NOT NULL,
            "BlockedAttempts" INTEGER NOT NULL DEFAULT 0,
            "LastBlockedRollNo" TEXT NOT NULL DEFAULT '',
            "LastBlockedAtUtc" TEXT NULL,
            "NetworkHash" TEXT NOT NULL DEFAULT '',
            "UserAgentHash" TEXT NOT NULL DEFAULT '',
            CONSTRAINT "FK_AttendanceDeviceBindings_Sessions_SessionId"
                FOREIGN KEY ("SessionId") REFERENCES "Sessions" ("Id") ON DELETE CASCADE
        );
        CREATE UNIQUE INDEX IF NOT EXISTS "IX_AttendanceDeviceBindings_SessionId_DeviceHash"
            ON "AttendanceDeviceBindings" ("SessionId", "DeviceHash");
        CREATE INDEX IF NOT EXISTS "IX_AttendanceDeviceBindings_SessionId_NetworkHash"
            ON "AttendanceDeviceBindings" ("SessionId", "NetworkHash");
        CREATE INDEX IF NOT EXISTS "IX_AttendanceDeviceBindings_SessionId_BlockedAttempts"
            ON "AttendanceDeviceBindings" ("SessionId", "BlockedAttempts");
        """);
}

var flutterWebRoot = Path.Combine(repositoryRoot, "build", "web");
var studentPortalRoot = Path.Combine(repositoryRoot, "docs");
var fapDemoRoot = Path.Combine(repositoryRoot, "fap-demo");

if (Directory.Exists(studentPortalRoot))
{
    var studentFiles = new PhysicalFileProvider(studentPortalRoot);
    app.UseStaticFiles(new StaticFileOptions
    {
        FileProvider = studentFiles,
        RequestPath = "/student",
    });
}

if (Directory.Exists(fapDemoRoot))
{
    var fapDemoFiles = new PhysicalFileProvider(fapDemoRoot);
    app.UseStaticFiles(new StaticFileOptions
    {
        FileProvider = fapDemoFiles,
        RequestPath = "/fap-demo",
    });
}

if (Directory.Exists(flutterWebRoot))
{
    var flutterFiles = new PhysicalFileProvider(flutterWebRoot);
    app.UseDefaultFiles(new DefaultFilesOptions { FileProvider = flutterFiles });
    app.UseStaticFiles(new StaticFileOptions { FileProvider = flutterFiles });
}

app.MapGet("/api/health", async (
    GoogleSheetsPrimaryStore sheetsStore,
    CancellationToken cancellationToken) =>
{
    var sheets = await sheetsStore.GetStatusAsync(false, cancellationToken);
    return Results.Ok(new
    {
        status = "ok",
        service = "FAP Attendance ASP.NET Core API",
        database = "Google Sheets",
        localCache = "SQLite",
        googleSheetsConfigured = sheets.IsConfigured,
        realtime = "SignalR",
        utcTime = DateTime.UtcNow,
    });
});

app.MapGet("/api/config/google-sheets", async (
    bool? verify,
    GoogleSheetsPrimaryStore sheetsStore,
    CancellationToken cancellationToken) =>
{
    var status = await sheetsStore.GetStatusAsync(verify == true, cancellationToken);
    return Results.Ok(new
    {
        success = true,
        isConfigured = status.IsConfigured,
        isReachable = status.IsReachable,
        webAppUrl = status.WebAppUrl,
        databaseMode = status.DatabaseMode,
        message = status.Message,
    });
});

app.MapPut("/api/config/google-sheets", async (
    GoogleSheetsConfigurationRequest request,
    GoogleSheetsPrimaryStore sheetsStore,
    AttendanceService service,
    CancellationToken cancellationToken) =>
{
    var status = await sheetsStore.ConfigureAsync(request.WebAppUrl, cancellationToken);
    if (status.IsConfigured && status.IsReachable)
    {
        var rosters = await service.GetAllClassRostersAsync(cancellationToken);
        foreach (var roster in rosters)
        {
            var rosterWrite = await sheetsStore.SyncRosterAsync(
                roster.Key,
                roster.Value,
                cancellationToken);
            if (!rosterWrite.Success)
            {
                return GoogleSheetsWriteFailedResult(
                    $"Đã lưu URL nhưng không thể chuyển roster cũ: {rosterWrite.Message}");
            }
        }

        var sessions = await service.GetRecentSessionsAsync(100, cancellationToken);
        foreach (var session in sessions)
        {
            var sessionWrite = await PersistSnapshotAsync(
                session,
                service,
                sheetsStore,
                cancellationToken);
            if (!sessionWrite.Success)
            {
                return GoogleSheetsWriteFailedResult(
                    $"Đã lưu URL nhưng không thể chuyển phiên cũ: {sessionWrite.Message}");
            }
        }
    }
    return Results.Json(new
    {
        success = status.IsConfigured && status.IsReachable,
        isConfigured = status.IsConfigured,
        isReachable = status.IsReachable,
        webAppUrl = status.WebAppUrl,
        databaseMode = status.DatabaseMode,
        message = status.Message,
    }, statusCode: status.IsConfigured && status.IsReachable
        ? StatusCodes.Status200OK
        : StatusCodes.Status400BadRequest);
});

app.MapPost("/api/sessions", async (
    OpenSessionRequest request,
    AttendanceService service,
    GoogleSheetsPrimaryStore sheetsStore,
    CancellationToken cancellationToken) =>
{
    if (!sheetsStore.IsConfigured) return GoogleSheetsRequiredResult();
    var result = await service.OpenSessionAsync(request, cancellationToken);
    if (result.Value is not null)
    {
        var rosterWrite = await sheetsStore.SyncRosterAsync(
            result.Value.ClassCode,
            result.Value.Students
                .Select(student => new RosterStudentRecord(
                    student.RollNo,
                    student.FullName,
                    student.Email))
                .ToArray(),
            cancellationToken);
        if (!rosterWrite.Success) return GoogleSheetsWriteFailedResult(rosterWrite.Message);
        var persisted = await PersistSnapshotAsync(
            result.Value,
            service,
            sheetsStore,
            cancellationToken);
        if (!persisted.Success) return GoogleSheetsWriteFailedResult(persisted.Message);
    }
    return Results.Json(new
    {
        success = result.Success,
        message = result.Message,
        session = result.Value,
    }, statusCode: result.StatusCode);
});

app.MapGet("/api/sessions", async (
    int? limit,
    AttendanceService service,
    CancellationToken cancellationToken) =>
{
    var sessions = await service.GetRecentSessionsAsync(limit ?? 20, cancellationToken);
    return Results.Ok(new { success = true, count = sessions.Count, sessions });
});

app.MapGet("/api/rosters/{classCode}", async (
    string classCode,
    GoogleSheetsPrimaryStore sheetsStore,
    CancellationToken cancellationToken) =>
{
    if (!sheetsStore.IsConfigured) return GoogleSheetsRequiredResult();
    var (readResult, students) = await sheetsStore.GetRosterAsync(classCode, cancellationToken);
    if (!readResult.Success) return GoogleSheetsWriteFailedResult(readResult.Message);
    return Results.Ok(new
    {
        success = true,
        classCode = classCode.Trim().ToUpperInvariant(),
        count = students.Count,
        students,
    });
});

app.MapPut("/api/rosters/{classCode}", async (
    string classCode,
    RosterSyncRequest request,
    AttendanceService service,
    GoogleSheetsPrimaryStore sheetsStore,
    CancellationToken cancellationToken) =>
{
    if (!sheetsStore.IsConfigured) return GoogleSheetsRequiredResult();
    var result = await service.SyncRosterAsync(classCode, request, cancellationToken);
    if (result.Success && result.Value is not null)
    {
        var rosterWrite = await sheetsStore.SyncRosterAsync(
            result.Value.ClassCode,
            result.Value.Students,
            cancellationToken);
        if (!rosterWrite.Success) return GoogleSheetsWriteFailedResult(rosterWrite.Message);
        if (result.Value.Session is not null)
        {
            var sessionWrite = await PersistSnapshotAsync(
                result.Value.Session,
                service,
                sheetsStore,
                cancellationToken);
            if (!sessionWrite.Success) return GoogleSheetsWriteFailedResult(sessionWrite.Message);
        }
    }
    return Results.Json(new
    {
        success = result.Success,
        message = result.Message,
        roster = result.Value,
        session = result.Value?.Session,
    }, statusCode: result.StatusCode);
});

app.MapPost("/api/sessions/{sessionId}/close", async (
    string sessionId,
    string? actor,
    AttendanceService service,
    GoogleSheetsPrimaryStore sheetsStore,
    CancellationToken cancellationToken) =>
{
    if (!sheetsStore.IsConfigured) return GoogleSheetsRequiredResult();
    var result = await service.CloseSessionAsync(sessionId, actor, cancellationToken);
    if (result.Value is not null)
    {
        var persisted = await PersistSnapshotAsync(
            result.Value,
            service,
            sheetsStore,
            cancellationToken);
        if (!persisted.Success) return GoogleSheetsWriteFailedResult(persisted.Message);
    }
    return Results.Json(new
    {
        success = result.Success,
        message = result.Message,
        session = result.Value,
    }, statusCode: result.StatusCode);
});

app.MapPost("/api/sessions/{sessionId}/otp/pause", async (
    string sessionId,
    string? actor,
    AttendanceService service,
    GoogleSheetsPrimaryStore sheetsStore,
    CancellationToken cancellationToken) =>
{
    if (!sheetsStore.IsConfigured) return GoogleSheetsRequiredResult();
    var result = await service.PauseOtpAsync(sessionId, actor, cancellationToken);
    if (result.Value is not null)
    {
        var persisted = await PersistSnapshotAsync(
            result.Value,
            service,
            sheetsStore,
            cancellationToken);
        if (!persisted.Success) return GoogleSheetsWriteFailedResult(persisted.Message);
    }
    return Results.Json(new
    {
        success = result.Success,
        message = result.Message,
        session = result.Value,
    }, statusCode: result.StatusCode);
});

app.MapPost("/api/sessions/{sessionId}/otp/resume", async (
    string sessionId,
    string? actor,
    AttendanceService service,
    GoogleSheetsPrimaryStore sheetsStore,
    CancellationToken cancellationToken) =>
{
    if (!sheetsStore.IsConfigured) return GoogleSheetsRequiredResult();
    var result = await service.ResumeOtpAsync(sessionId, actor, cancellationToken);
    if (result.Value is not null)
    {
        var persisted = await PersistSnapshotAsync(
            result.Value,
            service,
            sheetsStore,
            cancellationToken);
        if (!persisted.Success) return GoogleSheetsWriteFailedResult(persisted.Message);
    }
    return Results.Json(new
    {
        success = result.Success,
        message = result.Message,
        session = result.Value,
    }, statusCode: result.StatusCode);
});

app.MapGet("/api/sessions/{sessionId}", async (
    string sessionId,
    AttendanceService service,
    CancellationToken cancellationToken) =>
{
    var snapshot = await service.GetSnapshotAsync(sessionId, cancellationToken);
    return snapshot is null
        ? Results.NotFound(new { success = false, message = "Không tìm thấy phiên điểm danh." })
        : Results.Ok(snapshot);
});

app.MapGet("/api/attendance", async (
    string? sessionId,
    AttendanceService service,
    CancellationToken cancellationToken) =>
{
    var snapshot = await service.GetSnapshotAsync(sessionId, cancellationToken);
    return snapshot is null
        ? Results.Ok(new
        {
            status = "success",
            count = 0,
            students = Array.Empty<AttendanceRecord>(),
        })
        : Results.Ok(snapshot);
});

app.MapPost("/api/attendance", async (
    StudentCheckinRequest request,
    HttpContext httpContext,
    DeviceIdentityService deviceIdentityService,
    AttendanceService service,
    GoogleSheetsPrimaryStore sheetsStore,
    CancellationToken cancellationToken) =>
{
    if (!sheetsStore.IsConfigured) return GoogleSheetsRequiredResult();
    var email = request.Email?.Trim().ToLowerInvariant();
    if (string.IsNullOrWhiteSpace(email) ||
        !MailAddress.TryCreate(email, out var parsedEmail) ||
        !parsedEmail.Address.Equals(email, StringComparison.OrdinalIgnoreCase))
    {
        return Results.BadRequest(new
        {
            success = false,
            message = "Vui lòng nhập một địa chỉ email hợp lệ.",
        });
    }

    if (string.IsNullOrWhiteSpace(request.RollNo))
    {
        return Results.BadRequest(new { success = false, message = "Vui lòng nhập MSSV." });
    }

    var deviceIdentity = deviceIdentityService.GetOrCreate(httpContext);
    var result = await service.CheckinAsync(request, deviceIdentity, cancellationToken);
    if (result.Value is not null)
    {
        var persisted = await PersistSnapshotAsync(
            result.Value,
            service,
            sheetsStore,
            cancellationToken);
        if (!persisted.Success) return GoogleSheetsWriteFailedResult(persisted.Message);
    }
    var student = result.Value?.Students.FirstOrDefault(item =>
        item.RollNo.Equals(request.RollNo, StringComparison.OrdinalIgnoreCase));
    return Results.Json(new
    {
        success = result.Success,
        code = result.Code,
        message = result.Message,
        student,
        session = result.Value,
    }, statusCode: result.StatusCode);
});

app.MapPost("/api/sessions/{sessionId}/devices/{bindingId:long}/release", async (
    string sessionId,
    long bindingId,
    ReleaseDeviceRequest request,
    AttendanceService service,
    GoogleSheetsPrimaryStore sheetsStore,
    CancellationToken cancellationToken) =>
{
    if (!sheetsStore.IsConfigured) return GoogleSheetsRequiredResult();
    var result = await service.ReleaseDeviceBindingAsync(
        sessionId,
        bindingId,
        request,
        cancellationToken);
    if (result.Value is not null)
    {
        var persisted = await PersistSnapshotAsync(
            result.Value,
            service,
            sheetsStore,
            cancellationToken);
        if (!persisted.Success) return GoogleSheetsWriteFailedResult(persisted.Message);
    }
    return Results.Json(new
    {
        success = result.Success,
        message = result.Message,
        session = result.Value,
    }, statusCode: result.StatusCode);
});

app.MapPatch("/api/sessions/{sessionId}/attendance/{rollNo}", async (
    string sessionId,
    string rollNo,
    UpdateAttendanceRequest request,
    AttendanceService service,
    GoogleSheetsPrimaryStore sheetsStore,
    CancellationToken cancellationToken) =>
{
    if (!sheetsStore.IsConfigured) return GoogleSheetsRequiredResult();
    var result = await service.UpdateAttendanceAsync(
        sessionId,
        rollNo,
        request,
        cancellationToken);
    if (result.Value is not null)
    {
        var persisted = await PersistSnapshotAsync(
            result.Value,
            service,
            sheetsStore,
            cancellationToken);
        if (!persisted.Success) return GoogleSheetsWriteFailedResult(persisted.Message);
    }
    return Results.Json(new
    {
        success = result.Success,
        message = result.Message,
        session = result.Value,
    }, statusCode: result.StatusCode);
});

app.MapGet("/api/sessions/{sessionId}/audit", async (
    string sessionId,
    AttendanceService service,
    CancellationToken cancellationToken) =>
{
    var logs = await service.GetAuditLogsAsync(sessionId, cancellationToken);
    return Results.Ok(new { success = true, count = logs.Count, logs });
});

app.MapGet("/api/sessions/{sessionId}/export.csv", async (
    string sessionId,
    AttendanceService service,
    CancellationToken cancellationToken) =>
{
    var export = await service.ExportCsvAsync(sessionId, cancellationToken);
    return export is null
        ? Results.NotFound(new { success = false, message = "Không tìm thấy phiên điểm danh." })
        : Results.File(export.Value.Content, "text/csv; charset=utf-8", export.Value.FileName);
});

app.MapPost("/api/google-sheets/seed-demo", async (
    GoogleSheetsPrimaryStore sheetsStore,
    CancellationToken cancellationToken) =>
{
    if (!sheetsStore.IsConfigured) return GoogleSheetsRequiredResult();
    var seeded = await sheetsStore.SeedDemoAsync(cancellationToken);
    return seeded.Success
        ? Results.Ok(new
        {
            success = true,
            message = "Đã seed 4 lớp, 32 sinh viên và các phiên mẫu vào Google Sheets.",
            classCount = 4,
            studentCount = 32,
        })
        : GoogleSheetsWriteFailedResult(seeded.Message);
});

app.MapPost("/api/google-sheets/sync/{sessionId}", async (
    string sessionId,
    AttendanceService service,
    GoogleSheetsPrimaryStore sheetsStore,
    CancellationToken cancellationToken) =>
{
    if (!sheetsStore.IsConfigured) return GoogleSheetsRequiredResult();
    var snapshot = await service.GetSnapshotAsync(sessionId, cancellationToken);
    if (snapshot is null)
    {
        return Results.NotFound(new
        {
            success = false,
            message = "Không tìm thấy phiên điểm danh để đồng bộ.",
        });
    }

    var persisted = await PersistSnapshotAsync(
        snapshot,
        service,
        sheetsStore,
        cancellationToken);
    return persisted.Success
        ? Results.Ok(new { success = true, message = persisted.Message, session = snapshot })
        : GoogleSheetsWriteFailedResult(persisted.Message);
});

app.MapHub<AttendanceHub>("/hubs/attendance");

app.MapGet("/student", async context =>
{
    if (!context.Request.Path.Value!.EndsWith('/'))
    {
        context.Response.Redirect("/student/");
        return;
    }

    var studentIndexPath = Path.Combine(studentPortalRoot, "index.html");
    if (!File.Exists(studentIndexPath))
    {
        context.Response.StatusCode = StatusCodes.Status404NotFound;
        return;
    }

    context.Response.ContentType = "text/html; charset=utf-8";
    await context.Response.SendFileAsync(studentIndexPath);
});

app.MapGet("/fap-demo", async context =>
{
    if (!context.Request.Path.Value!.EndsWith('/'))
    {
        context.Response.Redirect("/fap-demo/");
        return;
    }

    var fapDemoIndexPath = Path.Combine(fapDemoRoot, "index.html");
    if (!File.Exists(fapDemoIndexPath))
    {
        context.Response.StatusCode = StatusCodes.Status404NotFound;
        return;
    }

    context.Response.ContentType = "text/html; charset=utf-8";
    await context.Response.SendFileAsync(fapDemoIndexPath);
});

app.MapFallback(async context =>
{
    var indexPath = Path.Combine(flutterWebRoot, "index.html");
    if (File.Exists(indexPath) &&
        context.Request.Headers.Accept.Any(value => value?.Contains("text/html") == true))
    {
        context.Response.ContentType = "text/html; charset=utf-8";
        await context.Response.SendFileAsync(indexPath);
        return;
    }

    context.Response.StatusCode = StatusCodes.Status404NotFound;
    await context.Response.WriteAsJsonAsync(new
    {
        status = "not_found",
        message = Directory.Exists(flutterWebRoot)
            ? "Không tìm thấy tài nguyên được yêu cầu."
            : "Chưa có build Flutter Web. Chạy 'flutter build web' trước khi mở trang chủ.",
        studentPortal = "/student/",
        fapDemo = "/fap-demo/",
        api = "/api/attendance",
    });
});

app.Run();

static async Task<GoogleSheetsWriteResult> PersistSnapshotAsync(
    AttendanceSnapshot snapshot,
    AttendanceService service,
    GoogleSheetsPrimaryStore sheetsStore,
    CancellationToken cancellationToken)
{
    var auditLogs = await service.GetAuditLogsAsync(snapshot.SessionId, cancellationToken);
    return await sheetsStore.SyncSessionAsync(snapshot, auditLogs, cancellationToken);
}

static IResult GoogleSheetsRequiredResult() => Results.Json(new
{
    success = false,
    code = "GOOGLE_SHEETS_NOT_CONFIGURED",
    message = "Google Sheets là database chính. Hãy cấu hình Web App URL trước khi sử dụng.",
}, statusCode: StatusCodes.Status503ServiceUnavailable);

static IResult GoogleSheetsWriteFailedResult(string message) => Results.Json(new
{
    success = false,
    code = "GOOGLE_SHEETS_WRITE_FAILED",
    message,
}, statusCode: StatusCodes.Status502BadGateway);

static bool IsLoopback(IPAddress? address) =>
    address is not null && IPAddress.IsLoopback(address);

static bool IsPublicStudentRequest(HttpRequest request)
{
    if (request.Path.StartsWithSegments("/student") ||
        request.Path.StartsWithSegments("/hubs/attendance"))
    {
        return true;
    }

    if (HttpMethods.IsGet(request.Method) && request.Path == "/api/health")
    {
        return true;
    }

    if (HttpMethods.IsPost(request.Method) && request.Path == "/api/attendance")
    {
        return true;
    }

    if (!HttpMethods.IsGet(request.Method)) return false;

    var segments = request.Path.Value?
        .Split('/', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
    return segments is ["api", "sessions", _];
}

static bool FixedTimeEquals(string suppliedToken, string expectedToken)
{
    var suppliedBytes = Encoding.UTF8.GetBytes(suppliedToken);
    var expectedBytes = Encoding.UTF8.GetBytes(expectedToken);
    return suppliedBytes.Length == expectedBytes.Length &&
        CryptographicOperations.FixedTimeEquals(suppliedBytes, expectedBytes);
}
