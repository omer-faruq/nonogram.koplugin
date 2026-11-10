local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local GestureRange = require("ui/gesturerange")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local LuaSettings = require("luasettings")
local RenderText = require("ui/rendertext")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local T = require("ffi/util").template
local Logic = require("nonogram_logic")
local Puzzles = require("nonogram_puzzles")

local Screen = Device.screen

--
-- Puzzle helpers ------------------------------------------------------------
--

local function buildHintsFromLines(lines)
    local rows = #lines
    local cols = #lines[1]
    local solution = {}
    for r = 1, rows do
        local line = lines[r]
        if #line ~= cols then
            error("Nonogram puzzle lines must have equal length")
        end

        solution[r] = {}
        for c = 1, cols do
            local ch = line:sub(c, c)
            solution[r][c] = (ch == "#" or ch == "1")
        end
    end

    local function buildHints(count_rows, count_cols, counter)
        local hints = {}
        local max_len = 0
        for primary = 1, count_rows do
            local list = {}
            local run = 0
            for secondary = 1, count_cols do
                if counter(primary, secondary) then
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
            hints[primary] = list
            if #list > max_len then
                max_len = #list
            end
        end
        return hints, max_len
    end

    local row_hints, max_row_hint = buildHints(rows, cols, function(r, c)
        return solution[r][c]
    end)
    local col_hints, max_col_hint = buildHints(cols, rows, function(c, r)
        return solution[r][c]
    end)

    return {
        rows_count = rows,
        cols_count = cols,
        row_hints = row_hints,
        col_hints = col_hints,
        max_row_hint = max_row_hint,
        max_col_hint = max_col_hint,
        solution = solution,
    }
end

local function copyHintList(hints)
    local copy = {}
    if not hints then
        return copy
    end
    for i, hint_list in ipairs(hints) do
        copy[i] = {}
        for j, value in ipairs(hint_list) do
            copy[i][j] = value
        end
    end
    return copy
end

local function copyBooleanGrid(grid)
    local copy = {}
    if not grid then
        return copy
    end
    for r, row in ipairs(grid) do
        copy[r] = {}
        for c, value in ipairs(row) do
            copy[r][c] = not not value
        end
    end
    return copy
end

local function copySolutionGrid(solution)
    return copyBooleanGrid(solution)
end

local function clonePuzzleForState(puzzle)
    if not puzzle then
        return nil
    end
    return {
        title = puzzle.title,
        rows_count = puzzle.rows_count,
        cols_count = puzzle.cols_count,
        row_hints = copyHintList(puzzle.row_hints),
        col_hints = copyHintList(puzzle.col_hints),
        max_row_hint = puzzle.max_row_hint,
        max_col_hint = puzzle.max_col_hint,
        solution = copySolutionGrid(puzzle.solution),
        is_random = puzzle.is_random,
        unique = puzzle.unique,
        picture_id = puzzle.picture_id,
        name = puzzle.name,
    }
end

local function buildPuzzleFromBooleanGrid(grid, title, unique)
    local rows = #grid
    local cols = rows > 0 and #grid[1] or 0
    local lines = {}
    for r = 1, rows do
        local chars = {}
        for c = 1, cols do
            chars[c] = grid[r][c] and "#" or "."
        end
        lines[r] = table.concat(chars)
    end
    local puzzle = buildHintsFromLines(lines)
    puzzle.title = title
    puzzle.is_random = true
    puzzle.unique = unique or nil
    return puzzle
end

--
-- Board model -------------------------------------------------------------
--

local NonogramBoard = {}
NonogramBoard.__index = NonogramBoard

local function clamp(v, min_v, max_v)
    return math.max(min_v, math.min(max_v, v))
end

function NonogramBoard:new()
    local board = {
        current = nil,
        user_grid = {},
        show_solution = false,
        selected = { row = 1, col = 1 },
        conflict_visible = false,
        incorrect_filled = {},
        highlight_hints = false,
    }
    setmetatable(board, self)
    return board
end

function NonogramBoard:setCurrentPuzzle(puzzle)
    if not puzzle then
        return
    end
    self.current = clonePuzzleForState(puzzle)
    self.conflict_visible = false
    self.incorrect_filled = {}
    self.highlight_hints = false
    self:resetProgress()
end

function NonogramBoard:ensurePuzzle(rows, cols, density)
    if not self.current then
        self:generateRandomPuzzle(rows, cols, density)
    end
end

function NonogramBoard:createEmptyGrid()
    if not self.current then
        return {}
    end
    local rows = self.current.rows_count
    local cols = self.current.cols_count
    local grid = {}
    for r = 1, rows do
        grid[r] = {}
        for c = 1, cols do
            grid[r][c] = -1
        end
    end
    return grid
