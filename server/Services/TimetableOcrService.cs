using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using Tesseract;

namespace Attendance.Api.Services;

public sealed class TimetableOcrService(IWebHostEnvironment environment)
{
    private static readonly Regex SubjectCodePattern = new(
        @"\b[A-Z]{2,4}\s*[-–]?\s*\d{3}[A-Z]?\b",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);
    private static readonly Regex ClassCodePattern = new(
        @"\b[A-Z]{2,4}\s*[-–]?\s*\d{4,6}\b",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);
    private static readonly Regex RoomPattern = new(
        @"\b(?:(?:PH[ÒO]NG|ROOM)\s*)?(?:NVH|DE|BE|AL|P)\s*[-.]?\s*[A-Z]?\d{2,4}\b|\b(?:ONLINE|TRỰC\s*TUYẾN)\b",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);
    private static readonly Regex SlotPattern = new(
        @"\b(?:SLOT|CA|TI[EẾ]T)\s*[:#-]?\s*([1-8])\b",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);
    private static readonly Regex TimePattern = new(
        @"\b(0?7[:.]00|0?9[:.]30|12[:.]30|15[:.]00|17[:.]30|17[:.]45|19[:.]30|20[:.]00)\b",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

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
            var subjectCode = CompactCode(subjectMatch.Value);
            if (subjectCode.Length < 5 ||
                subjectCode.StartsWith("NVH", StringComparison.OrdinalIgnoreCase) ||
                subjectCode.StartsWith("ROOM", StringComparison.OrdinalIgnoreCase) ||
                subjectCode.StartsWith("SLOT", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var nearby = lines
                .Where(line => IsNearby(subjectLine, line))
                .OrderBy(line => Math.Abs(line.CenterY - subjectLine.CenterY))
                .ToList();
            var combined = string.Join(" | ", nearby.Select(line => line.Text));

            var classCode = ClassCodePattern.Matches(combined)
                .Select(match => CompactCode(match.Value))
                .FirstOrDefault(code => !string.Equals(code, subjectCode, StringComparison.OrdinalIgnoreCase))
                ?? string.Empty;
            var room = NormalizeRoom(RoomPattern.Match(combined).Value);
            var day = nearby.Select(line => ParseDay(line.Text)).FirstOrDefault(value => value is not null)
                ?? NearestDay(subjectLine, dayAnchors);
            var slot = nearby.Select(line => ParseSlot(line.Text)).FirstOrDefault(value => value is not null)
                ?? ParseTimeSlot(combined)
                ?? NearestSlot(subjectLine, slotAnchors);
            var subjectName = PickSubjectName(
                nearby,
                subjectLine,
                subjectCode,
                classCode,
                room);

            var warnings = new List<string>();
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
        var time = match.Groups[1].Value.Replace('.', ':').TrimStart('0');
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
            .Where(item => !item.text.Contains(subjectCode, StringComparison.OrdinalIgnoreCase))
            .Where(item => classCode.Length == 0 || !item.text.Contains(classCode, StringComparison.OrdinalIgnoreCase))
            .Where(item => room.Length == 0 || !item.text.Contains(room, StringComparison.OrdinalIgnoreCase))
            .Where(item => ParseDay(item.text) is null && ParseSlot(item.text) is null && !TimePattern.IsMatch(item.text))
            .Where(item => item.text.Count(char.IsLetter) >= 4)
            .OrderBy(item => Math.Abs(item.line.CenterY - subjectLine.CenterY))
            .ThenByDescending(item => item.text.Length)
            .Select(item => item.text)
            .FirstOrDefault() ?? string.Empty;
    }

    private static string CompactCode(string raw) =>
        Regex.Replace(raw.ToUpperInvariant(), @"[^A-Z0-9]", string.Empty);

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
    double Confidence,
    IReadOnlyList<string> Warnings);

public sealed record TimetableOcrResult(
    string RawText,
    double Confidence,
    IReadOnlyList<TimetableOcrCandidate> Candidates,
    IReadOnlyList<string> Warnings);
