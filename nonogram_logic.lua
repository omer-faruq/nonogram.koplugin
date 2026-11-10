-- Pure nonogram logic: clues, line solver, puzzle solver and generator.
-- No KOReader dependencies, so it runs (and is tested) in plain LuaJIT.
--
-- Cell states: 1 = filled, 0 = known empty, -1 = unknown.
-- Pictures are grids of booleans (true = filled).

local Logic = {}

local function runsOf(n, isFilled)
    local list = {}
    local run = 0
    for i = 1, n do
        if isFilled(i) then
            run = run + 1
        elseif run > 0 then
            list[#list + 1] = run
            run = 0
        end
    end
    if run > 0 then
        list[#list + 1] = run
    end
    if #list == 0 then
        list[1] = 0
    end
    return list
end

--- Row and column clues of a boolean picture. An empty line gets the clue {0}.
function Logic.hintsFromGrid(grid)
    local rows = #grid
    local cols = rows > 0 and #grid[1] or 0
    local row_hints, col_hints = {}, {}
    for r = 1, rows do
        row_hints[r] = runsOf(cols, function(c) return grid[r][c] end)
    end
    for c = 1, cols do
        col_hints[c] = runsOf(rows, function(r) return grid[r][c] end)
    end
    return row_hints, col_hints
end

--- True if the filled runs of a line of n cells are exactly its clues.
function Logic.lineMatches(hints, n, isFilled)
    local runs = runsOf(n, isFilled)
    if #runs ~= #hints then
        return false
    end
    for i = 1, #runs do
        if runs[i] ~= hints[i] then
            return false
        end
    end
    return true
end

--- True if the filled cells (state 1) of a grid satisfy every clue.
function Logic.matchesHints(states, row_hints, col_hints)
    local rows, cols = #row_hints, #col_hints
    for r = 1, rows do
        if not Logic.lineMatches(row_hints[r], cols, function(c) return states[r][c] == 1 end) then
            return false
        end
    end
    for c = 1, cols do
        if not Logic.lineMatches(col_hints[c], rows, function(r) return states[r][c] == 1 end) then
            return false
        end
    end
    return true
end

--- Everything one line's clues force, given what is already known.
-- Returns a new line where a cell is 1/0 if every valid arrangement agrees
-- on it and -1 otherwise, or nil if no arrangement fits the known cells.
function Logic.solveLine(clues, line)
    local n = #line
    local k = #clues
    if k == 1 and clues[1] == 0 then
        k = 0
    end

    local zeros = { [0] = 0 }
    for i = 1, n do
        zeros[i] = zeros[i - 1] + (line[i] == 0 and 1 or 0)
    end
    local function free(s, e) -- no known-empty cell in s..e
        return zeros[e] - zeros[s - 1] == 0
    end

    -- pre[j][i]: cells 1..i can hold exactly the first j blocks.
    local pre = {}
    for j = 0, k do
        local row = { [0] = (j == 0) }
        local c = clues[j]
        local prev = pre[j - 1]
        for i = 1, n do
            local ok = line[i] ~= 1 and row[i - 1]
            if not ok and j >= 1 and i >= c and free(i - c + 1, i) then
                local s = i - c + 1
                if s == 1 then
                    ok = (j == 1)
                else
                    ok = line[s - 1] ~= 1 and prev[s - 2]
                end
            end
            row[i] = ok or false
        end
        pre[j] = row
    end
    if not pre[k][n] then
        return nil
    end

    -- suf[j][i]: cells i..n can hold exactly blocks j..k.
    local suf = {}
    for j = k + 1, 1, -1 do
        local row = { [n + 1] = (j == k + 1) }
        local c = clues[j]
        local nxt = suf[j + 1]
        for i = n, 1, -1 do
            local ok = line[i] ~= 1 and row[i + 1]
            if not ok and j <= k then
                local e = i + c - 1
                if e <= n and free(i, e) then
                    if e == n then
                        ok = (j == k)
                    else
                        ok = line[e + 1] ~= 1 and nxt[e + 2]
                    end
                end
            end
            row[i] = ok or false
        end
        suf[j] = row
    end

    -- Cells some valid arrangement fills (difference array over block spans).
    local diff = {}
    for i = 1, n + 1 do
        diff[i] = 0
    end
    for j = 1, k do
        local c = clues[j]
        for s = 1, n - c + 1 do
            local e = s + c - 1
            if free(s, e) then
                local left, right
                if s == 1 then
                    left = (j == 1)
                else
                    left = line[s - 1] ~= 1 and pre[j - 1][s - 2]
                end
                if e == n then
                    right = (j == k)
                else
                    right = line[e + 1] ~= 1 and suf[j + 1][e + 2]
                end
                if left and right then
                    diff[s] = diff[s] + 1
                    diff[e + 1] = diff[e + 1] - 1
                end
            end
        end
    end

    local result = {}
    local covering = 0
    for i = 1, n do
        covering = covering + diff[i]
        local can_fill = covering > 0
        local can_empty = false
        if line[i] ~= 1 then
            for j = 0, k do
                if pre[j][i - 1] and suf[j + 1][i + 1] then
                    can_empty = true
                    break
                end
            end
        end
        if can_fill and can_empty then
            result[i] = -1
        elseif can_fill then
            result[i] = 1
        elseif can_empty then
            result[i] = 0
        else
            return nil
        end
    end
    return result
end

-- Applies solveLine to rows and columns until nothing more is forced.
-- Mutates grid. Returns "solved", "stuck" or "contradiction".
local function propagate(grid, row_hints, col_hints)
    local rows, cols = #row_hints, #col_hints
    local row_dirty, col_dirty = {}, {}
    for r = 1, rows do
        row_dirty[r] = true
    end
    for c = 1, cols do
        col_dirty[c] = true
    end
    local line = {}
    local pending = true
    while pending do
        pending = false
        for r = 1, rows do
            if row_dirty[r] then
                row_dirty[r] = false
                local solved = Logic.solveLine(row_hints[r], grid[r])
                if not solved then
                    return "contradiction"
                end
                for c = 1, cols do
                    if solved[c] ~= grid[r][c] then
                        grid[r][c] = solved[c]
                        col_dirty[c] = true
                        pending = true
                    end
                end
            end
        end
        for c = 1, cols do
            if col_dirty[c] then
                col_dirty[c] = false
                for r = 1, rows do
                    line[r] = grid[r][c]
                end
                line[rows + 1] = nil
                local solved = Logic.solveLine(col_hints[c], line)
                if not solved then
                    return "contradiction"
                end
                for r = 1, rows do
                    if solved[r] ~= grid[r][c] then
                        grid[r][c] = solved[r]
                        row_dirty[r] = true
                        pending = true
                    end
                end
            end
        end
    end
    for r = 1, rows do
        for c = 1, cols do
            if grid[r][c] == -1 then
                return "stuck"
            end
        end
    end
    return "solved"
end

local function copyStates(states, rows, cols)
    local copy = {}
    for r = 1, rows do
        copy[r] = {}
        for c = 1, cols do
            local v = states and states[r] and states[r][c]
            copy[r][c] = (v == 1 or v == 0) and v or -1
        end
    end
    return copy
end

--- Solves by pure logic (no guessing), optionally starting from known cells.
-- Returns the state grid and "solved", "stuck" or "contradiction".
-- "solved" from an empty start means the clues have exactly one solution.
function Logic.solve(row_hints, col_hints, initial)
    local grid = copyStates(initial, #row_hints, #col_hints)
    return grid, propagate(grid, row_hints, col_hints)
end

--- Finds a solution that contains the given marks (1 = filled, 0 = empty),
-- guessing where logic alone is not enough. Returns a boolean picture, or
-- nil if no solution fits the marks (or the search budget runs out).
function Logic.findSolution(row_hints, col_hints, marks, max_nodes)
    local rows, cols = #row_hints, #col_hints
    local budget = max_nodes or 2000

    local function search(grid)
        budget = budget - 1
        if budget < 0 then
            return nil
        end
        local status = propagate(grid, row_hints, col_hints)
        if status == "contradiction" then
            return nil
        elseif status == "solved" then
            return grid
        end
        for r = 1, rows do
            for c = 1, cols do
                if grid[r][c] == -1 then
                    for _, guess in ipairs({ 1, 0 }) do
                        local attempt = copyStates(grid, rows, cols)
                        attempt[r][c] = guess
                        local found = search(attempt)
                        if found then
                            return found
                        end
                    end
                    return nil
                end
            end
        end
    end

    local solved = search(copyStates(marks, rows, cols))
    if not solved then
        return nil
    end
    local picture = {}
    for r = 1, rows do
        picture[r] = {}
        for c = 1, cols do
            picture[r][c] = solved[r][c] == 1
        end
    end
    return picture
end

-- A random picture with roughly `density` of its cells filled. The noise is
-- blurred first, so cells clump into blobs instead of salt-and-pepper.
local function randomPicture(rows, cols, density)
    local noise = {}
    for r = 1, rows do
        noise[r] = {}
        for c = 1, cols do
            noise[r][c] = math.random()
        end
    end
    local values, blurred = {}, {}
    for r = 1, rows do
        blurred[r] = {}
        for c = 1, cols do
            local sum, count = 0, 0
            for dr = -1, 1 do
                for dc = -1, 1 do
                    local row = noise[r + dr]
                    local v = row and row[c + dc]
                    if v then
                        sum = sum + v
                        count = count + 1
                    end
                end
            end
            blurred[r][c] = sum / count
            values[#values + 1] = blurred[r][c]
        end
    end
    table.sort(values)
    local filled = math.max(1, math.min(#values, math.floor(#values * density + 0.5)))
    local threshold = values[#values - filled + 1]
    local grid = {}
    for r = 1, rows do
        grid[r] = {}
        for c = 1, cols do
            grid[r][c] = blurred[r][c] >= threshold
        end
    end
    return grid
end

--- Generates a random picture whose clues are solvable by logic alone, and
-- therefore have exactly one solution.
-- Returns the picture and true; in the (unexpected) case that no such
-- picture turns up within the attempt limit, the last picture and false.
function Logic.generate(rows, cols, density, max_attempts)
    local grid
    for _ = 1, max_attempts or 200 do
        grid = randomPicture(rows, cols, density)
        -- When logic gets stuck, nudge the picture at an undecided cell and
        -- retry a few times before throwing it away.
        for _ = 1, 30 do
            local row_hints, col_hints = Logic.hintsFromGrid(grid)
            local states, status = Logic.solve(row_hints, col_hints)
            if status == "solved" then
                return grid, true
            end
            local undecided = {}
            for r = 1, rows do
                for c = 1, cols do
                    if states[r][c] == -1 then
                        undecided[#undecided + 1] = { r, c }
                    end
                end
            end
            local cell = undecided[math.random(#undecided)]
            grid[cell[1]][cell[2]] = not grid[cell[1]][cell[2]]
        end
    end
    return grid, false
end

return Logic