end

function NonogramBoard:resetProgress()
    if not self.current then
        return
    end
    self.user_grid = self:createEmptyGrid()
    self.show_solution = false
    self.selected = { row = 1, col = 1 }
    self.conflict_visible = false
    self.incorrect_filled = {}
    self.highlight_hints = false
end

function NonogramBoard:restartPuzzle()
    self:resetProgress()
end

function NonogramBoard:getPuzzle()
    return self.current
end

function NonogramBoard:getPuzzleTitle()
    local puzzle = self.current
    if not puzzle then
        return _("Puzzle")
    end
    -- A picture's name stays hidden until the player has seen the picture.
    if puzzle.name and (self.show_solution or self:isSolved()) then
        return _(puzzle.name)
    end
    return puzzle.title or _("Puzzle")
end

function NonogramBoard:getRowCount()
    return self.current and self.current.rows_count or 0
end

function NonogramBoard:getColCount()
    return self.current and self.current.cols_count or 0
end

function NonogramBoard:getRowHints(row)
    if not self.current then
        return {}
    end
    return self.current.row_hints[row]
end

function NonogramBoard:getColHints(col)
    if not self.current then
        return {}
    end
    return self.current.col_hints[col]
end

function NonogramBoard:getMaxRowHintCount()
    return self.current and self.current.max_row_hint or 0
end

function NonogramBoard:getMaxColHintCount()
    return self.current and self.current.max_col_hint or 0
end

function NonogramBoard:setSelection(row, col)
    local rows = math.max(1, self:getRowCount())
    local cols = math.max(1, self:getColCount())
    self.selected = {
        row = clamp(row, 1, rows),
        col = clamp(col, 1, cols),
    }
end

function NonogramBoard:areConflictsVisible()
    return self.conflict_visible
end

function NonogramBoard:areHintsHighlighted()
    return self.highlight_hints
end

function NonogramBoard:getSelection()
    return self.selected.row, self.selected.col
end

function NonogramBoard:isShowingSolution()
    return self.show_solution
end

function NonogramBoard:toggleSolution()
    self.show_solution = not self.show_solution
end

function NonogramBoard:_cellState(row, col)
    return self.user_grid[row][col]
end

function NonogramBoard:_isActualConflict(row, col)
    local solution = self.current.solution[row][col]
    local state = self.user_grid[row][col]
    if state == -1 then
        return false
    end
    if state == 1 and not solution then
        return true
    end
    if state == 0 and solution then
        return true
    end
    return false
end

function NonogramBoard:isCellConflict(row, col)
    if not self.current or not self.conflict_visible then
        return false
    end
    return self:_isActualConflict(row, col)
end

function NonogramBoard:isRowSatisfied(row)
    if not self.current then
        return false
    end
    return Logic.lineMatches(self.current.row_hints[row], self:getColCount(), function(col)
        return self.user_grid[row][col] == 1
    end)
end

function NonogramBoard:isColSatisfied(col)
    if not self.current then
        return false
    end
    return Logic.lineMatches(self.current.col_hints[col], self:getRowCount(), function(row)
        return self.user_grid[row][col] == 1
    end)
end

function NonogramBoard:applyAction(action)
    if not self.current then
        return false, _("No puzzle loaded.")
    end
    if self.show_solution then
        return false, _("Hide the solution to keep editing.")
    end
    local row, col = self:getSelection()
    local previous = self.user_grid[row][col]
    local target = previous
    if action == "fill" then
        target = 1
    elseif action == "mark" then
        target = 0
    elseif action == "clear" then
        target = -1
    else
        return false, _("Unknown action.")
    end
    if previous == target then
        return false
    end
    self.user_grid[row][col] = target
    self.conflict_visible = false
    self.incorrect_filled = {}
    self.highlight_hints = false
    if self:isSolved() then
        self:reconcileSolution()
    end
    return true
end

function NonogramBoard:revealHint()
    if not self.current then
        return false, _("No puzzle loaded.")
    end
    if self.show_solution then
        return false, _("Already showing the solution.")
    end
    self:reconcileSolution()
    local rows = self:getRowCount()
    local cols = self:getColCount()
    for r = 1, rows do
        for c = 1, cols do
            local solution = self.current.solution[r][c]
            local state = self.user_grid[r][c]
            if solution and state ~= 1 then
                self.user_grid[r][c] = 1
                self:setSelection(r, c)
                return true, T(_("Filled the correct cell %1,%2."), r, c)
            elseif (not solution) and state == 1 then
                self.user_grid[r][c] = -1
                self:setSelection(r, c)
                return true, T(_("Cleared an incorrect cell %1,%2."), r, c)
            end
        end
    end
    return false, _("Everything already matches the solution.")
