const std = @import("std");

/// Returns the number of terminal cells used by one Unicode scalar.
pub fn scalarWidth(codepoint: u21) usize {
    if (isControl(codepoint) or isZeroWidth(codepoint)) return 0;
    if (isWide(codepoint)) return 2;
    return 1;
}

/// Returns the display width of one UTF-8 string in terminal cells.
///
/// This intentionally tracks simple grapheme clusters well enough for terminal
/// layout: combining marks extend the previous visible glyph, and ZWJ-linked
/// emoji sequences collapse to the width of the widest joined glyph.
pub fn displayWidth(text: []const u8) usize {
    var total: usize = 0;
    var cluster_width: usize = 0;
    var join_pending = false;
    var index: usize = 0;

    while (index < text.len) {
        const sequence_len = std.unicode.utf8ByteSequenceLength(text[index]) catch {
            total += 1;
            index += 1;
            continue;
        };
        if (index + sequence_len > text.len) {
            total += 1;
            break;
        }

        const codepoint = std.unicode.utf8Decode(text[index .. index + sequence_len]) catch {
            total += 1;
            index += sequence_len;
            continue;
        };

        const width = scalarWidth(codepoint);
        if (cluster_width == 0) {
            if (width == 0) {
                join_pending = codepoint == 0x200D;
                index += sequence_len;
                continue;
            }

            cluster_width = width;
            join_pending = codepoint == 0x200D;
            index += sequence_len;
            continue;
        }

        if (width == 0 or join_pending) {
            cluster_width = @max(cluster_width, width);
            join_pending = codepoint == 0x200D;
            index += sequence_len;
            continue;
        }

        total += cluster_width;
        cluster_width = width;
        join_pending = false;
        index += sequence_len;
    }

    return total + cluster_width;
}

// C0 and C1 controls should never consume visible terminal cells.
fn isControl(codepoint: u21) bool {
    return (codepoint <= 0x001F) or (codepoint >= 0x007F and codepoint <= 0x009F);
}

