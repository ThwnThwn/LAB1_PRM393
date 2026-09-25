using System.Net.Mail;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Attendance.Api.Hubs;
using Attendance.Api.Models;
using Attendance.Api.Services;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.Extensions.FileProviders;
using Microsoft.AspNetCore.HttpOverrides;

var builder = WebApplication.CreateBuilder(args);

builder.WebHost.UseUrls(builder.Configuration["Urls"] ?? "http://0.0.0.0:8080");

var repositoryRoot = Path.GetFullPath(Path.Combine(builder.Environment.ContentRootPath, ".."));

builder.Services.AddScoped<AttendanceService>();
builder.Services.AddHttpClient(nameof(GoogleSheetsPrimaryStore));
builder.Services.AddSingleton<GoogleSheetsPrimaryStore>();
builder.Services.AddSingleton<AttendanceUpdateStream>();
builder.Services.AddSingleton<OtpService>();
builder.Services.AddSingleton<DeviceIdentityService>();
builder.Services.AddSingleton<TimetableOcrService>();
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
app.UseExceptionHandler(errorApp => errorApp.Run(async context =>
{
    var error = context.Features.Get<IExceptionHandlerFeature>()?.Error;
    context.Response.StatusCode = StatusCodes.Status502BadGateway;
    await context.Response.WriteAsJsonAsync(new
    {
        success = false,
        code = "GOOGLE_SHEETS_READ_FAILED",
        message = error?.Message ?? "Không thể đọc dữ liệu từ Google Sheets.",
    });
}));
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

var flutterWebRoot = Path.Combine(repositoryRoot, "build", "web");
var studentPortalRoot = Path.Combine(repositoryRoot, "student-portal");
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
        localCache = "Không sử dụng",
        runtimeState = "Chỉ OTP và SignalR trong RAM",
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
    CancellationToken cancellationToken) =>
{
    var status = await sheetsStore.ConfigureAsync(request.WebAppUrl, cancellationToken);
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

app.MapPost("/api/timetable/import-image", async (
    HttpRequest request,
    TimetableOcrService ocrService,
    CancellationToken cancellationToken) =>
{
    if (!request.HasFormContentType)
    {
        return Results.BadRequest(new
        {
            success = false,
            message = "Yêu cầu phải chứa ảnh thời khóa biểu.",
        });
    }

    var form = await request.ReadFormAsync(cancellationToken);
    var image = form.Files.GetFile("image") ?? form.Files.FirstOrDefault();
    if (image is null || image.Length == 0)
    {
        return Results.BadRequest(new
        {
            success = false,
            message = "Chưa chọn ảnh thời khóa biểu.",
        });
    }

    const long maxImageBytes = 12 * 1024 * 1024;
    if (image.Length > maxImageBytes)
    {
        return Results.Json(new
        {
            success = false,
            message = "Ảnh vượt quá giới hạn 12 MB.",
        }, statusCode: StatusCodes.Status413PayloadTooLarge);
    }

    var extension = Path.GetExtension(image.FileName).ToLowerInvariant();
    var supportedExtensions = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        ".png", ".jpg", ".jpeg", ".bmp", ".tif", ".tiff", ".webp",
    };
    if (!supportedExtensions.Contains(extension))
    {
        return Results.Json(new
        {
            success = false,
            message = "Định dạng ảnh chưa được hỗ trợ. Hãy dùng PNG, JPG, BMP, TIFF hoặc WebP.",
        }, statusCode: StatusCodes.Status415UnsupportedMediaType);
    }

    try
    {
        await using var stream = image.OpenReadStream();
        using var memory = new MemoryStream();
        await stream.CopyToAsync(memory, cancellationToken);
        var result = await ocrService.RecognizeAsync(memory.ToArray(), cancellationToken);
        return Results.Ok(new
        {
            success = true,
            fileName = Path.GetFileName(image.FileName),
            result.RawText,
            result.Confidence,
            result.Candidates,
            result.Warnings,
        });
    }
    catch (OperationCanceledException)
    {
        return Results.StatusCode(499);
    }
    catch (Exception error)
    {
        return Results.Json(new
        {
            success = false,
            message = $"Không thể đọc ảnh thời khóa biểu: {error.Message}",
        }, statusCode: StatusCodes.Status422UnprocessableEntity);
    }
}).DisableAntiforgery();

app.MapPost("/api/sessions", async (
    OpenSessionRequest request,
    AttendanceService service,
    GoogleSheetsPrimaryStore sheetsStore,
    CancellationToken cancellationToken) =>
{
    if (!sheetsStore.IsConfigured) return GoogleSheetsRequiredResult();
    var result = await service.OpenSessionAsync(request, cancellationToken);
    return Results.Json(new
    {
        success = result.Success,
        message = result.Message,
        session = result.Value,
    }, statusCode: result.StatusCode);
});

app.MapGet("/api/sessions", async (
    int? limit,
    string? classCode,
    string? subjectCode,
    int? slot,
    AttendanceService service,
    CancellationToken cancellationToken) =>
{
    var sessions = await service.GetRecentSessionsAsync(
        limit ?? 20,
        cancellationToken,
        classCode,
        subjectCode,
        slot);
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

app.MapGet("/api/updates", async (HttpContext context, AttendanceUpdateStream updates) =>
{
    var cancellationToken = context.RequestAborted;
    context.Response.ContentType = "text/event-stream";
    context.Response.Headers["Cache-Control"] = "no-cache, no-transform";
    context.Response.Headers["X-Accel-Buffering"] = "no";
    var subscription = updates.Subscribe();
    try
    {
        await context.Response.WriteAsync("retry: 3000\n: connected\n\n", cancellationToken);
        await context.Response.Body.FlushAsync(cancellationToken);
        await foreach (var update in subscription.Reader.ReadAllAsync(cancellationToken))
        {
            var payload = JsonSerializer.Serialize(update, new JsonSerializerOptions(JsonSerializerDefaults.Web));
            await context.Response.WriteAsync($"event: attendance\ndata: {payload}\n\n", cancellationToken);
            await context.Response.Body.FlushAsync(cancellationToken);
        }
    }
    catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
    {
        // A closed browser tab ends the stream normally.
    }
    finally
    {
        updates.Unsubscribe(subscription.Id);
    }
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
    return Results.Json(new
    {
        success = result.Success,
        message = result.Message,
        session = result.Value,
    }, statusCode: result.StatusCode);
});

app.MapPost("/api/sessions/attendance/batch", async (
    SaveAttendanceBatchRequest request,
    AttendanceService service,
    GoogleSheetsPrimaryStore sheetsStore,
    CancellationToken cancellationToken) =>
{
    if (!sheetsStore.IsConfigured) return GoogleSheetsRequiredResult();
    var result = await service.SaveAttendanceBatchAsync(request, cancellationToken);
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
            message = "Đã seed lịch tuần 21/09–27/09/2026, 4 lớp dùng chung roster 35 sinh viên và 7 ca học vào Google Sheets.",
            classCount = 4,
            studentCount = 35,
            rosterRowCount = 140,
            sessionCount = 7,
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

    return Results.Ok(new
    {
        success = true,
        message = "Phiên đã được đọc trực tiếp từ Google Sheets; không còn cache SQLite để đồng bộ.",
        session = snapshot,
    });
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
