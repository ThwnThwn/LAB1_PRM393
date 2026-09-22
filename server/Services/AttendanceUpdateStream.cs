using System.Collections.Concurrent;
using System.Threading.Channels;
using Attendance.Api.Models;

namespace Attendance.Api.Services;

// Transient notifications only. Google Sheets remains the sole durable store.
public sealed record AttendanceUpdate(string EventName, AttendanceSnapshot Snapshot);

public sealed class AttendanceUpdateStream
{
    private readonly ConcurrentDictionary<Guid, Channel<AttendanceUpdate>> subscribers = new();

    public (Guid Id, ChannelReader<AttendanceUpdate> Reader) Subscribe()
    {
        var id = Guid.NewGuid();
        var channel = Channel.CreateBounded<AttendanceUpdate>(new BoundedChannelOptions(16)
        {
            FullMode = BoundedChannelFullMode.DropOldest,
            SingleReader = true,
            SingleWriter = false,
        });
        subscribers[id] = channel;
        return (id, channel.Reader);
    }

    public void Unsubscribe(Guid id)
    {
        if (subscribers.TryRemove(id, out var channel)) channel.Writer.TryComplete();
    }

    public void Publish(string eventName, AttendanceSnapshot? snapshot)
    {
        if (snapshot is null) return;
        var update = new AttendanceUpdate(eventName, snapshot);
        foreach (var channel in subscribers.Values) channel.Writer.TryWrite(update);
    }
}
