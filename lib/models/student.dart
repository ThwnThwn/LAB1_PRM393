enum AttendanceStatus { present, absent }

extension AttendanceStatusExtension on AttendanceStatus {
  String toLabel() {
    switch (this) {
      case AttendanceStatus.present:
        return 'PRESENT';
      case AttendanceStatus.absent:
        return 'ABSENT';
    }
  }

  static AttendanceStatus fromString(String statusStr) {
    switch (statusStr.trim().toUpperCase()) {
      case 'PRESENT':
      case 'CÓ MẶT':
      case 'P':
      case 'LATE':
      case 'TRỄ':
      case 'L':
        return AttendanceStatus.present;
      case 'ABSENT':
      case 'VẮNG':
      case 'A':
        return AttendanceStatus.absent;
      default:
        return AttendanceStatus.absent;
    }
  }
}

class Student {
  final String rollNo; // e.g. SE182173
  final String fullName; // e.g. Bui Nhat Minh
  final String email; // e.g. minhnbse182173@fpt.edu.vn
  final String group; // e.g. SE1801
  AttendanceStatus status;
  DateTime? checkinTime;
  String notes;

  Student({
    required this.rollNo,
    required this.fullName,
    required this.email,
    required this.group,
    this.status = AttendanceStatus.absent,
    this.checkinTime,
    this.notes = '',
  });

  factory Student.fromMap(Map<String, dynamic> map) {
    return Student(
      rollNo: map['rollNo'] ?? map['RollNo'] ?? '',
      fullName: map['fullName'] ?? map['FullName'] ?? '',
      email: map['email'] ?? map['Email'] ?? '',
      group: map['group'] ?? map['Group'] ?? 'SE1801',
      status: AttendanceStatusExtension.fromString(
        map['status'] ?? map['Status'] ?? '',
      ),
      checkinTime: map['checkinTime'] != null
          ? DateTime.tryParse(map['checkinTime'])
          : null,
      notes: map['notes'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'rollNo': rollNo,
      'fullName': fullName,
      'email': email,
      'group': group,
      'status': status.toLabel(),
      'checkinTime': checkinTime?.toIso8601String() ?? '',
      'notes': notes,
    };
  }
}
