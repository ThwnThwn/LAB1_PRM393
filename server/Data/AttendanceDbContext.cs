using Attendance.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace Attendance.Api.Data;

public sealed class AttendanceDbContext(DbContextOptions<AttendanceDbContext> options)
    : DbContext(options)
{
    public DbSet<AttendanceSessionEntity> Sessions => Set<AttendanceSessionEntity>();
    public DbSet<AttendanceEntryEntity> AttendanceEntries => Set<AttendanceEntryEntity>();
    public DbSet<AttendanceDeviceBindingEntity> AttendanceDeviceBindings => Set<AttendanceDeviceBindingEntity>();
    public DbSet<ClassRosterStudentEntity> ClassRosterStudents => Set<ClassRosterStudentEntity>();
    public DbSet<AuditLogEntity> AuditLogs => Set<AuditLogEntity>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<AttendanceSessionEntity>(entity =>
        {
            entity.HasIndex(session => new
            {
                session.ClassCode,
                session.SubjectCode,
                session.Slot,
                session.IsOpen,
            });
            entity.Property(session => session.ClassCode).HasMaxLength(50);
            entity.Property(session => session.SubjectCode).HasMaxLength(50);
        });

        modelBuilder.Entity<AttendanceEntryEntity>(entity =>
        {
            entity.HasIndex(entry => new { entry.SessionId, entry.RollNo }).IsUnique();
            entity.Property(entry => entry.RollNo).HasMaxLength(50);
            entity.Property(entry => entry.Status).HasMaxLength(20);
            entity.HasOne(entry => entry.Session)
                .WithMany(session => session.AttendanceEntries)
                .HasForeignKey(entry => entry.SessionId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<AttendanceDeviceBindingEntity>(entity =>
        {
            entity.HasIndex(binding => new { binding.SessionId, binding.DeviceHash }).IsUnique();
            entity.HasIndex(binding => new { binding.SessionId, binding.NetworkHash });
            entity.HasIndex(binding => new { binding.SessionId, binding.BlockedAttempts });
            entity.Property(binding => binding.DeviceHash).HasMaxLength(64);
            entity.Property(binding => binding.RollNo).HasMaxLength(50);
            entity.Property(binding => binding.LastBlockedRollNo).HasMaxLength(50);
            entity.Property(binding => binding.NetworkHash).HasMaxLength(64);
            entity.Property(binding => binding.UserAgentHash).HasMaxLength(64);
            entity.HasOne(binding => binding.Session)
                .WithMany()
                .HasForeignKey(binding => binding.SessionId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<ClassRosterStudentEntity>(entity =>
        {
            entity.HasIndex(student => new { student.ClassCode, student.RollNo }).IsUnique();
            entity.Property(student => student.ClassCode).HasMaxLength(50);
            entity.Property(student => student.RollNo).HasMaxLength(50);
        });

        modelBuilder.Entity<AuditLogEntity>(entity =>
        {
            entity.HasIndex(log => new { log.SessionId, log.CreatedAtUtc });
            entity.Property(log => log.Action).HasMaxLength(50);
            entity.Property(log => log.Actor).HasMaxLength(100);
        });
    }
}
