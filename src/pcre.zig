const std = @import("std");
const c = @cImport({
    @cDefine("PCRE2_CODE_UNIT_WIDTH", "8");
    @cInclude("pcre2.h");
});

const Allocator = std.mem.Allocator;

pub const CompileOptions = struct {
    anchored: bool = false,
    allowEmptyClass: bool = false,
    altBsux: bool = false,
    altCircumflex: bool = false,
    altVerbnames: bool = false,
    autoCallout: bool = false,
    caseless: bool = false,
    dollarEndonly: bool = false,
    dotall: bool = false,
    dupnames: bool = false,
    endanchored: bool = false,
    extended: bool = false,
    extendedMore: bool = false,
    firstline: bool = false,
    literal: bool = false,
    matchInvalidUtf: bool = false,
    matchUnsetBackref: bool = false,
    multiline: bool = false,
    neverBackslashC: bool = false,
    neverUcp: bool = false,
    neverUtf: bool = false,
    noAutoCapture: bool = false,
    noAutoPossess: bool = false,
    noDotstarAnchor: bool = false,
    noStartOptimize: bool = false,
    noUtfCheck: bool = false,
    ucp: bool = false,
    ungreedy: bool = false,
    useOffsetLimit: bool = false,
    utf: bool = false,

    pub fn toFlags(self: CompileOptions) u32 {
        var result: u32 = 0;
        if (self.anchored) {
            result |= c.PCRE2_ANCHORED;
        }
        if (self.allowEmptyClass) {
            result |= c.PCRE2_ALLOW_EMPTY_CLASS;
        }
        if (self.altBsux) {
            result |= c.PCRE2_ALT_BSUX;
        }
        if (self.altCircumflex) {
            result |= c.PCRE2_ALT_CIRCUMFLEX;
        }
        if (self.altVerbnames) {
            result |= c.PCRE2_ALT_VERBNAMES;
        }
        if (self.autoCallout) {
            result |= c.PCRE2_AUTO_CALLOUT;
        }
        if (self.caseless) {
            result |= c.PCRE2_CASELESS;
        }
        if (self.dollarEndonly) {
            result |= c.PCRE2_DOLLAR_ENDONLY;
        }
        if (self.dotall) {
            result |= c.PCRE2_DOTALL;
        }
        if (self.dupnames) {
            result |= c.PCRE2_DUPNAMES;
        }
        if (self.endanchored) {
            result |= c.PCRE2_ENDANCHORED;
        }
        if (self.extended) {
            result |= c.PCRE2_EXTENDED;
        }
        if (self.extendedMore) {
            result |= c.PCRE2_EXTENDED_MORE;
        }
        if (self.firstline) {
            result |= c.PCRE2_FIRSTLINE;
        }
        if (self.literal) {
            result |= c.PCRE2_LITERAL;
        }
        if (self.matchInvalidUtf) {
            result |= c.PCRE2_MATCH_INVALID_UTF;
        }
        if (self.matchUnsetBackref) {
            result |= c.PCRE2_MATCH_UNSET_BACKREF;
        }
        if (self.multiline) {
            result |= c.PCRE2_MULTILINE;
        }
        if (self.neverBackslashC) {
            result |= c.PCRE2_NEVER_BACKSLASH_C;
        }
        if (self.neverUcp) {
            result |= c.PCRE2_NEVER_UCP;
        }
        if (self.neverUtf) {
            result |= c.PCRE2_NEVER_UTF;
        }
        if (self.noAutoCapture) {
            result |= c.PCRE2_NO_AUTO_CAPTURE;
        }
        if (self.noAutoPossess) {
            result |= c.PCRE2_NO_AUTO_POSSESS;
        }
        if (self.noDotstarAnchor) {
            result |= c.PCRE2_NO_DOTSTAR_ANCHOR;
        }
        if (self.noStartOptimize) {
            result |= c.PCRE2_NO_START_OPTIMIZE;
        }
        if (self.noUtfCheck) {
            result |= c.PCRE2_NO_UTF_CHECK;
        }
        if (self.ucp) {
            result |= c.PCRE2_UCP;
        }
        if (self.ungreedy) {
            result |= c.PCRE2_UNGREEDY;
        }
        if (self.useOffsetLimit) {
            result |= c.PCRE2_USE_OFFSET_LIMIT;
        }
        if (self.utf) {
            result |= c.PCRE2_UTF;
        }
        return result;
    }
};

