-- Plain LuaJIT tests for nonogram_puzzles.lua (no KOReader needed).
-- Run from the plugin folder:  luajit tests/nonogram_puzzles_test.lua
-- Pass "show" to also print every picture.

package.path = "./?.lua;" .. package.path
local Logic = require("nonogram_logic")
local Puzzles = require("nonogram_puzzles")

local show = arg and arg[1] == "show"
local failures = 0
local function check(cond, name)
    if not cond then
        failures = failures + 1
        print("FAIL " .. name)
    elseif not show then
        print("ok   " .. name)
    end
end

-- Random puzzles are at most 15 cells per side; with their clue strips the
-- board is at most this many cells across, and pictures must not exceed it.
local MAX_SIDE = 15
local MAX_SPAN = 21

local seen = {}
for i, entry in ipairs(Puzzles.list) do
    local label = string.format("#%d %s", i, tostring(entry.id))
    local rows = entry.rows
    local cols = #rows[1]
    local well_formed = type(entry.id) == "string" and type(entry.name) == "string" and not seen[entry.id]
    seen[entry.id] = true
    local grid = {}
    for r, line in ipairs(rows) do
        if #line ~= cols or line:find("[^#.]") then
            well_formed = false
        end
        grid[r] = {}
        for c = 1, #line do
            grid[r][c] = line:sub(c, c) == "#"
        end
    end
    check(well_formed, label .. ": unique id, name, equal-length rows of # and .")
    if well_formed then
        local row_hints, col_hints = Logic.hintsFromGrid(grid)
        local max_row, max_col = 0, 0
        for _, h in ipairs(row_hints) do max_row = math.max(max_row, #h) end
        for _, h in ipairs(col_hints) do max_col = math.max(max_col, #h) end
        check(#rows >= 5 and #rows <= MAX_SIDE and cols >= 5 and cols <= MAX_SIDE
            and cols + max_row <= MAX_SPAN and #rows + max_col <= MAX_SPAN,
            label .. ": fits the screen like a random puzzle")
        local states, status = Logic.solve(row_hints, col_hints)
        check(status == "solved", label .. ": solvable by logic alone (one solution)")
        if show or status ~= "solved" then
            print(string.format("--- %s (%dx%d) %s", label, cols, #rows, status))
            for r = 1, #rows do
                local out = {}
                for c = 1, cols do
                    out[c] = states[r][c] == -1 and "??" or (grid[r][c] and "##" or " .")
                end
                print(table.concat(out))
            end
        end
    end
end

-- Selection order
local list = Puzzles.list
local first, first_index = Puzzles.next({}, nil)
check(first == list[1] and first_index == 1, "next: starts with the first picture")
local second = Puzzles.next({}, list[1].id)
check(second == list[2], "next: continues in list order")
check(Puzzles.next({ [list[2].id] = true }, list[1].id) == list[3], "next: skips solved pictures")
check(Puzzles.next({}, list[#list].id) == list[1], "next: wraps around")
local all = {}
for _, entry in ipairs(list) do all[entry.id] = true end
check(Puzzles.next(all, list[1].id) == list[2], "next: replays in order once everything is solved")
check(Puzzles.next({}, "no-such-id") == list[1], "next: unknown current id starts from the top")
check(Puzzles.solvedCount({ [list[1].id] = true, gone = true }) == 1, "solvedCount ignores unknown ids")
check(Puzzles.indexOf(list[3].id) == 3 and Puzzles.count() == #list, "indexOf / count")

print(failures == 0 and ("ALL PASSED (" .. #list .. " pictures)") or (failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
