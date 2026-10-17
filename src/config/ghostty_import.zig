//! Witty: one-time import of an existing Ghostty configuration.
//!
//! Witty keeps its config in its own directories (`build_config.user_dir`),
//! so it never reads Ghostty's files and stock Ghostty never meets Witty-only
//! syntax such as `altscreen:` keybinds, which fail its config validation.
//! The first time Witty loads its default config and finds none, this copies
//! Ghostty's config into Witty's directories so an existing setup carries
//! over.
//!
//! The import:
//!
//!   - runs only while no Witty default config file exists and at least one
//!     Ghostty default config file does. Once Witty has a config (imported,
//!     written by hand, or the generated template) it does nothing, so it is
//!     safe to run on every load;
//!   - only reads Ghostty's files. It never modifies, moves or deletes them;
//!   - only writes inside Witty's directories, and never overwrites a file
//!     that already exists there;
//!   - follows `config-file` includes written as relative paths and copies
//!     each one to the same relative location, which is where the copied
//!     config looks for it. Absolute and `~/` includes name the same file for
//!     both apps, so they are not copied, only logged;
//!   - copies the user theme directory (`themes/`) so `theme = <name>` keeps
//!     resolving;
//!   - logs each file it copies. Errors are logged and never stop Witty from
//!     loading its config.
const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const build_config = @import("../build_config.zig");
const internal_os = @import("../os/main.zig");
const global = @import("../global.zig");
const whitespace = @import("../cli.zig").args.whitespace;

const log = std.log.scoped(.config);

/// Upstream Ghostty's per-user directory names: where the import reads.
const ghostty_dir = struct {
    const xdg = "ghostty";
    const macos = "com.mitchellh.ghostty";
};

/// The default config file names, in the order both apps load them.
const config_names = [_][]const u8{ "config", "config.ghostty" };

/// The directory under the XDG config directory that holds user themes.
const themes_dir = "themes";

/// The largest file the import copies. Config files and themes are a few
/// kilobytes; anything far bigger is not a config file.
const max_file_size = 4 * 1024 * 1024;

/// A Ghostty config directory and the Witty directory it is imported into.
pub const Location = struct {
    /// Absolute path of Ghostty's directory. It is only ever read.
    ghostty: []const u8,

    /// Absolute path of the matching Witty directory.
    witty: []const u8,

    /// True for the XDG config directory, which also holds user themes.
    themes: bool = false,
};