end

function NonogramBoard:hasConflicts()
    if not self.current then
        return false
    end
    for r = 1, self:getRowCount() do
        for c = 1, self:getColCount() do
            if self:_isActualConflict(r, c) then
                return true
            end
        end
    end
    return false
end

-- Solved means the filled cells satisfy every clue, whichever picture that is.
function NonogramBoard:isSolved()
    if not self.current then
        return false
    end
    return Logic.matchesHints(self.user_grid, self.current.row_hints, self.current.col_hints)
end

-- Puzzles saved by older versions can have several valid solutions. If the
-- player's marks disagree with the stored one but fit another, adopt that one
-- so Check, Hint and Show solution judge against a picture they can reach.
function NonogramBoard:reconcileSolution()
    if not self.current or self.current.unique or not self:hasConflicts() then
        return
    end
    local solution = Logic.findSolution(self.current.row_hints, self.current.col_hints, self.user_grid)
    if solution then
        self.current.solution = solution
    end
end

function NonogramBoard:copyGrid(grid)
    grid = grid or {}
    local rows = self:getRowCount()
    local cols = self:getColCount()
    local copy = {}
    for r = 1, rows do
        copy[r] = {}
        for c = 1, cols do
            copy[r][c] = grid[r][c]
        end
    end
    return copy
end

function NonogramBoard:validateGrid(grid)
    if type(grid) ~= "table" then
        return nil
    end
    local rows = self:getRowCount()
    local cols = self:getColCount()
    local copy = {}
    for r = 1, rows do
        local source_row = grid[r]
        if type(source_row) ~= "table" then
            return nil
        end
        copy[r] = {}
        for c = 1, cols do
            local value = source_row[c]
            if value ~= 1 and value ~= 0 and value ~= -1 then
                value = -1
            end
            copy[r][c] = value
        end
    end
    return copy
end

function NonogramBoard:serialize()
    if not self.current then
        return nil
    end
    return {
        puzzle = clonePuzzleForState(self.current),
        user_grid = self:copyGrid(self.user_grid),
        show_solution = self.show_solution,
        selected = { row = self.selected.row, col = self.selected.col },
        conflict_visible = self.conflict_visible,
        incorrect_filled = copyBooleanGrid(self.incorrect_filled),
        highlight_hints = self.highlight_hints,
    }
end

function NonogramBoard:load(state)
    if type(state) ~= "table" or not state.puzzle then
        return false
    end
    self:setCurrentPuzzle(state.puzzle)
    local grid = self:validateGrid(state.user_grid)
    if grid then
        self.user_grid = grid
    end
    local rows = math.max(1, self:getRowCount())
    local cols = math.max(1, self:getColCount())
    local selected = state.selected or {}
    self.selected = {
        row = clamp(selected.row or 1, 1, rows),
        col = clamp(selected.col or 1, 1, cols),
    }
    self.show_solution = not not state.show_solution
    self.conflict_visible = not not state.conflict_visible
    self.incorrect_filled = copyBooleanGrid(state.incorrect_filled)
    self.highlight_hints = not not state.highlight_hints
    return true
end

function NonogramBoard:generateRandomPuzzle(rows, cols, density)
    rows = clamp(math.floor(rows or math.random(10, 15)), 5, 20)
    cols = clamp(math.floor(cols or math.random(10, 15)), 5, 20)
    density = math.max(0.2, math.min(0.8, density or (0.35 + math.random() * 0.3)))
    -- Only pictures solvable by logic alone are used, so the clues have
    -- exactly one solution.
    local grid, unique = Logic.generate(rows, cols, density)
    local puzzle = buildPuzzleFromBooleanGrid(grid, T(_("Random %1x%2"), rows, cols), unique)
    self:setCurrentPuzzle(puzzle)
    return self.current
end

-- Loads a hand-drawn picture (an entry of nonogram_puzzles.lua).
function NonogramBoard:loadPicture(entry, title)
    local puzzle = buildHintsFromLines(entry.rows)
    puzzle.title = title
    puzzle.name = entry.name
    puzzle.picture_id = entry.id
    puzzle.unique = true
    self:setCurrentPuzzle(puzzle)
    return self.current
end

