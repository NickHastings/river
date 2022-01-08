// This file is part of river, a dynamic tiling wayland compositor.
//
// Copyright 2020 The River Developers
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");

const server = &@import("../main.zig").server;

const Direction = @import("../command.zig").Direction;
const Error = @import("../command.zig").Error;
const Seat = @import("../Seat.zig");

/// Switch focus to the passed tags.
pub fn setFocusedTags(
    allocator: std.mem.Allocator,
    seat: *Seat,
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!void {
    const tags = try parseTags(allocator, args, out);
    if (seat.focused_output.pending.tags != tags) {
        seat.focused_output.previous_tags = seat.focused_output.pending.tags;
        seat.focused_output.pending.tags = tags;
        seat.focused_output.arrangeViews();
        seat.focus(null);
        server.root.startTransaction();
    }
}

/// Change focus to the tags by one tag.
pub fn cycleFocusedTags(
    _: std.mem.Allocator,
    seat: *Seat,
    args: []const [:0]const u8,
    _: *?[]const u8,
) Error!void {
    if (args.len < 3) return Error.NotEnoughArguments;
    if (args.len > 3) return Error.TooManyArguments;

    const direction = std.meta.stringToEnum(Direction, args[1]) orelse return Error.InvalidDirection;
    const n_tags: u32 = try std.fmt.parseInt(u32, args[2], 10);
    var tags = seat.focused_output.pending.tags;
    seat.focused_output.previous_tags = tags;

    var new_tags = tags;
    if (direction == Direction.next) {
        var i: u6 = 0;
        var mask: u32 = 1;
        while (i < (n_tags - 1)) : (i += 1) {
            mask <<= 1;
        }

        const wrap = ((tags & mask) != 0);

        // If highest bit (last tag) is set => unset it
        if (wrap) {
            tags ^= mask;
        }
        new_tags = (tags << 1);

        // If highest bit was set => set lowest bit to wrap to first tag
        if (wrap) {
            new_tags |= 0b1;
        }
    } else {
        const wrap = ((tags & 0b1) != 0);

        // If lowest bit is set (first tag) => unset it
        if (wrap) {
            tags ^= 0b1;
        }
        new_tags = (tags >> 1);

        // If lowest bit was set => set highest bit to wrap to last tag
        if (wrap) {
            var i: u6 = 0;
            var mask: u32 = 1;
            while (i < (n_tags - 1)) : (i += 1) {
                mask <<= 1;
            }
            new_tags |= mask;
        }
    }

    seat.focused_output.pending.tags = new_tags;
    seat.focused_output.arrangeViews();
    seat.focus(null);
    server.root.startTransaction();

    seat.focused_output.previous_tags = seat.focused_output.pending.tags;
}

/// Set the spawn tagmask
pub fn spawnTagmask(
    allocator: std.mem.Allocator,
    seat: *Seat,
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!void {
    const tags = try parseTags(allocator, args, out);
    seat.focused_output.spawn_tagmask = tags;
}

/// Set the tags of the focused view.
pub fn setViewTags(
    allocator: std.mem.Allocator,
    seat: *Seat,
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!void {
    const tags = try parseTags(allocator, args, out);
    if (seat.focused == .view) {
        const view = seat.focused.view;
        view.pending.tags = tags;
        seat.focus(null);
        view.applyPending();
    }
}

/// Toggle focus of the passsed tags.
pub fn toggleFocusedTags(
    allocator: std.mem.Allocator,
    seat: *Seat,
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!void {
    const tags = try parseTags(allocator, args, out);
    const output = seat.focused_output;
    const new_focused_tags = output.pending.tags ^ tags;
    if (new_focused_tags != 0) {
        output.previous_tags = output.pending.tags;
        output.pending.tags = new_focused_tags;
        output.arrangeViews();
        seat.focus(null);
        server.root.startTransaction();
    }
}

/// Toggle the passed tags of the focused view
pub fn toggleViewTags(
    allocator: std.mem.Allocator,
    seat: *Seat,
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!void {
    const tags = try parseTags(allocator, args, out);
    if (seat.focused == .view) {
        const new_tags = seat.focused.view.pending.tags ^ tags;
        if (new_tags != 0) {
            const view = seat.focused.view;
            view.pending.tags = new_tags;
            seat.focus(null);
            view.applyPending();
        }
    }
}

/// Switch focus to tags that were selected previously
pub fn focusPreviousTags(
    _: std.mem.Allocator,
    seat: *Seat,
    args: []const []const u8,
    _: *?[]const u8,
) Error!void {
    if (args.len > 1) return error.TooManyArguments;
    const previous_tags = seat.focused_output.previous_tags;
    if (seat.focused_output.pending.tags != previous_tags) {
        seat.focused_output.previous_tags = seat.focused_output.pending.tags;
        seat.focused_output.pending.tags = previous_tags;
        seat.focused_output.arrangeViews();
        seat.focus(null);
        server.root.startTransaction();
    }
}

/// Set the tags of the focused view to the tags that were selected previously
pub fn sendToPreviousTags(
    _: std.mem.Allocator,
    seat: *Seat,
    args: []const []const u8,
    _: *?[]const u8,
) Error!void {
    if (args.len > 1) return error.TooManyArguments;
    const previous_tags = seat.focused_output.previous_tags;
    if (seat.focused == .view) {
        const view = seat.focused.view;
        view.pending.tags = previous_tags;
        seat.focus(null);
        view.applyPending();
    }
}

fn parseTags(
    allocator: std.mem.Allocator,
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!u32 {
    if (args.len < 2) return Error.NotEnoughArguments;
    if (args.len > 2) return Error.TooManyArguments;

    const tags = try std.fmt.parseInt(u32, args[1], 10);

    if (tags == 0) {
        out.* = try std.fmt.allocPrint(allocator, "tags may not be 0", .{});
        return Error.Other;
    }

    return tags;
}