/// Import Ghostty's config into Witty's default config directories if
/// Witty has no config yet. This never fails: problems are logged and
/// loading carries on with whatever config Witty has.
pub fn importDefault(alloc_gpa: Allocator) void {
    var arena_state: std.heap.ArenaAllocator = .init(alloc_gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var environ_map = global.environMap() catch |err| {
        log.warn("Ghostty config import skipped, no environment err={}", .{err});
        return;
    };
    defer environ_map.deinit();

    const locations = defaultLocations(arena, &environ_map) catch |err| {
        log.warn("Ghostty config import skipped, no config directory err={}", .{err});
        return;
    };

    _ = importLocations(arena, global.io(), &environ_map, locations) catch |err| {
        log.warn("Ghostty config import failed err={}", .{err});
    };
}

/// Ghostty's default config directories paired with Witty's: the XDG
/// config directory everywhere, plus Application Support on macOS.
fn defaultLocations(
    arena: Allocator,
    environ_map: *const std.process.Environ.Map,
) ![]const Location {
    const io = global.io();
    var list: std.ArrayList(Location) = .empty;
    try list.append(arena, .{
        .ghostty = try internal_os.xdg.config(io, arena, environ_map, .{
            .subdir = ghostty_dir.xdg,
        }),
        .witty = try internal_os.xdg.config(io, arena, environ_map, .{
            .subdir = build_config.user_dir.xdg,
        }),
        .themes = true,
    });

    if (comptime builtin.os.tag == .macos) {
        // Both directories sit directly under Application Support.
        const witty = try internal_os.macos.appSupportDir(arena, "");
        const base = std.fs.path.dirname(witty) orelse return error.AppleAPIFailed;
        try list.append(arena, .{
            .ghostty = try std.fs.path.join(arena, &.{ base, ghostty_dir.macos }),
            .witty = witty,
        });
    }

    return list.items;
}

/// Import from each location's Ghostty directory into its Witty directory.
/// Returns the number of files copied, which is zero when Witty already
/// has a config or Ghostty has none.
pub fn importLocations(
    arena: Allocator,
    io: std.Io,
    environ_map: *const std.process.Environ.Map,
    raw_locations: []const Location,
) Allocator.Error!usize {
    const locations = try arena.alloc(Location, raw_locations.len);
    for (raw_locations, locations) |raw, *loc| loc.* = .{
        .ghostty = try std.fs.path.resolve(arena, &.{raw.ghostty}),
        .witty = try std.fs.path.resolve(arena, &.{raw.witty}),
        .themes = raw.themes,
    };

    // Witty already has a config. Any file counts, even an empty one or a
    // dangling symlink: it is the user's, and an import would shadow it.
    for (locations) |loc| {
        for (config_names) |name| {
            const path = try std.fs.path.join(arena, &.{ loc.witty, name });
            if (exists(io, path)) return 0;
        }
    }

    const ghostty_has_config = found: {
        for (locations) |loc| {
            for (config_names) |name| {
                const path = try std.fs.path.join(arena, &.{ loc.ghostty, name });
                if (isFile(io, path)) break :found true;
            }
        }
        break :found false;
    };
    if (!ghostty_has_config) return 0;

    var importer: Importer = .{
        .arena = arena,
        .io = io,
        .environ_map = environ_map,
    };
    for (locations) |loc| {
        if (loc.themes) try importer.copyThemes(loc);
        for (config_names) |name| {
            const src = try std.fs.path.join(arena, &.{ loc.ghostty, name });
            if (!isFile(io, src)) continue;
            const dst = try std.fs.path.join(arena, &.{ loc.witty, name });
            try importer.copyTree(loc, src, dst);
        }
    }

    if (importer.copied > 0) log.info(
        "imported {d} Ghostty config file(s); Witty now reads its own copies",
        .{importer.copied},
    );
    return importer.copied;
}

const Importer = struct {
    arena: Allocator,
    io: std.Io,
    environ_map: *const std.process.Environ.Map,

    /// Destinations already handled, which also stops include cycles.
    seen: std.StringHashMapUnmanaged(void) = .empty,

    /// The number of files copied.
    copied: usize = 0,

    /// Copy the config file `src` to `dst`. The relative includes it names
    /// are copied first, so a file is written after the files it includes.
    fn copyTree(
        self: *Importer,
        loc: Location,
        src: []const u8,
        dst: []const u8,
    ) Allocator.Error!void {
        if (try self.seen.fetchPut(self.arena, dst, {}) != null) return;
        if (exists(self.io, dst)) {
            log.info("kept existing {s}, did not import {s}", .{ dst, src });
            return;
        }

        const stat = std.Io.Dir.cwd().statFile(self.io, src, .{}) catch |err| {
            log.warn("could not import {s} err={}", .{ src, err });
            return;
        };
        if (stat.kind != .file) {
            log.warn("could not import {s}: not a regular file", .{src});
            return;
        }
        const content = std.Io.Dir.cwd().readFileAlloc(
            self.io,
            src,
            self.arena,
            .limited(max_file_size),
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                log.warn("could not import {s} err={}", .{ src, err });
                return;
            },
        };

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const include = parseInclude(line) orelse continue;
            try self.copyInclude(loc, src, dst, include);
        }

        self.write(src, dst, content, stat.permissions);
    }

    /// Handle one `config-file` include of `src`, whose copy is `dst`.
    fn copyInclude(
        self: *Importer,
        loc: Location,
        src: []const u8,
        dst: []const u8,
        include: Include,
    ) Allocator.Error!void {
        // Absolute and home-relative paths name the same file for both
        // apps, so the copied config keeps reading it where it is.
        if (std.fs.path.isAbsolute(include.path) or
            std.mem.startsWith(u8, include.path, "~/"))
        {
            try self.logShared(loc, src, include.path);
            return;
        }

        // Where the copy of `dst` will look for it. A path that climbs out
        // of the directory (`../shared.conf`) is not Witty's to write.
        const include_dst = try std.fs.path.resolve(self.arena, &.{
            std.fs.path.dirname(dst).?,
            include.path,
        });
        if (!isWithin(include_dst, loc.witty)) {
            log.info(
                "{s} includes {s}, which is outside the config directory; not copied",
                .{ src, include.path },
            );
            return;
        }

        // Where Ghostty reads it: relative to the including file, through
        // symlinks, as `Path.expand` resolves it.
        const joined = try std.fs.path.join(self.arena, &.{
            std.fs.path.dirname(src).?,
            include.path,
        });
        const include_src = std.Io.Dir.cwd().realPathFileAlloc(
            self.io,
            joined,
            self.arena,
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                if (!include.optional) log.warn(
                    "{s} includes {s}, which could not be read; nothing to import err={}",
                    .{ src, include.path, err },
                );
                return;
            },
        };

        try self.copyTree(loc, include_src, include_dst);
    }

    /// Log an include that names its file by absolute or `~/` path. Both
    /// apps read that one file, which matters when it lives in Ghostty's
    /// config directory: Witty keeps sharing it.
    fn logShared(
        self: *Importer,
        loc: Location,
        src: []const u8,
        path: []const u8,
    ) Allocator.Error!void {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const expanded = if (std.mem.startsWith(u8, path, "~/"))
            internal_os.expandHome(self.io, self.environ_map, path, &buf) catch path
        else
            path;
        const normalized = try std.fs.path.resolve(self.arena, &.{expanded});

        if (isWithin(normalized, loc.ghostty)) {
            log.warn(
                "{s} includes {s} by absolute path, so Witty keeps reading Ghostty's file; " ++
                    "copy it into {s} and point the include there to stop sharing it",
                .{ src, path, loc.witty },
            );
        } else {
            log.info("{s} includes {s} by absolute path; not copied", .{ src, path });
        }
    }

    /// Copy Ghostty's user themes so `theme = <name>` keeps resolving.
    fn copyThemes(self: *Importer, loc: Location) Allocator.Error!void {
        const src_dir = try std.fs.path.join(self.arena, &.{ loc.ghostty, themes_dir });
        var dir = std.Io.Dir.openDirAbsolute(self.io, src_dir, .{ .iterate = true }) catch return;
        defer dir.close(self.io);

        var it = dir.iterate();
        while (it.next(self.io) catch |err| {
            log.warn("could not list {s} err={}", .{ src_dir, err });
            return;
        }) |entry| {
            switch (entry.kind) {
                .file, .sym_link => {},
                else => continue,
            }
            if (entry.name.len == 0 or entry.name[0] == '.') continue;

            const src = try std.fs.path.join(self.arena, &.{ src_dir, entry.name });
            const dst = try std.fs.path.join(self.arena, &.{ loc.witty, themes_dir, entry.name });
            try self.copyTree(loc, src, dst);
        }
    }

    /// Create `dst` holding `content` with `permissions`. An existing file
    /// is never replaced.
    fn write(
        self: *Importer,
        src: []const u8,
        dst: []const u8,
        content: []const u8,
        permissions: std.Io.File.Permissions,
    ) void {
        if (std.fs.path.dirname(dst)) |dir| {
            std.Io.Dir.cwd().createDirPath(self.io, dir) catch |err| {
                log.warn("could not import {s}: creating {s} failed err={}", .{ src, dir, err });
                return;
            };
        }

        const file = std.Io.Dir.createFileAbsolute(self.io, dst, .{
            .exclusive = true,
            .permissions = permissions,
        }) catch |err| {
            switch (err) {
                error.PathAlreadyExists => log.info(
                    "kept existing {s}, did not import {s}",
                    .{ dst, src },
                ),
                else => log.warn(
                    "could not import {s}: creating {s} failed err={}",
                    .{ src, dst, err },
                ),
            }
            return;
        };
        defer file.close(self.io);

        file.writeStreamingAll(self.io, content) catch |err| {
            log.warn("could not import {s}: writing {s} failed err={}", .{ src, dst, err });
            std.Io.Dir.deleteFileAbsolute(self.io, dst) catch {};
            return;
        };

        self.copied += 1;
        log.info("imported Ghostty config {s} -> {s}", .{ src, dst });
    }
};