function NonogramBoard:checkProgress()
    if not self.current then
        return { solved = false, conflicts = false }
    end
    self:reconcileSolution()
    local solved = self:isSolved()
    local conflicts = false
    local incorrect = {}
    if not solved then
        conflicts = self:hasConflicts()
        if conflicts then
            for r = 1, self:getRowCount() do
                for c = 1, self:getColCount() do
                    if self:_isActualConflict(r, c) then
                        local state = self.user_grid[r][c]
                        local solution = self.current.solution[r][c]
                        if state == 1 and not solution then
                            incorrect[r] = incorrect[r] or {}
                            incorrect[r][c] = true
                        end
                    end
                end
            end
        end
    end
    self.conflict_visible = conflicts
    self.incorrect_filled = incorrect
    self.highlight_hints = true
    return {
        solved = solved,
        conflicts = conflicts,
    }
end

--
-- Board widget ------------------------------------------------------------
--

local NonogramBoardWidget = InputContainer:extend{
    board = nil,
    max_width = nil,
    max_height = nil,
}

function NonogramBoardWidget:init()
    self.number_face = Font:getFace("cfont", math.max(22, math.floor(Screen:getWidth() / 32)))
    self.hint_face = Font:getFace("smallinfofont", math.max(18, math.floor(Screen:getWidth() / 40)))
    self.paint_rect = Geom:new{ x = 0, y = 0, w = 10, h = 10 }
    self.ges_events = {
        Tap = {
            GestureRange:new{
                ges = "tap",
                range = function()
                    return self.paint_rect
                end,
            },
        },
    }
end

function NonogramBoardWidget:setMaxDimensions(max_w, max_h)
    self.max_width = max_w
    self.max_height = max_h
    if self.board then
        self:updateMetrics()
    end
end

function NonogramBoardWidget:updateMetrics()
    local rows = self.board:getRowCount()
    local cols = self.board:getColCount()
    local left_hint_cols = math.max(2, self.board:getMaxRowHintCount())
    local top_hint_rows = math.max(2, self.board:getMaxColHintCount())
    local target_w = math.floor((self.max_width or (Screen:getWidth() * 0.9)))
    local target_h = math.floor((self.max_height or (Screen:getHeight() * 0.9)))
    local cell_size = math.floor(math.min(
        target_w / (cols + left_hint_cols),
        target_h / (rows + top_hint_rows)
    ))
    cell_size = math.max(1, cell_size)
    self.cell_size = cell_size
    self.left_hint_cols = left_hint_cols
    self.top_hint_rows = top_hint_rows
    self.total_width = (cols + left_hint_cols) * cell_size
    self.total_height = (rows + top_hint_rows) * cell_size
    self.grid_origin_x = self.paint_rect.x + left_hint_cols * cell_size
    self.grid_origin_y = self.paint_rect.y + top_hint_rows * cell_size
    self.dimen = Geom:new{ w = self.total_width, h = self.total_height }
end

function NonogramBoardWidget:getCellFromPoint(x, y)
    if not self.grid_origin_x then
        return nil
    end
    local cell = self.cell_size
    if cell <= 0 then
        return nil
    end
    local local_x = x - self.grid_origin_x
    local local_y = y - self.grid_origin_y
    if local_x < 0 or local_y < 0 then
        return nil
    end
    local col = math.floor(local_x / cell) + 1
    local row = math.floor(local_y / cell) + 1
    if row < 1 or row > self.board:getRowCount() or col < 1 or col > self.board:getColCount() then
        return nil
    end
    return row, col
end

function NonogramBoardWidget:onTap(_, ges)
    if not (ges and ges.pos) then
        return false
    end
    local row, col = self:getCellFromPoint(ges.pos.x, ges.pos.y)
    if not row then
        return false
    end
    self.board:setSelection(row, col)
    if self.onSelectionChanged then
        self.onSelectionChanged(row, col)
    end
    if self.onCellActivated then
        self.onCellActivated(row, col)
    end
    self:refresh()
    return true
end

function NonogramBoardWidget:refresh()
    if not self.paint_rect then
        return
    end
    UIManager:setDirty(self, function()
        return "ui", Geom:new{
            x = self.paint_rect.x,
            y = self.paint_rect.y,
            w = self.paint_rect.w,
            h = self.paint_rect.h,
        }
    end)
end

local function drawCenteredText(bb, x, y, w, h, face, text, color)
    local metrics = RenderText:sizeUtf8Text(0, h, face, text, true, false)
    local text_x = x + math.floor((w - metrics.x) / 2)
    local baseline = y + math.floor((h + metrics.y_top - metrics.y_bottom) / 2)
    RenderText:renderUtf8Text(bb, text_x, baseline, face, text, true, false, color)
end