pub const MatchOptions = struct {
    anchored: bool = false,
    copyMatchedSubject: bool = false,
    endanchored: bool = false,
    notbol: bool = false,
    noteol: bool = false,
    notempty: bool = false,
    notemptyAtstart: bool = false,
    noJit: bool = false,
    noUtfCheck: bool = false,
    partialHard: bool = false,
    partialSoft: bool = false,

    pub fn toFlags(self: MatchOptions) u32 {
        var result: u32 = 0;
        if (self.anchored) {
            result |= c.PCRE2_ANCHORED;
        }
        if (self.copyMatchedSubject) {
            result |= c.PCRE2_COPY_MATCHED_SUBJECT;
        }
        if (self.endanchored) {
            result |= c.PCRE2_ENDANCHORED;
        }
        if (self.notbol) {
            result |= c.PCRE2_NOTBOL;
        }
        if (self.noteol) {
            result |= c.PCRE2_NOTEOL;
        }
        if (self.notempty) {
            result |= c.PCRE2_NOTEMPTY;
        }
        if (self.notemptyAtstart) {
            result |= c.PCRE2_NOTEMPTY_ATSTART;
        }
        if (self.noJit) {
            result |= c.PCRE2_NO_JIT;
        }
        if (self.noUtfCheck) {
            result |= c.PCRE2_NO_UTF_CHECK;
        }
        if (self.partialHard) {
            result |= c.PCRE2_PARTIAL_HARD;
        }
        if (self.partialSoft) {
            result |= c.PCRE2_PARTIAL_SOFT;
        }
        return result;
    }
};

pub const Regex = struct {
    handle: *c.pcre2_code_8,

    pub fn compile(pattern: []const u8, options: CompileOptions) !Regex {
        const cPattern = @ptrCast([*c]const u8, pattern.ptr);
        const cOptions = options.toFlags();

        var error_code: c_int = undefined;
        var error_offset: usize = undefined;
        var handle = c.pcre2_compile_8(cPattern, pattern.len, cOptions, &error_code, &error_offset, null);
        if (handle) |h| {
            return Regex{ .handle = h };
        }

        return error.CompilationFailed;
    }

    pub fn match(self: *const Regex, subject: []const u8, startOffset: usize, options: MatchOptions) !MatchData {
        const cSubject = @ptrCast([*c]const u8, subject.ptr);
        const cOptions = options.toFlags();
        var matchData = c.pcre2_match_data_create_from_pattern_8(self.handle, null);
        errdefer c.pcre2_match_data_free_8(matchData);
        const rc = c.pcre2_match_8(self.handle, cSubject, subject.len, startOffset, cOptions, matchData, null);
        if (rc < 0) {
            switch (rc) {
                c.PCRE2_ERROR_NOMATCH => return error.NoMatch,
                else => return error.MatchFailed,
            }
        }

        return MatchData{ .handle = matchData.? };
    }

    pub fn groups(self: *const Regex, allocator: Allocator, subject: []const u8, startOffset: usize, options: MatchOptions) ![][]const u8 {
        const matchData = try self.match(subject, startOffset, options);
        const ovector = c.pcre2_get_ovector_pointer_8(matchData.handle);
        const ovector_len = c.pcre2_get_ovector_count_8(matchData.handle);
        var result = std.ArrayList([]const u8).init(allocator);
        errdefer result.deinit();
        var i: u32 = 0;
        while (i < ovector_len * 2) : (i += 2) {
            const start = ovector[@as(usize, i)];
            const end = ovector[@as(usize, i + 1)];
            try result.append(subject[start..end]);
        }
        return result.toOwnedSlice();
    }

    pub fn deinit(self: *Regex) void {
        c.pcre2_code_free_8(self.handle);
    }
};

pub const MatchData = struct {
    handle: *c.pcre2_match_data_8,
};
