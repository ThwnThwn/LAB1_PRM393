using System.Net.Mail;
using Attendance.Api.Data;
using Attendance.Api.Hubs;
using Attendance.Api.Models;
using Attendance.Api.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.FileProviders;

var builder = WebApplication.CreateBuilder(args);

builder.WebHost.UseUrls(builder.Configuration["Urls"] ?? "http://0.0.0.0:8080");

var repositoryRoot = Path.GetFullPath(Path.Combine(builder.Environment.ContentRootPath, ".."));
var dataDirectory = Path.Combine(builder.Environment.ContentRootPath, "App_Data");
Directory.CreateDirectory(dataDirectory);
var databasePath = Path.Combine(dataDirectory, "attendance.db");

builder.Services.AddDbContext<AttendanceDbContext>(options =>
    options.UseSqlite($"Data Source={databasePath}"));
builder.Services.AddScoped<AttendanceService>();
builder.Services.AddSingleton<OtpService>();
builder.Services.AddSignalR();
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
app.UseCors();

await using (var scope = app.Services.CreateAsyncScope())
{
    var database = scope.ServiceProvider.GetRequiredService<AttendanceDbContext>();
    await database.Database.EnsureCreatedAsync();
}

var flutterWebRoot = Path.Combine(repositoryRoot, "build", "web");
var studentPortalRoot = Path.Combine(repositoryRoot, "docs");

if (Directory.Exists(studentPortalRoot))
{
    var studentFiles = new PhysicalFileProvider(studentPortalRoot);
    app.UseStaticFiles(new StaticFileOptions
    {
        FileProvider = studentFiles,
        RequestPath = "/student",
    });
}

if (Directory.Exists(flutterWebRoot))
{
    var flutterFiles = new PhysicalFileProvider(flutterWebRoot);
    app.UseDefaultFiles(new DefaultFilesOptions { FileProvider = flutterFiles });
    app.UseStaticFiles(new StaticFileOptions { FileProvider = flutterFiles });
}

app.MapGet("/api/health", () => Results.Ok(new
{
    status = "ok",
    service = "FAP Attendance ASP.NET Core API",
    database = "SQLite",
    realtime = "SignalR",
    utcTime = DateTime.UtcNow,
}));

app.MapPost("/api/sessions", async (
    OpenSessionRequest request,
    AttendanceService service,
    CancellationToken cancellationToken) =>
{
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
    AttendanceService service,
    CancellationToken cancellationToken) =>
{
    var sessions = await service.GetRecentSessionsAsync(limit ?? 20, cancellationToken);
    return Results.Ok(new { success = true, count = sessions.Count, sessions });
});

app.MapPost("/api/sessions/{sessionId}/close", async (
    string sessionId,
    string? actor,
    AttendanceService service,
    CancellationToken cancellationToken) =>
{
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
    CancellationToken cancellationToken) =>
{
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
    CancellationToken cancellationToken) =>
{
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

app.MapPost("/api/attendance", async (
    StudentCheckinRequest request,
    AttendanceService service,
    CancellationToken cancellationToken) =>
{
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

    var result = await service.CheckinAsync(request, cancellationToken);
    var student = result.Value?.Students.FirstOrDefault(item =>
        item.RollNo.Equals(request.RollNo, StringComparison.OrdinalIgnoreCase));
    return Results.Json(new
    {
        success = result.Success,
        message = result.Message,
        student,
        session = result.Value,
    }, statusCode: result.StatusCode);
});

app.MapPatch("/api/sessions/{sessionId}/attendance/{rollNo}", async (
    string sessionId,
    string rollNo,
    UpdateAttendanceRequest request,
    AttendanceService service,
    CancellationToken cancellationToken) =>
{
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
        api = "/api/attendance",
    });
});

app.Run();