// Common zero-width marks and joiners used in terminal-facing Unicode text.
fn isZeroWidth(codepoint: u21) bool {
    return inRange(codepoint, 0x0300, 0x036F) or
        inRange(codepoint, 0x0483, 0x0489) or
        inRange(codepoint, 0x0591, 0x05BD) or
        codepoint == 0x05BF or
        inRange(codepoint, 0x05C1, 0x05C2) or
        inRange(codepoint, 0x05C4, 0x05C5) or
        codepoint == 0x05C7 or
        inRange(codepoint, 0x0610, 0x061A) or
        inRange(codepoint, 0x064B, 0x065F) or
        codepoint == 0x0670 or
        inRange(codepoint, 0x06D6, 0x06DD) or
        inRange(codepoint, 0x06DF, 0x06E4) or
        inRange(codepoint, 0x06E7, 0x06E8) or
        inRange(codepoint, 0x06EA, 0x06ED) or
        codepoint == 0x0711 or
        inRange(codepoint, 0x0730, 0x074A) or
        inRange(codepoint, 0x07A6, 0x07B0) or
        inRange(codepoint, 0x07EB, 0x07F3) or
        codepoint == 0x07FD or
        inRange(codepoint, 0x0816, 0x0819) or
        inRange(codepoint, 0x081B, 0x0823) or
        inRange(codepoint, 0x0825, 0x0827) or
        inRange(codepoint, 0x0829, 0x082D) or
        inRange(codepoint, 0x0859, 0x085B) or
        inRange(codepoint, 0x0898, 0x089F) or
        inRange(codepoint, 0x08CA, 0x0902) or
        codepoint == 0x093A or
        codepoint == 0x093C or
        inRange(codepoint, 0x0941, 0x0948) or
        codepoint == 0x094D or
        inRange(codepoint, 0x0951, 0x0957) or
        inRange(codepoint, 0x0962, 0x0963) or
        codepoint == 0x0981 or
        codepoint == 0x09BC or
        codepoint == 0x09C1 or
        codepoint == 0x09C4 or
        codepoint == 0x09CD or
        inRange(codepoint, 0x09E2, 0x09E3) or
        codepoint == 0x0A01 or
        codepoint == 0x0A02 or
        codepoint == 0x0A3C or
        codepoint == 0x0A41 or
        inRange(codepoint, 0x0A47, 0x0A48) or
        inRange(codepoint, 0x0A4B, 0x0A4D) or
        inRange(codepoint, 0x0A51, 0x0A51) or
        codepoint == 0x0A70 or
        codepoint == 0x0A71 or
        inRange(codepoint, 0x0A75, 0x0A75) or
        inRange(codepoint, 0x0A81, 0x0A82) or
        codepoint == 0x0ABC or
        inRange(codepoint, 0x0AC1, 0x0AC5) or
        codepoint == 0x0AC7 or
        codepoint == 0x0AC8 or
        codepoint == 0x0ACD or
        inRange(codepoint, 0x0AE2, 0x0AE3) or
        inRange(codepoint, 0x0AFA, 0x0AFF) or
        codepoint == 0x0B01 or
        codepoint == 0x0B3C or
        codepoint == 0x0B3F or
        inRange(codepoint, 0x0B41, 0x0B44) or
        codepoint == 0x0B4D or
        codepoint == 0x0B55 or
        codepoint == 0x0B56 or
        inRange(codepoint, 0x0B62, 0x0B63) or
        codepoint == 0x0B82 or
        codepoint == 0x0BC0 or
        codepoint == 0x0BCD or
        codepoint == 0x0C00 or
        inRange(codepoint, 0x0C04, 0x0C04) or
        inRange(codepoint, 0x0C3E, 0x0C40) or
        inRange(codepoint, 0x0C46, 0x0C48) or
        inRange(codepoint, 0x0C4A, 0x0C4D) or
        inRange(codepoint, 0x0C55, 0x0C56) or
        inRange(codepoint, 0x0C62, 0x0C63) or
        inRange(codepoint, 0x0C81, 0x0C81) or
        codepoint == 0x0CBC or
        codepoint == 0x0CBF or
        codepoint == 0x0CC6 or
        inRange(codepoint, 0x0CCC, 0x0CCD) or
        inRange(codepoint, 0x0CE2, 0x0CE3) or
        inRange(codepoint, 0x0D00, 0x0D01) or
        inRange(codepoint, 0x0D3B, 0x0D3C) or
        inRange(codepoint, 0x0D41, 0x0D44) or
        codepoint == 0x0D4D or
        inRange(codepoint, 0x0D62, 0x0D63) or
        codepoint == 0x0D81 or
        codepoint == 0x0DCA or
        inRange(codepoint, 0x0DD2, 0x0DD4) or
        codepoint == 0x0DD6 or
        codepoint == 0x0E31 or
        inRange(codepoint, 0x0E34, 0x0E3A) or
        inRange(codepoint, 0x0E47, 0x0E4E) or
        codepoint == 0x0EB1 or
        inRange(codepoint, 0x0EB4, 0x0EBC) or
        inRange(codepoint, 0x0EC8, 0x0ECE) or
        inRange(codepoint, 0x0F18, 0x0F19) or
        codepoint == 0x0F35 or
        codepoint == 0x0F37 or
        codepoint == 0x0F39 or
        inRange(codepoint, 0x0F71, 0x0F7E) or
        inRange(codepoint, 0x0F80, 0x0F84) or
        inRange(codepoint, 0x0F86, 0x0F87) or
        inRange(codepoint, 0x0F8D, 0x0F97) or
        inRange(codepoint, 0x0F99, 0x0FBC) or
        codepoint == 0x0FC6 or
        inRange(codepoint, 0x102D, 0x1030) or
        inRange(codepoint, 0x1032, 0x1037) or
        inRange(codepoint, 0x1039, 0x103A) or
        inRange(codepoint, 0x103D, 0x103E) or
        inRange(codepoint, 0x1058, 0x1059) or
        inRange(codepoint, 0x105E, 0x1060) or
        inRange(codepoint, 0x1071, 0x1074) or
        codepoint == 0x1082 or
        codepoint == 0x1085 or
        codepoint == 0x1086 or
        codepoint == 0x108D or
        codepoint == 0x109D or
        inRange(codepoint, 0x135D, 0x135F) or
        inRange(codepoint, 0x1712, 0x1714) or
        inRange(codepoint, 0x1732, 0x1734) or
        inRange(codepoint, 0x1752, 0x1753) or
        inRange(codepoint, 0x1772, 0x1773) or
        inRange(codepoint, 0x17B4, 0x17B5) or
        inRange(codepoint, 0x17B7, 0x17BD) or
        codepoint == 0x17C6 or
        inRange(codepoint, 0x17C9, 0x17D3) or
        codepoint == 0x17DD or
        inRange(codepoint, 0x180B, 0x180D) or
        codepoint == 0x180F or
        inRange(codepoint, 0x1885, 0x1886) or
        codepoint == 0x18A9 or
        inRange(codepoint, 0x1920, 0x1922) or
        inRange(codepoint, 0x1927, 0x1928) or
        codepoint == 0x1932 or
        inRange(codepoint, 0x1939, 0x193B) or
        inRange(codepoint, 0x1A17, 0x1A18) or
        codepoint == 0x1A1B or
        codepoint == 0x1A56 or
        inRange(codepoint, 0x1A58, 0x1A5E) or
        codepoint == 0x1A60 or
        codepoint == 0x1A62 or
        inRange(codepoint, 0x1A65, 0x1A6C) or
        inRange(codepoint, 0x1A73, 0x1A7C) or
        codepoint == 0x1A7F or
        inRange(codepoint, 0x1AB0, 0x1ACE) or
        inRange(codepoint, 0x1B00, 0x1B03) or
        codepoint == 0x1B34 or
        codepoint == 0x1B36 or
        inRange(codepoint, 0x1B3C, 0x1B3D) or
        codepoint == 0x1B42 or
        inRange(codepoint, 0x1B6B, 0x1B73) or
        inRange(codepoint, 0x1B80, 0x1B81) or
        codepoint == 0x1BA2 or
        inRange(codepoint, 0x1BA5, 0x1BA7) or
        inRange(codepoint, 0x1BAE, 0x1BAF) or
        inRange(codepoint, 0x1BE6, 0x1BE6) or
        inRange(codepoint, 0x1BE8, 0x1BE9) or
        codepoint == 0x1BED or
        inRange(codepoint, 0x1BEF, 0x1BF1) or
        inRange(codepoint, 0x1C2C, 0x1C33) or
        inRange(codepoint, 0x1C36, 0x1C37) or
        inRange(codepoint, 0x1CD0, 0x1CD2) or
        inRange(codepoint, 0x1CD4, 0x1CE0) or
        inRange(codepoint, 0x1CE2, 0x1CE8) or
        codepoint == 0x1CED or
        codepoint == 0x1CF4 or
        codepoint == 0x1CF8 or
        codepoint == 0x1CF9 or
        inRange(codepoint, 0x1DC0, 0x1DFF) or
        inRange(codepoint, 0x200B, 0x200F) or
        inRange(codepoint, 0x202A, 0x202E) or
        codepoint == 0x2060 or
        inRange(codepoint, 0x2061, 0x2064) or
        inRange(codepoint, 0x2066, 0x206F) or
        codepoint == 0x20D0 or
        inRange(codepoint, 0x20D1, 0x20F0) or
        codepoint == 0x20E3 or
        inRange(codepoint, 0x2CEF, 0x2CF1) or
        codepoint == 0x2D7F or
        inRange(codepoint, 0x2DE0, 0x2DFF) or
        inRange(codepoint, 0x302A, 0x302F) or
        inRange(codepoint, 0x3099, 0x309A) or
        inRange(codepoint, 0xA66F, 0xA672) or
        inRange(codepoint, 0xA674, 0xA67D) or
        inRange(codepoint, 0xA69E, 0xA69F) or
        inRange(codepoint, 0xA6F0, 0xA6F1) or
        inRange(codepoint, 0xA802, 0xA802) or
        codepoint == 0xA806 or
        codepoint == 0xA80B or
        inRange(codepoint, 0xA825, 0xA826) or
        codepoint == 0xA82C or
        inRange(codepoint, 0xA8C4, 0xA8C5) or
        inRange(codepoint, 0xA8E0, 0xA8F1) or
        inRange(codepoint, 0xA8FF, 0xA8FF) or
        inRange(codepoint, 0xA926, 0xA92D) or
        inRange(codepoint, 0xA947, 0xA951) or
        inRange(codepoint, 0xA980, 0xA982) or
        codepoint == 0xA9B3 or
        inRange(codepoint, 0xA9B6, 0xA9B9) or
        codepoint == 0xA9BC or
        codepoint == 0xA9E5 or
        inRange(codepoint, 0xAA29, 0xAA2E) or
        inRange(codepoint, 0xAA31, 0xAA32) or
        inRange(codepoint, 0xAA35, 0xAA36) or
        codepoint == 0xAA43 or
        codepoint == 0xAA4C or
        codepoint == 0xAA7C or
        codepoint == 0xAAB0 or
        inRange(codepoint, 0xAAB2, 0xAAB4) or
        inRange(codepoint, 0xAAB7, 0xAAB8) or
        inRange(codepoint, 0xAABE, 0xAABF) or
        codepoint == 0xAAC1 or
        codepoint == 0xAAEC or
        codepoint == 0xAAED or
        codepoint == 0xAAF6 or
        inRange(codepoint, 0xABE5, 0xABE5) or
        codepoint == 0xABE8 or
        codepoint == 0xABED or
        codepoint == 0xFB1E or
        inRange(codepoint, 0xFE00, 0xFE0F) or
        inRange(codepoint, 0xFE20, 0xFE2F) or
        inRange(codepoint, 0x1F3FB, 0x1F3FF) or
        codepoint == 0x200D or
        inRange(codepoint, 0xE0100, 0xE01EF);
}

