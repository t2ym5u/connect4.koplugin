-- ---------------------------------------------------------------------------
-- P4Board — Connect Four (Puissance 4) game logic
--
-- grid[r][c]: 0=empty, 1=yellow (player 1), 2=red (player 2)
--   r=1 TOP, r=6 BOTTOM; c=1..7
--
-- turn:    1 or 2 (current player)
-- status:  "playing" / "won" / "draw"
-- winner:  nil / 1 / 2
-- last_col, last_row: position of most recent drop (for highlighting)
-- ---------------------------------------------------------------------------

local P4Board = {}
P4Board.__index = P4Board

local ROWS = 6
local COLS = 7

-- Center-outward column order for better alpha-beta pruning
local COL_ORDER = { 4, 3, 5, 2, 6, 1, 7 }

-- ---------------------------------------------------------------------------
-- Constructor / reset
-- ---------------------------------------------------------------------------

function P4Board:new(opts)
    opts = opts or {}
    local o = setmetatable({}, self)
    o:reset()
    return o
end

function P4Board:reset()
    self.grid = {}
    for r = 1, ROWS do
        self.grid[r] = {}
        for c = 1, COLS do
            self.grid[r][c] = 0
        end
    end
    self.turn     = 1
    self.status   = "playing"
    self.winner   = nil
    self.last_col = nil
    self.last_row = nil
end

-- Alias used by some callers
function P4Board:generate()
    self:reset()
end

-- ---------------------------------------------------------------------------
-- Drop a piece into column col for the current player.
-- Returns: "ok" | "full" | "won" | "draw"
-- ---------------------------------------------------------------------------

function P4Board:dropPiece(col)
    if col < 1 or col > COLS then return "full" end
    if self.status ~= "playing" then return "full" end

    -- Find lowest empty row (gravity: highest r is bottom)
    local target_row = nil
    for r = ROWS, 1, -1 do
        if self.grid[r][col] == 0 then
            target_row = r
            break
        end
    end
    if not target_row then return "full" end

    local player = self.turn
    self.grid[target_row][col] = player
    self.last_col = col
    self.last_row = target_row

    -- Check win
    if self:checkWin(target_row, col, player) then
        self.status = "won"
        self.winner = player
        return "won"
    end

    -- Check draw (all columns full)
    if self:isBoardFull() then
        self.status = "draw"
        return "draw"
    end

    -- Switch turn
    self.turn = (player == 1) and 2 or 1
    return "ok"
end

-- ---------------------------------------------------------------------------
-- Win detection: check 4-in-a-row through (r,c) for player
-- ---------------------------------------------------------------------------

function P4Board:checkWin(r, c, player)
    local grid = self.grid

    local function countDir(dr, dc)
        local count = 0
        local nr, nc = r + dr, c + dc
        while nr >= 1 and nr <= ROWS and nc >= 1 and nc <= COLS
              and grid[nr][nc] == player do
            count = count + 1
            nr = nr + dr
            nc = nc + dc
        end
        return count
    end

    -- Horizontal
    if 1 + countDir(0, 1) + countDir(0, -1) >= 4 then return true end
    -- Vertical
    if 1 + countDir(1, 0) + countDir(-1, 0) >= 4 then return true end
    -- Diagonal ↗↙
    if 1 + countDir(-1, 1) + countDir(1, -1) >= 4 then return true end
    -- Diagonal ↖↘
    if 1 + countDir(-1, -1) + countDir(1, 1) >= 4 then return true end

    return false
end

-- ---------------------------------------------------------------------------
-- Check if board is completely full
-- ---------------------------------------------------------------------------

function P4Board:isBoardFull()
    for c = 1, COLS do
        if self.grid[1][c] == 0 then return false end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Count open 3-in-a-row threats for a player on a given grid.
-- A "threat" is a window of 4 consecutive cells containing exactly 3 pieces
-- of the player and 1 empty cell.
-- ---------------------------------------------------------------------------

