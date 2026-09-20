using System.Collections.Concurrent;

namespace Attendance.Api.Services;

public sealed class OtpService
{
    private const int OtpDurationSeconds = 10;
    private const string SeedKey = "FAP_ATTENDANCE_SECRET_2026";
    private readonly ConcurrentDictionary<string, PausedOtpState> pausedSessions =
        new(StringComparer.OrdinalIgnoreCase);

    public bool Validate(string? inputOtp, DateTimeOffset? now = null)
    {
        var cleanOtp = inputOtp?.Trim();
        if (cleanOtp is null || cleanOtp.Length != 6 || !cleanOtp.All(char.IsDigit))
        {
            return false;
        }

        var epochSeconds = (now ?? DateTimeOffset.UtcNow).ToUnixTimeSeconds();
        var currentWindow = epochSeconds / OtpDurationSeconds;

        return cleanOtp == Calculate(currentWindow) || cleanOtp == Calculate(currentWindow - 1);
    }

    public bool ValidateForSession(
        string sessionId,
        string? inputOtp,
        DateTimeOffset? now = null)
    {
        var cleanOtp = inputOtp?.Trim();
        if (cleanOtp is null || cleanOtp.Length != 6 || !cleanOtp.All(char.IsDigit))
        {
            return false;
        }

        if (pausedSessions.TryGetValue(sessionId, out var pausedState))
        {
            return cleanOtp == pausedState.Otp;
        }

        return Validate(cleanOtp, now);
    }

    public PausedOtpState Pause(string sessionId, DateTimeOffset? now = null)
    {
        return pausedSessions.GetOrAdd(sessionId, _ =>
        {
            var timestamp = now ?? DateTimeOffset.UtcNow;
            var epochSeconds = timestamp.ToUnixTimeSeconds();
            return new PausedOtpState(
                Generate(timestamp),
                OtpDurationSeconds - (int)(epochSeconds % OtpDurationSeconds));
        });
    }

    public void Resume(string sessionId) => pausedSessions.TryRemove(sessionId, out _);

    public PausedOtpState? GetPausedState(string sessionId) =>
        pausedSessions.TryGetValue(sessionId, out var state) ? state : null;

    internal static string Generate(DateTimeOffset time)
    {
        var window = time.ToUnixTimeSeconds() / OtpDurationSeconds;
        return Calculate(window);
    }

    private static string Calculate(long windowIndex)
    {
        var hash = 5381;
        var value = $"{SeedKey}:{windowIndex}";

        unchecked
        {
            foreach (var character in value)
            {
                hash = ((hash << 5) + hash) + character;
            }
        }

        var positiveHash = hash == int.MinValue ? int.MaxValue : Math.Abs(hash);
        var code = (positiveHash % 900_000) + 100_000;
        return code.ToString();
    }
}

public sealed record PausedOtpState(string Otp, int RemainingSeconds);
