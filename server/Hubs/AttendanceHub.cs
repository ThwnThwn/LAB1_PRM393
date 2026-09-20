using Microsoft.AspNetCore.SignalR;

namespace Attendance.Api.Hubs;

public sealed class AttendanceHub : Hub
{
    public Task JoinSession(string sessionId) =>
        Groups.AddToGroupAsync(Context.ConnectionId, GetGroupName(sessionId));

    public Task LeaveSession(string sessionId) =>
        Groups.RemoveFromGroupAsync(Context.ConnectionId, GetGroupName(sessionId));

    public static string GetGroupName(string sessionId) => $"attendance:{sessionId}";
}