function P4Board:countThreats(player, board_grid)
    board_grid = board_grid or self.grid
    local opponent = (player == 1) and 2 or 1
    local threats = 0

    local function checkWindow(cells)
        local p_count = 0
        local empty   = 0
        for _, v in ipairs(cells) do
            if v == player then
                p_count = p_count + 1
            elseif v == empty then
                empty = empty + 1
            elseif v == opponent then
                return  -- blocked
            end
        end
        -- Recount properly
        p_count = 0
        local e_count = 0
        for _, v in ipairs(cells) do
            if v == player then p_count = p_count + 1
            elseif v == 0  then e_count = e_count + 1
            end
        end
        if p_count == 3 and e_count == 1 then
            threats = threats + 1
        end
    end

    -- Horizontal windows
    for r = 1, ROWS do
        for c = 1, COLS - 3 do
            checkWindow({ board_grid[r][c], board_grid[r][c+1],
                          board_grid[r][c+2], board_grid[r][c+3] })
        end
    end
    -- Vertical windows
    for r = 1, ROWS - 3 do
        for c = 1, COLS do
            checkWindow({ board_grid[r][c], board_grid[r+1][c],
                          board_grid[r+2][c], board_grid[r+3][c] })
        end
    end
    -- Diagonal ↘
    for r = 1, ROWS - 3 do
        for c = 1, COLS - 3 do
            checkWindow({ board_grid[r][c],   board_grid[r+1][c+1],
                          board_grid[r+2][c+2], board_grid[r+3][c+3] })
        end
    end
    -- Diagonal ↗
    for r = 4, ROWS do
        for c = 1, COLS - 3 do
            checkWindow({ board_grid[r][c],   board_grid[r-1][c+1],
                          board_grid[r-2][c+2], board_grid[r-3][c+3] })
        end
    end

    return threats
end