// Broad East Asian width and emoji ranges treated as double-width in a
// terminal grid.
fn isWide(codepoint: u21) bool {
    return inRange(codepoint, 0x1100, 0x115F) or
        codepoint == 0x2329 or
        codepoint == 0x232A or
        inRange(codepoint, 0x2E80, 0x303E) or
        inRange(codepoint, 0x3040, 0xA4CF) or
        inRange(codepoint, 0xAC00, 0xD7A3) or
        inRange(codepoint, 0xF900, 0xFAFF) or
        inRange(codepoint, 0xFE10, 0xFE19) or
        inRange(codepoint, 0xFE30, 0xFE6B) or
        inRange(codepoint, 0xFF01, 0xFF60) or
        inRange(codepoint, 0xFFE0, 0xFFE6) or
        inRange(codepoint, 0x1F300, 0x1FAFF) or
        inRange(codepoint, 0x20000, 0x2FFFD) or
        inRange(codepoint, 0x30000, 0x3FFFD);
}

fn inRange(codepoint: u21, start: u21, end: u21) bool {
    return codepoint >= start and codepoint <= end;
}

test "display width counts wide and combining glyphs" {
    try std.testing.expectEqual(@as(usize, 3), displayWidth("a漢"));
    try std.testing.expectEqual(@as(usize, 1), displayWidth("e\u{0301}"));
    try std.testing.expectEqual(@as(usize, 2), displayWidth("👩‍💻"));
}