local function paintLineFallback(bb, x0, y0, x1, y1, color)
    x0 = math.floor(x0 + 0.5)
    y0 = math.floor(y0 + 0.5)
    x1 = math.floor(x1 + 0.5)
    y1 = math.floor(y1 + 0.5)
    local dx = math.abs(x1 - x0)
    local sx = x0 < x1 and 1 or -1
    local dy = -math.abs(y1 - y0)
    local sy = y0 < y1 and 1 or -1
    local err = dx + dy
    while true do
        bb:paintRect(x0, y0, 1, 1, color)
        if x0 == x1 and y0 == y1 then
            break
        end
        local e2 = 2 * err
        if e2 >= dy then
            err = err + dy
            x0 = x0 + sx
        end
        if e2 <= dx then
            err = err + dx
            y0 = y0 + sy
        end
    end
end

function NonogramBoardWidget:paintHints(bb, x, y)
    local cell = self.cell_size
    local grid_x = x + self.left_hint_cols * cell
    local grid_y = y + self.top_hint_rows * cell
    local highlight = self.board:areHintsHighlighted()

    for row = 1, self.board:getRowCount() do
        local hints = self.board:getRowHints(row)
        local start_x = grid_x - self.left_hint_cols * cell
        local row_y = grid_y + (row - 1) * cell
        if highlight and self.board:isRowSatisfied(row) then
            bb:paintRect(start_x, row_y, self.left_hint_cols * cell, cell, Blitbuffer.COLOR_GRAY_D)
        end
        local offset = self.left_hint_cols - #hints
        for idx, value in ipairs(hints) do
            local cell_x = start_x + (offset + idx - 1) * cell
            drawCenteredText(bb, cell_x, row_y, cell, cell, self.hint_face, tostring(value), Blitbuffer.COLOR_BLACK)
        end
    end

    for col = 1, self.board:getColCount() do
        local hints = self.board:getColHints(col)
        local start_y = grid_y - self.top_hint_rows * cell
        local col_x = grid_x + (col - 1) * cell
        if highlight and self.board:isColSatisfied(col) then
            bb:paintRect(col_x, start_y, cell, self.top_hint_rows * cell, Blitbuffer.COLOR_GRAY_D)
        end
        local offset = self.top_hint_rows - #hints
        for idx, value in ipairs(hints) do
            local cell_y = start_y + (offset + idx - 1) * cell
            drawCenteredText(bb, col_x, cell_y, cell, cell, self.hint_face, tostring(value), Blitbuffer.COLOR_BLACK)
        end
    end
end

function NonogramBoardWidget:paintGrid(bb, x, y)
    local cell = self.cell_size
    local grid_x = x + self.left_hint_cols * cell
    local grid_y = y + self.top_hint_rows * cell
    local rows = self.board:getRowCount()
    local cols = self.board:getColCount()
    local incorrect = self.board.incorrect_filled
    local sel_row, sel_col = self.board:getSelection()
    for row = 1, rows do
        for col = 1, cols do
            local cell_x = grid_x + (col - 1) * cell
            local cell_y = grid_y + (row - 1) * cell
            bb:paintRect(cell_x, cell_y, cell, cell, Blitbuffer.COLOR_WHITE)
            if row == sel_row and col == sel_col then
                bb:paintRect(cell_x, cell_y, cell, cell, Blitbuffer.COLOR_GRAY)
            end
            if self.board:isCellConflict(row, col) then
                bb:paintRect(cell_x, cell_y, cell, cell, Blitbuffer.COLOR_GRAY_D)
            end
            local value
            if self.board:isShowingSolution() then
                value = self.board.current.solution[row][col] and 1 or 0
            else
                value = self.board.user_grid[row][col]
            end
            if value == 1 then
                bb:paintRect(cell_x + 2, cell_y + 2, cell - 4, cell - 4, Blitbuffer.COLOR_BLACK)
                if incorrect[row] and incorrect[row][col] then
                    local padding = math.floor(cell * 0.2)
                    paintLineFallback(bb,
                        cell_x + padding,
                        cell_y + padding,
                        cell_x + cell - padding,
                        cell_y + cell - padding,
                        Blitbuffer.COLOR_WHITE)
                    paintLineFallback(bb,
                        cell_x + padding,
                        cell_y + cell - padding,
                        cell_x + cell - padding,
                        cell_y + padding,
                        Blitbuffer.COLOR_WHITE)
                end
            elseif value == 0 then
                local padding = math.floor(cell * 0.2)
                paintLineFallback(bb,
                    cell_x + padding,
                    cell_y + padding,
                    cell_x + cell - padding,
                    cell_y + cell - padding,
                    Blitbuffer.COLOR_GRAY_2 or Blitbuffer.COLOR_GRAY_4)
                paintLineFallback(bb,
                    cell_x + padding,
                    cell_y + cell - padding,
                    cell_x + cell - padding,
                    cell_y + padding,
                    Blitbuffer.COLOR_GRAY_2 or Blitbuffer.COLOR_GRAY_4)
            end
        end
    end

    local thick = Size.line.thick
    local thin = Size.line.thin
    for i = 0, rows do
        local y0 = grid_y + math.floor(i * cell)
        bb:paintRect(grid_x, y0, cols * cell, (i % 5 == 0) and thick or thin, Blitbuffer.COLOR_BLACK)
    end
    for i = 0, cols do
        local x0 = grid_x + math.floor(i * cell)
        bb:paintRect(x0, grid_y, (i % 5 == 0) and thick or thin, rows * cell, Blitbuffer.COLOR_BLACK)
    end
