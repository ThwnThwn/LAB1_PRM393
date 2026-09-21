using System.Security.Cryptography;
using System.Text;
using Attendance.Api.Models;
using Microsoft.AspNetCore.WebUtilities;

namespace Attendance.Api.Services;

public sealed class DeviceIdentityService
{
    private const string CookieName = "fap_attendance_device";
    private static readonly TimeSpan CookieLifetime = TimeSpan.FromDays(365);

    public DeviceIdentity GetOrCreate(HttpContext context)
    {
        var token = context.Request.Cookies[CookieName];
        if (!IsValidToken(token))
        {
            token = WebEncoders.Base64UrlEncode(RandomNumberGenerator.GetBytes(32));
            context.Response.Cookies.Append(
                CookieName,
                token,
                new CookieOptions
                {
                    HttpOnly = true,
                    IsEssential = true,
                    MaxAge = CookieLifetime,
                    Path = "/",
                    SameSite = SameSiteMode.Lax,
                    Secure = context.Request.IsHttps,
                });
        }

        var deviceHash = Hash(token!);
        var remoteAddress = context.Connection.RemoteIpAddress?.ToString() ?? "unknown";
        var userAgent = context.Request.Headers.UserAgent.ToString();
        return new DeviceIdentity(
            deviceHash,
            deviceHash[..8],
            Hash(remoteAddress),
            Hash(userAgent));
    }

    private static bool IsValidToken(string? token) =>
        !string.IsNullOrWhiteSpace(token) &&
        token.Length is >= 32 and <= 128 &&
        token.All(character => char.IsAsciiLetterOrDigit(character) || character is '-' or '_');

    private static string Hash(string value) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)));
}
