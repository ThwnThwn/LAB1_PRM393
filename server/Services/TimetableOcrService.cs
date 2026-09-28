using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using Tesseract;

namespace Attendance.Api.Services;

public sealed class TimetableOcrService(IWebHostEnvironment environment)
{
    private static readonly Regex SubjectCodePattern = new(
        @"(?<![A-Z0-9])(?<prefix>[A-Z]{2,5})\s*[-–]?\s*(?<number>[0-9ILOSBZG]{3})(?<suffix>[A-Z]?)(?![A-Z0-9])",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);
    private static readonly Regex ClassCodePattern = new(
        @"(?<![A-Z0-9])(?<prefix>[A-Z]{2})\s*[-–]?\s*(?<number>[0-9ILOSBZG]{4,6})(?![A-Z0-9])",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);
    private static readonly Regex RoomPattern = new(
        @"\b(?:(?:PH[ÒO]NG|ROOM)\s*)?(?:NVH|DE|BE|AL|P)\s*[-.]?\s*[A-Z]?\d{2,4}\b|\b(?:ONLINE|TRỰC\s*TUYẾN)\b",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);
    private static readonly Regex SlotPattern = new(
        @"\b(?:SLOT|CA|TI[EẾ]T)\s*[:#-]?\s*([1-8])\b",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);
    private static readonly Regex TimePattern = new(
        @"(?<!\d)(0?7|0?9|12|15|17|19|20)\s*[:.hH]\s*(00|30|45)(?!\d)",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);
    private static readonly Regex InstructorPattern = new(
        @"(?<![A-Za-z])(?<name>[A-Z][a-z]{2,}[A-Z]{2,5})(?![A-Za-z])",
        RegexOptions.Compiled);

    private readonly string _tessdataPath = Path.Combine(environment.ContentRootPath, "tessdata");

    public Task<TimetableOcrResult> RecognizeAsync(byte[] imageBytes, CancellationToken cancellationToken)
    {
        return Task.Run(() => Recognize(imageBytes), cancellationToken);
    }

    public TimetableOcrResult Recognize(byte[] imageBytes)
    {
        if (!Directory.Exists(_tessdataPath) ||
            !File.Exists(Path.Combine(_tessdataPath, "eng.traineddata")) ||
            !File.Exists(Path.Combine(_tessdataPath, "vie.traineddata")))
        {
            throw new InvalidOperationException(
                "Thiếu dữ liệu OCR eng/vie trong thư mục server/tessdata.");
        }

        using var engine = new TesseractEngine(_tessdataPath, "eng+vie", EngineMode.LstmOnly);
        engine.SetVariable("user_defined_dpi", "300");
        engine.SetVariable("preserve_interword_spaces", "1");
        using var image = Pix.LoadFromMemory(imageBytes);
        using var page = engine.Process(image, PageSegMode.Auto);

        var lines = ReadLines(page);
        var candidates = Parse(lines);
        var meanConfidence = Math.Clamp(page.GetMeanConfidence(), 0, 1);
        return new TimetableOcrResult(
            page.GetText().Trim(),
            meanConfidence,
            candidates,
            candidates.Count == 0
                ? ["Chưa tìm thấy mã môn dạng PRN232. Bạn có thể thêm ca thủ công trong bước xem trước."]
                : []);
    }