end

function NonogramBoardWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.total_width or 10, h = self.total_height or 10 }
    self:updateMetrics()
    self.paint_rect.w = self.total_width
    self.paint_rect.h = self.total_height
    bb:paintRect(x, y, self.total_width, self.total_height, Blitbuffer.COLOR_WHITE)
    self:paintHints(bb, x, y)
    self:paintGrid(bb, x, y)
end

--
-- Screen ------------------------------------------------------------------
--

local NonogramScreen = InputContainer:extend{}

function NonogramScreen:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.covers_fullscreen = true
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self.board:ensurePuzzle()
    self.status_text = TextWidget:new{
        text = _("Tap a cell, then use the buttons below to fill or mark it."),
        face = Font:getFace("smallinfofont"),
        max_width = math.floor(Screen:getWidth() * 0.95),
    }
    self.board_widget = NonogramBoardWidget:new{
        board = self.board,
        onSelectionChanged = function()
            self:updateStatus()
        end,
        onCellActivated = function(row, col)
            self:onCellActivated(row, col)
        end,
    }
    self.active_action = "fill"
    self:buildLayout()
end

function NonogramScreen:buildLayout()
    local board_frame_width = math.floor(Screen:getWidth() * 0.9)
    local board_frame_padding = Size.padding.large
    local board_frame = FrameContainer:new{
        padding = board_frame_padding,
        width = board_frame_width,
        bordersize = 0,
        bordercolor = Blitbuffer.COLOR_WHITE,
        self.board_widget,
    }

    local top_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width = math.floor(Screen:getWidth() * 0.9),
        buttons = {
            {
                {
                    text = _("New game"),
                    callback = function()
                        self:onNewGame()
                    end,
                },
                {
                    text = _("Restart"),
                    callback = function()
                        self:onRestart()
                    end,
                },
                {
                    id = "solution_button",
                    text = _("Show solution"),
                    callback = function()
                        self:toggleSolution()
                    end,
                },
                {
                    text = _("Close"),
                    callback = function()
                        self:onClose()
                        UIManager:close(self)
                        UIManager:setDirty(nil, "full")
                    end,
                },
            },
        },
    }
    self.solution_button = top_buttons:getButtonById("solution_button")

    local action_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width = math.floor(Screen:getWidth() * 0.85),
        buttons = {
            {
                {
                    id = "fill_button",
                    text = _("Fill cell"),
                    callback = function()
                        self:setActiveAction("fill")
                    end,
                },
                {
                    id = "mark_button",
                    text = _("Mark empty"),
                    callback = function()
                        self:setActiveAction("mark")
                    end,
                },
                {
                    text = _("Clear cell"),
                    callback = function()
                        self:onAction("clear")
                    end,
                },
            },
            {
                {
                    text = _("Hint"),
                    callback = function()
                        self:onHint()
                    end,
                },
                {
                    text = _("Check"),
                    callback = function()
                        self:onCheck()
                    end,
                },
            },
        },
    }
    self.fill_button = action_buttons:getButtonById("fill_button")
    self.mark_button = action_buttons:getButtonById("mark_button")
    local action_buttons_height = action_buttons:getSize().h

    local layout_vertical_margin = Size.padding.large
    local spacing_height = Size.span.vertical_default * 4
    local top_buttons_height = top_buttons:getSize().h
    local status_height = self.status_text:getSize().h
    local frame_border = board_frame.bordersize or Size.border.window
    local frame_margin = board_frame.margin or 0
    local board_inner_width = board_frame_width - 2 * (board_frame_padding + frame_border + frame_margin)
    local available_height = Screen:getHeight() - 2 * layout_vertical_margin
    available_height = available_height - spacing_height - top_buttons_height - status_height - action_buttons_height
    local board_inner_height = available_height - 2 * (frame_border + frame_margin + board_frame_padding)
    board_inner_width = math.max(1, board_inner_width)
    board_inner_height = math.max(1, board_inner_height)
    self.board_widget:setMaxDimensions(board_inner_width, board_inner_height)
    board_frame.height = math.max(0, board_inner_height + 2 * (board_frame_padding + frame_border + frame_margin))
    self.layout_vertical_margin = layout_vertical_margin

    self.content_layout = VerticalGroup:new{
        align = "center",
        VerticalSpan:new{ width = Size.span.vertical_default },
        top_buttons,
        VerticalSpan:new{ width = Size.span.vertical_default },
        board_frame,
        VerticalSpan:new{ width = Size.span.vertical_default },
    }
    local scrolling_height = Screen:getHeight() - 2 * layout_vertical_margin - action_buttons:getSize().h - self.status_text:getSize().h - 2 * Size.span.vertical_default
    local scrolling_width = math.floor(Screen:getWidth() * 0.95)
    self.layout = ScrollableContainer:new{
        dimen = Geom:new{ w = scrolling_width, h = scrolling_height },
        self.content_layout,
    }
    self.action_buttons = action_buttons
    self.action_buttons_margin = layout_vertical_margin
    self[1] = self.layout
    self[2] = self.status_text
    self[3] = self.action_buttons
    self:updateActionButtons()
    self:updateSolutionButton()
    self:updateStatus()