const Include = struct {
    path: []const u8,
    optional: bool,
};

/// The include on a `config-file = <path>` line, or null for any other
/// line. This follows `cli.args.LineIterator` and then `Path.parse`: a
/// trimmed key and value, one pair of quotes, then an optional `?` prefix
/// and one more pair of quotes.
fn parseInclude(raw: []const u8) ?Include {
    const line = std.mem.trim(u8, raw, whitespace ++ "\r");
    if (line.len == 0 or line[0] == '#') return null;
    const eql = std.mem.indexOfScalar(u8, line, '=') orelse return null;
    const key = std.mem.trim(u8, line[0..eql], whitespace);
    if (!std.mem.eql(u8, key, "config-file")) return null;

    var value = unquote(std.mem.trim(u8, line[eql + 1 ..], whitespace));
    const optional = value.len > 0 and value[0] == '?';
    if (optional) value = unquote(value[1..]);
    if (value.len == 0) return null;
    return .{ .path = value, .optional = optional };
}

fn unquote(value: []const u8) []const u8 {
    if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"')
        return value[1 .. value.len - 1];
    return value;
}

/// True if anything is at `path`, including a dangling symlink.
fn exists(io: std.Io, path: []const u8) bool {
    _ = std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false }) catch return false;
    return true;
}