-- ---------------------------------------------------------------------------
-- Score a window of 4 cells for the evaluation function (from player 1's POV)
-- ---------------------------------------------------------------------------

local function scoreWindow(cells, player)
    local opponent = (player == 1) and 2 or 1
    local p_count  = 0
    local e_count  = 0
    for _, v in ipairs(cells) do
        if v == player   then p_count = p_count + 1
        elseif v == 0    then e_count = e_count + 1
        end
    end
    -- Check no opponent blocking
    local opp_count = 0
    for _, v in ipairs(cells) do
        if v == opponent then opp_count = opp_count + 1 end
    end
    if opp_count > 0 then return 0 end

    if p_count == 4 then return 100
    elseif p_count == 3 and e_count == 1 then return 5
    elseif p_count == 2 and e_count == 2 then return 2
    end
    return 0
end

-- ---------------------------------------------------------------------------
-- Static evaluation of a board state (from player 1's perspective)
-- ---------------------------------------------------------------------------

local function evaluate(grid)
    local score = 0

    -- Center column preference (column 4 = index 4)
    for r = 1, ROWS do
        if grid[r][4] == 1 then score = score + 3
        elseif grid[r][4] == 2 then score = score - 3
        end
    end

    -- Horizontal windows
    for r = 1, ROWS do
        for c = 1, COLS - 3 do
            local window = { grid[r][c], grid[r][c+1], grid[r][c+2], grid[r][c+3] }
            score = score + scoreWindow(window, 1) - scoreWindow(window, 2)
        end
    end
    -- Vertical windows
    for r = 1, ROWS - 3 do
        for c = 1, COLS do
            local window = { grid[r][c], grid[r+1][c], grid[r+2][c], grid[r+3][c] }
            score = score + scoreWindow(window, 1) - scoreWindow(window, 2)
        end
    end
    -- Diagonal ↘
    for r = 1, ROWS - 3 do
        for c = 1, COLS - 3 do
            local window = { grid[r][c], grid[r+1][c+1], grid[r+2][c+2], grid[r+3][c+3] }
            score = score + scoreWindow(window, 1) - scoreWindow(window, 2)
        end
    end
    -- Diagonal ↗
    for r = 4, ROWS do
        for c = 1, COLS - 3 do
            local window = { grid[r][c], grid[r-1][c+1], grid[r-2][c+2], grid[r-3][c+3] }
            score = score + scoreWindow(window, 1) - scoreWindow(window, 2)
        end
    end

    return score
end

-- ---------------------------------------------------------------------------
-- AI helpers
-- ---------------------------------------------------------------------------

-- Copy a grid (shallow rows)
local function copyGrid(src)
    local dst = {}
    for r = 1, ROWS do
        dst[r] = {}
        for c = 1, COLS do
            dst[r][c] = src[r][c]
        end
    end
    return dst
end

-- Drop player's piece into col on a grid copy.
-- Returns: new_grid, row (nil if column full)
local function simulateDrop(grid, col, player)
    local target = nil
    for r = ROWS, 1, -1 do
        if grid[r][col] == 0 then
            target = r
            break
        end
    end
    if not target then return nil, nil end
    local new_grid = copyGrid(grid)
    new_grid[target][col] = player
    return new_grid, target
end

-- Check win on a grid for player at (r, c)
local function checkWinGrid(grid, r, c, player)
    local function countDir(dr, dc)
        local count = 0
        local nr, nc = r + dr, c + dc
        while nr >= 1 and nr <= ROWS and nc >= 1 and nc <= COLS
              and grid[nr][nc] == player do
            count = count + 1
            nr = nr + dr
            nc = nc + dc
        end
        return count
    end
    if 1 + countDir(0,1) + countDir(0,-1) >= 4 then return true end
    if 1 + countDir(1,0) + countDir(-1,0) >= 4 then return true end
    if 1 + countDir(-1,1) + countDir(1,-1) >= 4 then return true end
    if 1 + countDir(-1,-1) + countDir(1,1) >= 4 then return true end
    return false
end

-- Check if grid is full
local function isFull(grid)
    for c = 1, COLS do
        if grid[1][c] == 0 then return false end
    end
    return true
end

-- Minimax with alpha-beta pruning
-- maximizing = true means it's player 1's turn to move
local function minimax(grid, depth, alpha, beta, maximizing)
    -- Check terminal states
    if depth == 0 then
        return evaluate(grid)
    end
    if isFull(grid) then
        return 0
    end

    if maximizing then
        local best = -1e9
        for _, col in ipairs(COL_ORDER) do
            local new_grid, row = simulateDrop(grid, col, 1)
            if new_grid and row then
                local val
                if checkWinGrid(new_grid, row, col, 1) then
                    val = 10000 + depth  -- prefer sooner wins
                else
                    val = minimax(new_grid, depth - 1, alpha, beta, false)
                end
                if val > best then best = val end
                if best > alpha then alpha = best end
                if alpha >= beta then break end
            end
        end
        return best
    else
        local best = 1e9
        for _, col in ipairs(COL_ORDER) do
            local new_grid, row = simulateDrop(grid, col, 2)
            if new_grid and row then
                local val
                if checkWinGrid(new_grid, row, col, 2) then
                    val = -10000 - depth  -- prefer sooner wins for player 2
                else
                    val = minimax(new_grid, depth - 1, alpha, beta, true)
                end
                if val < best then best = val end
                if best < beta then beta = best end
                if alpha >= beta then break end
            end
        end
        return best
    end
end

-- ---------------------------------------------------------------------------
-- Public AI entry point
-- Returns best column (1-7) or nil if no move available.
-- depth: easy=3, medium=5, hard=7
-- AI always plays as player 2 by convention in single-player mode, but the
-- minimax is called from the current player's perspective.
-- ---------------------------------------------------------------------------

function P4Board:getAIMove(depth)
    depth = depth or 5
    if self.status ~= "playing" then return nil end

    local current = self.turn        -- 1 or 2
    local maximizing_root = (current == 1)

    local best_col = nil
    local best_val = maximizing_root and -1e9 or 1e9

    -- Immediate win check (depth 1)
    for _, col in ipairs(COL_ORDER) do
        local new_grid, row = simulateDrop(self.grid, col, current)
        if new_grid and row then
            if checkWinGrid(new_grid, row, col, current) then
                return col  -- take immediate win
            end
        end
    end

    -- Block opponent's immediate win
    local opponent = (current == 1) and 2 or 1
    for _, col in ipairs(COL_ORDER) do
        local new_grid, row = simulateDrop(self.grid, col, opponent)
        if new_grid and row then
            if checkWinGrid(new_grid, row, col, opponent) then
                -- Check this column is actually playable for current player
                local cg, _ = simulateDrop(self.grid, col, current)
                if cg then
                    best_col = col
                end
            end
        end
    end
    if best_col then return best_col end

    -- Full minimax search
    for _, col in ipairs(COL_ORDER) do
        local new_grid, row = simulateDrop(self.grid, col, current)
        if new_grid and row then
            local val
            if maximizing_root then
                val = minimax(new_grid, depth - 1, -1e9, 1e9, false)
            else
                val = minimax(new_grid, depth - 1, -1e9, 1e9, true)
            end

            if maximizing_root then
                if val > best_val then
                    best_val = val
                    best_col = col
                end
            else
                if val < best_val then
                    best_val = val
                    best_col = col
                end
            end
        end
    end

    return best_col
end

-- ---------------------------------------------------------------------------
-- Serialize / Load
-- ---------------------------------------------------------------------------

function P4Board:serialize()
    local grid_copy = {}
    for r = 1, ROWS do
        grid_copy[r] = {}
        for c = 1, COLS do
            grid_copy[r][c] = self.grid[r][c]
        end
    end
    return {
        grid     = grid_copy,
        turn     = self.turn,
        status   = self.status,
        winner   = self.winner,
        last_col = self.last_col,
        last_row = self.last_row,
    }
end

function P4Board:load(data)
    if type(data) ~= "table" or type(data.grid) ~= "table" then
        return false
    end
    for r = 1, ROWS do
        if type(data.grid[r]) ~= "table" then return false end
        for c = 1, COLS do
            local v = data.grid[r][c]
            if type(v) ~= "number" or v < 0 or v > 2 then return false end
            self.grid[r][c] = v
        end
    end
    self.turn     = (data.turn == 2) and 2 or 1
    self.status   = (data.status == "won" or data.status == "draw") and data.status or "playing"
    self.winner   = data.winner
    self.last_col = data.last_col
    self.last_row = data.last_row
    return true
end

return P4Board
