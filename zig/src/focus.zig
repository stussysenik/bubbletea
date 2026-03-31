const std = @import("std");
const tea = @import("tea.zig");

/// Small utility for cycling focus across a fixed number of slots.
pub const FocusRing = struct {
    count: usize,
    index: usize = 0,

    /// Creates a ring with `count` focusable entries.
    pub fn init(count: usize) FocusRing {
        return .{ .count = count };
    }

    /// Returns the currently focused index when the ring is non-empty.
    pub fn current(self: *const FocusRing) ?usize {
        if (self.count == 0) return null;
        return self.index;
    }

    /// Returns true when the provided index is the active slot.
    pub fn isFocused(self: *const FocusRing, index: usize) bool {
        return self.count != 0 and self.index == index;
    }

    /// Updates the ring size and clamps focus into the new bounds.
    pub fn setCount(self: *FocusRing, count: usize) void {
        self.count = count;
        if (self.count == 0) {
            self.index = 0;
            return;
        }
        if (self.index >= self.count) {
            self.index = self.count - 1;
        }
    }

    /// Focuses an explicit slot when it is in range.
    pub fn focus(self: *FocusRing, index: usize) bool {
        if (self.count == 0 or index >= self.count or index == self.index) return false;
        self.index = index;
        return true;
    }

    /// Moves focus to the next slot, wrapping at the end.
    pub fn next(self: *FocusRing) bool {
        if (self.count <= 1) return false;
        self.index = (self.index + 1) % self.count;
        return true;
    }

    /// Moves focus to the previous slot, wrapping at the beginning.
    pub fn previous(self: *FocusRing) bool {
        if (self.count <= 1) return false;
        self.index = if (self.index == 0) self.count - 1 else self.index - 1;
        return true;
    }

    /// Applies standard focus-navigation keys.
    pub fn update(self: *FocusRing, key: tea.Key) bool {
        if (key.isCode(.tab) or key.isCode(.page_down)) return self.next();
        if (key.isCode(.shift_tab) or key.isCode(.page_up)) return self.previous();
        if (key.isCode(.home)) return self.focus(0);
        if (key.isCode(.end)) return self.focus(if (self.count == 0) 0 else self.count - 1);
        return false;
    }
};

test "focus ring wraps and clamps" {
    var ring = FocusRing.init(3);

    try std.testing.expectEqual(@as(?usize, 0), ring.current());
    try std.testing.expect(ring.next());
    try std.testing.expectEqual(@as(?usize, 1), ring.current());
    try std.testing.expect(ring.previous());
    try std.testing.expectEqual(@as(?usize, 0), ring.current());
    try std.testing.expect(ring.focus(2));
    try std.testing.expectEqual(@as(?usize, 2), ring.current());

    ring.setCount(1);
    try std.testing.expectEqual(@as(?usize, 0), ring.current());
}
