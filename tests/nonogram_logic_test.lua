-- Plain LuaJIT tests for nonogram_logic.lua (no KOReader needed).
-- Run from the plugin folder:  luajit tests/nonogram_logic_test.lua

package.path = "./?.lua;" .. package.path
local Logic = require("nonogram_logic")

local failures = 0
local function check(cond, name)
    if cond then
        print("ok   " .. name)
    else
        failures = failures + 1
        print("FAIL " .. name)
    end
end

local function gridFromLines(lines)
    local grid = {}
    for r, line in ipairs(lines) do
        grid[r] = {}
        for c = 1, #line do
            grid[r][c] = line:sub(c, c) == "#"
        end
    end
    return grid
end

local function toStates(grid)
    local states = {}
    for r, row in ipairs(grid) do
        states[r] = {}
        for c, v in ipairs(row) do
            states[r][c] = v and 1 or -1
        end
    end
    return states
end

local function sameList(a, b)
    if #a ~= #b then
        return false
    end
    for i = 1, #a do
        if a[i] ~= b[i] then
            return false
        end
    end
    return true
end

-- The board from the bug report: the stored solution ...
local reported = gridFromLines{
    "..#...##.#.",
    "......##...",
    "..###...#..",
    "#....#.#..#",
    "...#.####..",
    ".##.#.##.##",
    "..#.#.###.#",
    "#..##......",
    "#..#..#....",
    ".#.#..#...#",
    "######.####",
    "#.####.#..#",
}
-- ... and the different, equally valid grid the player arrived at.
local alternative = gridFromLines{
    "..#....##.#",
    "......##...",
    "..###.#....",
    "#....#.#.#.",
    "...#.####..",
    ".##.#.##.##",
    "..#.#.###.#",
    "#..##......",
    "#..#..#....",
    ".#.#..#...#",
    "######.####",
    "#.####.#..#",
}

local row_hints, col_hints = Logic.hintsFromGrid(reported)

check(sameList(row_hints[1], { 1, 2, 1 }) and sameList(row_hints[11], { 6, 4 })
    and sameList(col_hints[4], { 1, 1, 5 }) and sameList(col_hints[11], { 1, 2, 3 }),
    "hintsFromGrid matches the clues in the screenshot")

check(sameList(Logic.hintsFromGrid(gridFromLines{ "..." })[1], { 0 }),
    "an empty line has the single clue 0")

check(Logic.matchesHints(toStates(reported), row_hints, col_hints),
    "stored solution satisfies the clues")
check(Logic.matchesHints(toStates(alternative), row_hints, col_hints),
    "the player's alternative grid also satisfies the clues")

local broken = toStates(alternative)
broken[1][1] = 1
check(not Logic.matchesHints(broken, row_hints, col_hints),
    "a grid breaking a clue is rejected")

-- Line solver
local function lineStr(line)
    local out = {}
    for i, v in ipairs(line) do
        out[i] = v == 1 and "#" or (v == 0 and "." or "?")
    end
    return table.concat(out)
end
local function unknownLine(n)
    local line = {}
    for i = 1, n do
        line[i] = -1
    end
    return line
end

check(lineStr(Logic.solveLine({ 5 }, unknownLine(5))) == "#####", "solveLine: full line")
check(lineStr(Logic.solveLine({ 0 }, unknownLine(4))) == "....", "solveLine: empty line")
check(lineStr(Logic.solveLine({ 3 }, unknownLine(5))) == "??#??", "solveLine: overlap")
check(lineStr(Logic.solveLine({ 2, 2 }, unknownLine(5))) == "##.##", "solveLine: forced gap")
check(lineStr(Logic.solveLine({ 1, 1 }, { 1, -1, -1, -1, 1 })) == "#...#", "solveLine: uses known cells")
check(Logic.solveLine({ 3 }, { 1, 0, 1, -1, -1 }) == nil, "solveLine: contradiction returns nil")

-- Whole puzzle
local _, status = Logic.solve(row_hints, col_hints)
check(status == "stuck", "the reported puzzle is not solvable by logic alone (ambiguous)")

local heart = gridFromLines{
    ".#.#.",
    "#####",
    "#####",
    ".###.",
    "..#..",
}
local hr, hc = Logic.hintsFromGrid(heart)
local solved, hstatus = Logic.solve(hr, hc)
check(hstatus == "solved", "a simple picture is solved by logic alone")
check(hstatus == "solved" and Logic.matchesHints(solved, hr, hc), "and the result satisfies its clues")

-- findSolution: any solution consistent with the player's marks
local found = Logic.findSolution(row_hints, col_hints, toStates(alternative))
local same = found ~= nil
if found then
    for r = 1, #alternative do
        for c = 1, #alternative[1] do
            if found[r][c] ~= alternative[r][c] then
                same = false
            end
        end
    end
end
check(same, "findSolution returns the solution containing the player's marks")

local impossible = toStates(reported)
impossible[2][1] = 1 -- row 2 has the single clue 2, already placed
check(Logic.findSolution(row_hints, col_hints, impossible) == nil,
    "findSolution returns nil when the marks fit no solution")

-- Generator
math.randomseed(12345)
local all_unique, all_sized, all_consistent = true, true, true
for i = 1, 40 do
    local rows, cols = 5 + (i % 11), 5 + ((i * 7) % 11)
    local grid, unique = Logic.generate(rows, cols, 0.35 + (i % 4) * 0.1)
    if #grid ~= rows or #grid[1] ~= cols then
        all_sized = false
    end
    local gr, gc = Logic.hintsFromGrid(grid)
    local _, gstatus = Logic.solve(gr, gc)
    if not unique then
        all_unique = false
    end
    if unique ~= (gstatus == "solved") then
        all_consistent = false
    end
end
check(all_sized, "generate returns grids of the requested size")
check(all_consistent, "generate's unique flag agrees with the solver")
check(all_unique, "generate produces logic-solvable (unique) puzzles")

print(failures == 0 and "ALL PASSED" or (failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