/// True if `path` is a regular file or a symlink to one.
fn isFile(io: std.Io, path: []const u8) bool {
    const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return stat.kind == .file;
}

/// True if the normalized absolute `path` is `root` or inside it.
fn isWithin(path: []const u8, root: []const u8) bool {
    if (!std.mem.startsWith(u8, path, root)) return false;
    return path.len == root.len or path[root.len] == std.fs.path.sep;
}

// ─── Tests ───────────────────────────────────────────────────────────────

const testing = std.testing;

/// A temporary directory holding `ghostty/` and `witty/` for one test.
const TestDirs = struct {
    tmp: testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    root: []const u8,

    fn init() !TestDirs {
        var tmp = testing.tmpDir(.{});
        errdefer tmp.cleanup();
        var arena: std.heap.ArenaAllocator = .init(testing.allocator);
        errdefer arena.deinit();
        try tmp.dir.createDirPath(testing.io, "ghostty");
        const root = try tmp.dir.realPathFileAlloc(testing.io, ".", arena.allocator());
        return .{ .tmp = tmp, .arena = arena, .root = root };
    }

    fn deinit(self: *TestDirs) void {
        self.arena.deinit();
        self.tmp.cleanup();
    }

    fn path(self: *TestDirs, sub_path: []const u8) ![]const u8 {
        return std.fs.path.join(self.arena.allocator(), &.{ self.root, sub_path });
    }

    fn location(self: *TestDirs, ghostty: []const u8, witty: []const u8) !Location {
        return .{ .ghostty = try self.path(ghostty), .witty = try self.path(witty), .themes = true };
    }

    fn write(self: *TestDirs, sub_path: []const u8, data: []const u8) !void {
        if (std.fs.path.dirname(sub_path)) |dir| try self.tmp.dir.createDirPath(testing.io, dir);
        try self.tmp.dir.writeFile(testing.io, .{ .sub_path = sub_path, .data = data });
    }

    fn read(self: *TestDirs, sub_path: []const u8) ![]const u8 {
        return self.tmp.dir.readFileAlloc(testing.io, sub_path, self.arena.allocator(), .limited(1 << 20));
    }

    fn missing(self: *TestDirs, sub_path: []const u8) !void {
        try testing.expectError(error.FileNotFound, self.tmp.dir.statFile(testing.io, sub_path, .{}));
    }

    fn import(self: *TestDirs, locations: []const Location) !usize {
        const alloc = self.arena.allocator();
        var environ_map: std.process.Environ.Map = .init(alloc);
        try environ_map.put("HOME", self.root);
        return importLocations(alloc, testing.io, &environ_map, locations);
    }
};