    internal static IReadOnlyList<TimetableOcrCandidate> Parse(IReadOnlyList<OcrLine> lines)
    {
        var dayAnchors = lines
            .Select(line => (line, day: ParseDay(line.Text)))
            .Where(item => item.day is not null)
            .ToList();
        var slotAnchors = lines
            .Select(line => (line, slot: ParseSlot(line.Text)))
            .Where(item => item.slot is not null)
            .ToList();

        var candidates = new List<TimetableOcrCandidate>();
        foreach (var subjectLine in lines.Where(line => SubjectCodePattern.IsMatch(line.Text)))
        {
            var subjectMatch = SubjectCodePattern.Match(subjectLine.Text);
            if (ClassCodePattern.IsMatch(subjectMatch.Value)) continue;

            var rawSubjectCode = CompactCode(subjectMatch.Value);
            var subjectCode = NormalizeSubjectCode(subjectMatch);
            if (subjectCode.Length < 5 ||
                subjectCode.StartsWith("NVH", StringComparison.OrdinalIgnoreCase) ||
                subjectCode.StartsWith("ROOM", StringComparison.OrdinalIgnoreCase) ||
                subjectCode.StartsWith("SLOT", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var nearby = lines
                .Where(line => IsNearby(subjectLine, line))
                .OrderBy(line => ProximityScore(subjectLine, line))
                .ToList();

            var classCandidate = nearby
                .SelectMany(line => ClassCodePattern.Matches(line.Text)
                    .Cast<Match>()
                    .Select(match => (
                        Line: line,
                        Raw: CompactCode(match.Value),
                        Code: NormalizeClassCode(match))))
                .Where(item => !string.Equals(item.Code, subjectCode, StringComparison.OrdinalIgnoreCase))
                .OrderBy(item => ProximityScore(subjectLine, item.Line))
                .FirstOrDefault();
            var classCode = classCandidate.Code ?? string.Empty;
            var rawClassCode = classCandidate.Raw ?? string.Empty;
            var room = nearby
                .SelectMany(line => RoomPattern.Matches(line.Text)
                    .Cast<Match>()
                    .Select(match => (Line: line, Room: NormalizeRoom(match.Value))))
                .OrderBy(item => ProximityScore(subjectLine, item.Line))
                .Select(item => item.Room)
                .FirstOrDefault() ?? string.Empty;
            var day = ParseDay(subjectLine.Text)
                ?? NearestDay(subjectLine, dayAnchors)
                ?? nearby.Select(line => ParseDay(line.Text)).FirstOrDefault(value => value is not null);
            var directSlot = ParseSlot(subjectLine.Text);
            var timeSlot = ParseTimeSlot(subjectLine.Text) is int directTimeSlot
                ? new DetectedTimeSlot(directTimeSlot, subjectLine.Text)
                : NearestTimeSlot(subjectLine, nearby);
            var nearbyExplicitSlot = nearby
                .Select(line => (Line: line, Slot: ParseSlot(line.Text)))
                .Where(item => item.Slot is not null)
                .OrderBy(item => ProximityScore(subjectLine, item.Line))
                .Select(item => item.Slot)
                .FirstOrDefault();
            var slot = directSlot
                ?? timeSlot?.Slot
                ?? nearbyExplicitSlot
                ?? NearestSlot(subjectLine, slotAnchors);
            var instructor = PickInstructor(nearby, subjectLine);
            var subjectName = PickSubjectName(
                nearby,
                subjectLine,
                subjectCode,
                classCode,
                room);

            var warnings = new List<string>();
            if (!string.Equals(rawSubjectCode, subjectCode, StringComparison.OrdinalIgnoreCase))
            {
                warnings.Add($"Đã tự sửa mã môn {rawSubjectCode} → {subjectCode}");
            }
            if (rawClassCode.Length > 0 &&
                !string.Equals(rawClassCode, classCode, StringComparison.OrdinalIgnoreCase))
            {
                warnings.Add($"Đã tự sửa mã lớp {rawClassCode} → {classCode}");
            }
            if (directSlot is null && timeSlot is not null && slot == timeSlot.Slot)
            {
                warnings.Add($"Đã tự điền Slot {timeSlot.Slot} từ giờ học");
            }
            if (instructor.Length > 0)
            {
                warnings.Add($"Đã tách giảng viên {instructor} khỏi tên môn");
            }
            if (classCode.Length == 0) warnings.Add("Chưa nhận diện được mã lớp");
            if (day is null) warnings.Add("Chưa xác định được thứ");
            if (slot is null) warnings.Add("Chưa xác định được slot");

            candidates.Add(new TimetableOcrCandidate(
                subjectCode,
                subjectName.Length == 0 ? subjectCode : subjectName,
                classCode,
                day,
                slot,
                room,
                instructor,
                Math.Clamp(subjectLine.Confidence, 0, 1),
                warnings));
        }

        return candidates
            .GroupBy(candidate => $"{candidate.SubjectCode}|{candidate.ClassCode}|{candidate.DayOfWeek}|{candidate.Slot}")
            .Select(group => group.OrderByDescending(candidate => candidate.Confidence).First())
            .ToList();
    }

    private static List<OcrLine> ReadLines(Page page)
    {
        var result = new List<OcrLine>();
        using var iterator = page.GetIterator();
        iterator.Begin();
        do
        {
            var text = iterator.GetText(PageIteratorLevel.TextLine)?.Trim();
            if (string.IsNullOrWhiteSpace(text) ||
                !iterator.TryGetBoundingBox(PageIteratorLevel.TextLine, out var bounds))
            {
                continue;
            }

            result.Add(new OcrLine(
                NormalizeWhitespace(text),
                bounds.X1,
                bounds.Y1,
                Math.Max(1, bounds.X2 - bounds.X1),
                Math.Max(1, bounds.Y2 - bounds.Y1),
                iterator.GetConfidence(PageIteratorLevel.TextLine) / 100f));
        }
        while (iterator.Next(PageIteratorLevel.TextLine));
        return result;
    }

    private static bool IsNearby(OcrLine source, OcrLine candidate)
    {
        var verticalDistance = Math.Abs(source.CenterY - candidate.CenterY);
        var horizontalOverlap = Math.Min(source.Right, candidate.Right) - Math.Max(source.X, candidate.X);
        var horizontalDistance = horizontalOverlap >= 0
            ? 0
            : Math.Min(Math.Abs(source.X - candidate.Right), Math.Abs(candidate.X - source.Right));
        return verticalDistance <= Math.Max(150, source.Height * 7) && horizontalDistance <= 360;
    }

    private static double ProximityScore(OcrLine source, OcrLine candidate) =>
        Math.Abs(source.CenterX - candidate.CenterX) +
        Math.Abs(source.CenterY - candidate.CenterY) * 0.35;

    private static int? NearestDay(OcrLine source, List<(OcrLine line, int? day)> anchors)
    {
        var anchor = anchors
            .Where(item => Math.Abs(item.line.CenterX - source.CenterX) <= Math.Max(180, source.Width * 2))
            .OrderBy(item => Math.Abs(item.line.CenterX - source.CenterX) + Math.Abs(item.line.CenterY - source.CenterY) * 0.15)
            .FirstOrDefault();
        return anchor.day;
    }

    private static int? NearestSlot(OcrLine source, List<(OcrLine line, int? slot)> anchors)
    {
        var anchor = anchors
            .Where(item => Math.Abs(item.line.CenterY - source.CenterY) <= Math.Max(160, source.Height * 7))
            .OrderBy(item => Math.Abs(item.line.CenterY - source.CenterY) + Math.Abs(item.line.CenterX - source.CenterX) * 0.1)
            .FirstOrDefault();
        return anchor.slot;
    }

    private static int? ParseDay(string raw)
    {
        var text = RemoveDiacritics(raw).ToUpperInvariant();
        var patterns = new (string Pattern, int Day)[]
        {
            (@"\b(MON|MONDAY|THU\s*2|T2)\b", 1),
            (@"\b(TUE|TUESDAY|THU\s*3|T3)\b", 2),
            (@"\b(WED|WEDNESDAY|THU\s*4|T4)\b", 3),
            (@"\b(THURSDAY|THU\s*5|T5|THU(?!\s*[2-7]))\b", 4),
            (@"\b(FRI|FRIDAY|THU\s*6|T6)\b", 5),
            (@"\b(SAT|SATURDAY|THU\s*7|T7)\b", 6),
            (@"\b(SUN|SUNDAY|CHU\s*NHAT|CN)\b", 7),
        };
        return patterns.FirstOrDefault(item => Regex.IsMatch(text, item.Pattern, RegexOptions.IgnoreCase)).Day is var day && day > 0
            ? day
            : null;
    }

    private static int? ParseSlot(string raw)
    {
        var match = SlotPattern.Match(RemoveDiacritics(raw));
        return match.Success && int.TryParse(match.Groups[1].Value, out var slot) ? slot : null;
    }

    private static int? ParseTimeSlot(string raw)
    {
        var match = TimePattern.Match(raw);
        if (!match.Success) return null;
        if (!int.TryParse(match.Groups[1].Value, out var hour) ||
            !int.TryParse(match.Groups[2].Value, out var minute))
        {
            return null;
        }
        var time = $"{hour}:{minute:00}";
        return time switch
        {
            "7:00" => 1,
            "9:30" => 2,
            "12:30" => 3,
            "15:00" => 4,
            "17:30" => 5,
            "20:00" => 6,
            "17:45" => 7,
            "19:30" => 8,
            _ => null,
        };
    }

    private static DetectedTimeSlot? NearestTimeSlot(
        OcrLine source,
        IEnumerable<OcrLine> lines)
    {
        return lines
            .Select(line => (Line: line, Slot: ParseTimeSlot(line.Text)))
            .Where(item => item.Slot is not null)
            .OrderBy(item => ProximityScore(source, item.Line))
            .Select(item => new DetectedTimeSlot(item.Slot!.Value, item.Line.Text))
            .FirstOrDefault();
    }

    private static string PickSubjectName(
        IEnumerable<OcrLine> lines,
        OcrLine subjectLine,
        string subjectCode,
        string classCode,
        string room)
    {
        return lines
            .Select(line => (line, text: line.Text.Trim()))
            .Where(item => item.text.Length >= 5)
            .Where(item =>
                Math.Abs(item.line.CenterX - subjectLine.CenterX) <=
                Math.Max(220, subjectLine.Width * 2.5))
            .Where(item => !SubjectCodePattern.IsMatch(item.text) && !ClassCodePattern.IsMatch(item.text))
            .Where(item => !RoomPattern.IsMatch(item.text))
            .Where(item => !InstructorPattern.IsMatch(item.text))
            .Where(item => !item.text.Contains(subjectCode, StringComparison.OrdinalIgnoreCase))
            .Where(item => classCode.Length == 0 || !item.text.Contains(classCode, StringComparison.OrdinalIgnoreCase))
            .Where(item => room.Length == 0 || !item.text.Contains(room, StringComparison.OrdinalIgnoreCase))
            .Where(item => ParseDay(item.text) is null && ParseSlot(item.text) is null && !TimePattern.IsMatch(item.text))
            .Where(item => item.text.Count(char.IsLetter) >= 4)
            .OrderBy(item => ProximityScore(subjectLine, item.line))
            .ThenByDescending(item => item.text.Length)
            .Select(item => item.text)
            .FirstOrDefault() ?? string.Empty;
    }

    private static string PickInstructor(
        IEnumerable<OcrLine> lines,
        OcrLine subjectLine)
    {
        return lines
            .Select(line => (line, match: InstructorPattern.Match(line.Text)))
            .Where(item => item.match.Success)
            .OrderBy(item => ProximityScore(subjectLine, item.line))
            .Select(item => item.match.Groups["name"].Value)
            .FirstOrDefault() ?? string.Empty;
    }

    private static string CompactCode(string raw) =>
        Regex.Replace(raw.ToUpperInvariant(), @"[^A-Z0-9]", string.Empty);

    private static string NormalizeSubjectCode(Match match)
    {
        var prefix = CompactCode(match.Groups["prefix"].Value);
        var number = NormalizeDigitLike(match.Groups["number"].Value);
        var suffix = CompactCode(match.Groups["suffix"].Value);
        if (prefix.Length == 5 && prefix.StartsWith("TI", StringComparison.Ordinal))
        {
            // The blue book icon next to a course is sometimes read as "TI".
            prefix = prefix[2..];
        }
        else if (prefix.Length == 4 && prefix[0] is 'I' or 'L')
        {
            prefix = prefix[1..];
        }
        return $"{prefix}{number}{suffix}";
    }

    private static string NormalizeClassCode(Match match) =>
        $"{CompactCode(match.Groups["prefix"].Value)}{NormalizeDigitLike(match.Groups["number"].Value)}";

    private static string NormalizeDigitLike(string raw)
    {
        var builder = new StringBuilder(raw.Length);
        foreach (var character in raw.ToUpperInvariant())
        {
            builder.Append(character switch
            {
                'I' or 'L' => '1',
                'O' => '0',
                'S' => '5',
                'B' => '8',
                'Z' => '2',
                'G' => '6',
                _ => character,
            });
        }
        return builder.ToString();
    }

    private static string NormalizeRoom(string raw) =>
        NormalizeWhitespace(Regex.Replace(raw.Trim(), @"^(PH[ÒO]NG|ROOM)\s*", string.Empty, RegexOptions.IgnoreCase))
            .ToUpperInvariant();

    private static string NormalizeWhitespace(string raw) =>
        Regex.Replace(raw, @"\s+", " ").Trim();

    private static string RemoveDiacritics(string raw)
    {
        var normalized = raw.Normalize(NormalizationForm.FormD);
        var builder = new StringBuilder(normalized.Length);
        foreach (var character in normalized)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(character) != UnicodeCategory.NonSpacingMark)
            {
                builder.Append(character == 'Đ' ? 'D' : character == 'đ' ? 'd' : character);
            }
        }
        return builder.ToString().Normalize(NormalizationForm.FormC);
    }
}

internal sealed record DetectedTimeSlot(int Slot, string Source);

public sealed record OcrLine(
    string Text,
    int X,
    int Y,
    int Width,
    int Height,
    float Confidence)
{
    public double CenterX => X + Width / 2d;
    public double CenterY => Y + Height / 2d;
    public int Right => X + Width;
}

public sealed record TimetableOcrCandidate(
    string SubjectCode,
    string SubjectName,
    string ClassCode,
    int? DayOfWeek,
    int? Slot,
    string Room,
    string Instructor,
    double Confidence,
    IReadOnlyList<string> Warnings);

public sealed record TimetableOcrResult(
    string RawText,
    double Confidence,
    IReadOnlyList<TimetableOcrCandidate> Candidates,
    IReadOnlyList<string> Warnings);