end

function NonogramScreen:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    local top_offset = (self.layout_vertical_margin or Size.padding.large)
    local layout_size = self.layout.dimen or self.layout:getSize()
    local layout_x = x + math.floor((self.dimen.w - layout_size.w) / 2)
    local layout_y = y + top_offset
    self.layout:paintTo(bb, layout_x, layout_y)

    local status_size = self.status_text:getSize()
    local status_x = x + math.floor((self.dimen.w - status_size.w) / 2)
    local status_y = layout_y + layout_size.h + Size.span.vertical_default
    self.status_text:paintTo(bb, status_x, status_y)

    local action_size = self.action_buttons:getSize()
    local action_x = x + math.floor((self.dimen.w - action_size.w) / 2)
    local action_y = status_y + status_size.h + Size.span.vertical_default
    self.action_buttons.dimen = Geom:new{ x = action_x, y = action_y, w = action_size.w, h = action_size.h }
    self.action_buttons:paintTo(bb, action_x, action_y)
end

function NonogramScreen:updateStatus(message)
    if message then
        self.status_text:setText(message)
        UIManager:setDirty(self, function()
            return "ui", self.dimen
        end)
        return
    end
    local row, col = self.board:getSelection()
    local puzzle_title = self.board:getPuzzleTitle()
    local status = T(_("%1 · Cell %2,%3"), puzzle_title, row, col)
    if self.board:isSolved() then
        status = status .. "\n" .. _("Puzzle solved! Start a new game or restart to play again.")
    elseif self.board:isShowingSolution() then
        status = status .. "\n" .. _("Solution is visible; editing is disabled.")
    elseif self.board:areConflictsVisible() then
        status = status .. "\n" .. _("Conflicting cells are highlighted.")
    end
    self.status_text:setText(status)
    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
end

function NonogramScreen:onAction(action)
    local ok, err = self.board:applyAction(action)
    if not ok then
        if err then
            self:updateStatus(err)
        end
        return
    end
    self.board_widget:refresh()
    if self.board:isSolved() then
        local puzzle = self.board:getPuzzle()
        local text = _("Great job!")
        if puzzle.name then
            text = text .. "\n" .. _(puzzle.name)
        end
        self.plugin:markPictureSolved(puzzle)
        UIManager:show(InfoMessage:new{ text = text, timeout = 3 })
    end
    self.plugin:saveState()
    self:updateStatus()
end

function NonogramScreen:setActiveAction(action)
    if action ~= "fill" and action ~= "mark" then
        return
    end
    if self.active_action == action then
        return
    end
    self.active_action = action
    self:updateActionButtons()
end

function NonogramScreen:updateActionButtons()
    local function applyBackground(button, is_active)
        if not button then
            return
        end
        button.frame.background = is_active and Blitbuffer.COLOR_GRAY_E or Blitbuffer.COLOR_WHITE
    end
    applyBackground(self.fill_button, self.active_action == "fill")
    applyBackground(self.mark_button, self.active_action == "mark")
    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
end

function NonogramScreen:onCellActivated(row, col)
    if not self.active_action then
        return
    end
    local current = self.board.user_grid[row][col]
    local action = self.active_action
    if action == "fill" and current == 1 then
        action = "clear"
    elseif action == "mark" and current == 0 then
        action = "clear"
    end
    self:onAction(action)
end

function NonogramScreen:onHint()
    local ok, msg = self.board:revealHint()
    if not ok then
        self:updateStatus(msg)
        return
    end
    self.board_widget:refresh()
    self.plugin:saveState()
    self:updateStatus(msg)