test "ghostty import: no Ghostty config means no import" {
    var dirs: TestDirs = try .init();
    defer dirs.deinit();
    // A theme alone is not a config.
    try dirs.write("ghostty/themes/Mine", "background = #000000\n");

    try testing.expectEqual(0, try dirs.import(&.{try dirs.location("ghostty", "witty")}));
    try dirs.missing("witty");
}

test "ghostty import: an existing Witty config is never overwritten" {
    var dirs: TestDirs = try .init();
    defer dirs.deinit();
    try dirs.write("ghostty/config", "font-size = 13\nconfig-file = keys.conf\n");
    try dirs.write("ghostty/keys.conf", "keybind = ctrl+a=text:ghostty\n");
    try dirs.write("ghostty-support/config", "font-size = 14\n");

    // A config in any Witty location, even an empty one, stops the import.
    try dirs.write("witty-support/config.ghostty", "");
    const locations = [_]Location{
        try dirs.location("ghostty", "witty"),
        try dirs.location("ghostty-support", "witty-support"),
    };
    try testing.expectEqual(0, try dirs.import(&locations));
    try dirs.missing("witty");
    try testing.expectEqualStrings("", try dirs.read("witty-support/config.ghostty"));

    // Without a Witty config the import runs, but keeps Witty's own copy
    // of an include.
    try dirs.write("witty/keys.conf", "keybind = ctrl+a=text:witty\n");
    try testing.expectEqual(1, try dirs.import(&.{try dirs.location("ghostty", "witty")}));
    try testing.expectEqualStrings("font-size = 13\nconfig-file = keys.conf\n", try dirs.read("witty/config"));
    try testing.expectEqualStrings("keybind = ctrl+a=text:witty\n", try dirs.read("witty/keys.conf"));
}

test "ghostty import: included files are copied" {
    var dirs: TestDirs = try .init();
    defer dirs.deinit();
    const config =
        \\font-size = 13
        \\config-file = keys.conf
        \\  config-file  =  "?sub/optional.conf"
        \\config-file = ?missing.conf
        \\# config-file = commented.conf
        \\config-file = ../outside.conf
        \\config-file = ~/home.conf
        \\theme = Mine
        \\
    ;
    try dirs.write("ghostty/config", config);
    try dirs.write("ghostty/keys.conf", "keybind = altscreen:super+d=text:\\x02%\nconfig-file = nested/deep.conf\n");
    try dirs.write("ghostty/nested/deep.conf", "font-thicken = true\nconfig-file = ../keys.conf\n");
    try dirs.write("ghostty/sub/optional.conf", "font-size = 14\n");
    try dirs.write("ghostty/commented.conf", "font-size = 15\n");
    try dirs.write("ghostty/themes/Mine", "background = #000000\n");
    try dirs.write("outside.conf", "font-size = 16\n");
    try dirs.write("home.conf", "font-size = 17\n");

    // config, keys.conf, nested/deep.conf, sub/optional.conf, themes/Mine.
    try testing.expectEqual(5, try dirs.import(&.{try dirs.location("ghostty", "witty")}));

    try testing.expectEqualStrings(config, try dirs.read("witty/config"));
    try testing.expectEqualStrings(try dirs.read("ghostty/keys.conf"), try dirs.read("witty/keys.conf"));
    try testing.expectEqualStrings(try dirs.read("ghostty/nested/deep.conf"), try dirs.read("witty/nested/deep.conf"));
    try testing.expectEqualStrings("font-size = 14\n", try dirs.read("witty/sub/optional.conf"));
    try testing.expectEqualStrings("background = #000000\n", try dirs.read("witty/themes/Mine"));

    // Commented out, missing, or reached through `..` or `~/`: not copied.
    try dirs.missing("witty/commented.conf");
    try dirs.missing("witty/missing.conf");
    try dirs.missing("witty/outside.conf");
    try dirs.missing("witty/home.conf");
}