end

function NonogramScreen:onCheck()
    local result = self.board:checkProgress()
    self.board_widget:refresh()
    self.plugin:saveState()
    if result.solved then
        self:updateStatus(_("Everything matches the solution."))
        return
    end
    if result.conflicts then
        self:updateStatus(_("There are mistakes marked in darker cells."))
    else
        self:updateStatus(_("Looks good so far; keep filling the blanks."))
    end
end

function NonogramScreen:onRestart()
    self.board:restartPuzzle()
    self.board_widget:refresh()
    self.plugin:saveState()
    self:updateSolutionButton()
    self:updateStatus(_("Progress cleared."))
end

function NonogramScreen:toggleSolution()
    self.board:toggleSolution()
    self.board_widget:refresh()
    self.plugin:saveState()
    self:updateSolutionButton()
    if self.board:isShowingSolution() then
        self:updateStatus(_("Showing the full solution."))
    else
        self:updateStatus(_("Solution hidden. Continue playing!"))
    end
end

function NonogramScreen:updateSolutionButton()
    if not self.solution_button then
        return
    end
    local text = self.board:isShowingSolution() and _("Hide solution") or _("Show solution")
    local width = self.solution_button.width
    self.solution_button:setText(text, width)
end

function NonogramScreen:onClose()
    self.plugin:saveState()
    self.plugin:onScreenClosed()
end

-- Asks which kind of puzzle to start: the next picture or a random one.
function NonogramScreen:onNewGame()
    local dialog
    local function choice(text, start)
        return { {
            text = text,
            callback = function()
                UIManager:close(dialog)
                self:onPuzzleChanged(start())
            end,
        } }
    end
    dialog = ButtonDialog:new{
        title = _("New game"),
        title_align = "center",
        buttons = {
            choice(T(_("Picture puzzle (%1/%2 solved)"),
                Puzzles.solvedCount(self.plugin:getSolvedPictures()), Puzzles.count()), function()
                self.plugin:startNextPicture()
                return self.board:getPuzzleTitle()
            end),
            choice(_("Random puzzle"), function()
                self.board:generateRandomPuzzle()
                return _("Generated a new random puzzle.")
            end),
        },
    }
    UIManager:show(dialog)
end

function NonogramScreen:onPuzzleChanged(message)
    if self.board_widget.updateMetrics then
        self.board_widget:updateMetrics()
    end
    self.board_widget:refresh()
    self.plugin:saveState()
    self:updateSolutionButton()
    self.active_action = nil
    self:setActiveAction("fill")
    self:updateStatus(message)
end

--
-- Plugin container --------------------------------------------------------
--

local Nonogram = WidgetContainer:extend{
    name = "nonogram",
    is_doc_only = false,
}

function Nonogram:init()
    self.settings_file = DataStorage:getSettingsDir() .. "/nonogram.lua"
    self.settings = LuaSettings:open(self.settings_file)
    self.ui.menu:registerToMainMenu(self)
end

function Nonogram:addToMainMenu(menu_items)
    menu_items.nonogram = {
        text = _("Nonogram"),
        sorting_hint = "tools",
        callback = function()
            self:showGame()
        end,
    }
end

function Nonogram:getBoard()
    if not self.board then
        self.board = NonogramBoard:new()
        local state = self.settings:readSetting("state")
        if not self.board:load(state) then
            self:startNextPicture()
        else
            self.board:ensurePuzzle()
        end
    end
    return self.board
end

-- Ids of the pictures the player has completed: { [id] = true }.
function Nonogram:getSolvedPictures()
    return self.settings:readSetting("solved_pictures") or {}
end

function Nonogram:markPictureSolved(puzzle)
    if not (puzzle and puzzle.picture_id) then
        return
    end
    local solved = self:getSolvedPictures()
    solved[puzzle.picture_id] = true
    self.settings:saveSetting("solved_pictures", solved)
end

-- Loads the next unsolved picture after the current one (in list order).
function Nonogram:startNextPicture()
    local current = self.board:getPuzzle()
    local entry, index = Puzzles.next(self:getSolvedPictures(), current and current.picture_id)
    self.board:loadPicture(entry, T(_("Picture %1/%2"), index, Puzzles.count()))
end

function Nonogram:saveState()
    if not self.board then
        return
    end
    self.settings:saveSetting("state", self.board:serialize())
    self.settings:flush()
end

function Nonogram:showGame()
    if self.screen then
        return
    end
    self.screen = NonogramScreen:new{
        board = self:getBoard(),
        plugin = self,
    }
    UIManager:show(self.screen)
end

function Nonogram:onScreenClosed()
    self.screen = nil
end

return Nonogram