test "ghostty import: never writes outside Witty's directory" {
    var dirs: TestDirs = try .init();
    defer dirs.deinit();
    // Ghostty's directory is a symlink, as dotfile managers set it up, so
    // `..` reaches a different place from Ghostty's side than from Witty's.
    try dirs.write("dotfiles/ghostty/config", "config-file = ../outside.conf\n");
    try dirs.write("dotfiles/outside.conf", "font-size = 16\n");
    try dirs.tmp.dir.symLink(testing.io, "dotfiles/ghostty", "linked", .{ .is_directory = true });

    try testing.expectEqual(1, try dirs.import(&.{try dirs.location("linked", "witty")}));
    try testing.expectEqualStrings("config-file = ../outside.conf\n", try dirs.read("witty/config"));
    try dirs.missing("outside.conf");
}

test "ghostty import: originals are untouched" {
    var dirs: TestDirs = try .init();
    defer dirs.deinit();
    try dirs.write("ghostty/config", "font-size = 13\nconfig-file = keys.conf\n");
    try dirs.write("ghostty/keys.conf", "keybind = ctrl+a=text:x\n");
    try dirs.write("ghostty/themes/Mine", "background = #000000\n");

    const Snapshot = struct { name: []const u8, data: []const u8, mtime: i96 };
    const names = [_][]const u8{ "ghostty/config", "ghostty/keys.conf", "ghostty/themes/Mine" };
    var before: [names.len]Snapshot = undefined;
    for (names, &before) |name, *snap| snap.* = .{
        .name = name,
        .data = try dirs.read(name),
        .mtime = (try dirs.tmp.dir.statFile(testing.io, name, .{})).mtime.nanoseconds,
    };

    try testing.expectEqual(3, try dirs.import(&.{try dirs.location("ghostty", "witty")}));
    // Running again finds Witty's config and does nothing.
    try testing.expectEqual(0, try dirs.import(&.{try dirs.location("ghostty", "witty")}));

    for (before) |snap| {
        try testing.expectEqualStrings(snap.data, try dirs.read(snap.name));
        const stat = try dirs.tmp.dir.statFile(testing.io, snap.name, .{});
        try testing.expectEqual(snap.mtime, stat.mtime.nanoseconds);
    }

    // Nothing new appeared in Ghostty's directory.
    var ghostty = try dirs.tmp.dir.openDir(testing.io, "ghostty", .{ .iterate = true });
    defer ghostty.close(testing.io);
    var count: usize = 0;
    var it = ghostty.iterate();
    while (try it.next(testing.io)) |_| count += 1;
    try testing.expectEqual(3, count); // config, keys.conf, themes
}

test "ghostty import: Witty's per-user paths are its own" {
    // Guards the call sites against an upstream merge that brings back
    // Ghostty's directory names.
    const file_load = @import("file_load.zig");
    const theme = @import("theme.zig");
    const crash_dir = @import("../crash/dir.zig");
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var environ_map = try testing.environ.createMap(alloc);
    defer environ_map.deinit();

    const sep = std.fs.path.sep_str;
    const witty = sep ++ build_config.user_dir.xdg ++ sep;
    try testing.expect(std.mem.endsWith(u8, try file_load.defaultXdgPath(alloc), witty ++ "config.ghostty"));
    try testing.expect(std.mem.endsWith(u8, try file_load.legacyDefaultXdgPath(alloc), witty ++ "config"));
    if (try theme.Location.user.dir(alloc)) |dir| {
        try testing.expect(std.mem.endsWith(u8, dir, witty ++ "themes"));
    }
    const crash = try crash_dir.defaultDir(testing.io, alloc, &environ_map);
    try testing.expect(std.mem.endsWith(u8, crash.path, witty ++ "crash"));
}
