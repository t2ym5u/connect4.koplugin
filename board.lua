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
-- AI — iterative-deepening alpha-beta (negamax) under a time budget
--
-- The search runs on a flat, padded copy of the grid (square (r, c) is
-- r * W + c, with a border of sentinels) and drops/lifts pieces in place,
-- instead of copying the whole grid for every simulated drop. The evaluation
-- is unchanged and still from player 1's perspective; negamax just flips its
-- sign for player 2.
-- ---------------------------------------------------------------------------

-- Scales every time budget. A test harness sets it below 1 to reproduce on
-- a desktop the depth an e-reader CPU (~25x slower) reaches in the budget.
P4Board.AI_TIME_SCALE = 1

local clock = os.clock
local INF   = 1e9
local W     = COLS + 2      -- padded row width
local EDGE  = 3             -- sentinel value

local function sq(r, c) return r * W + c end

-- Every window of 4 cells, as flat indices (horizontal, vertical, both
-- diagonals), plus the centre column.
local WINDOWS = {}
local function addWindow(r, c, dr, dc)
    WINDOWS[#WINDOWS + 1] = { sq(r, c), sq(r + dr, c + dc),
                              sq(r + 2 * dr, c + 2 * dc), sq(r + 3 * dr, c + 3 * dc) }
end
for r = 1, ROWS do for c = 1, COLS - 3 do addWindow(r, c, 0, 1) end end
for r = 1, ROWS - 3 do for c = 1, COLS do addWindow(r, c, 1, 0) end end
for r = 1, ROWS - 3 do for c = 1, COLS - 3 do addWindow(r, c, 1, 1) end end
for r = 4, ROWS do for c = 1, COLS - 3 do addWindow(r, c, -1, 1) end end
local NWIN = #WINDOWS
local CENTRE = {}
for r = 1, ROWS do CENTRE[r] = sq(r, 4) end

-- Static evaluation from player 1's perspective: centre column +/-3 per
-- piece; per window with only one colour in it, 100 for four, 5 for three
-- and 2 for two (unchanged from the grid version).
local function evaluate(g)
    local score = 0
    for r = 1, ROWS do
        local v = g[CENTRE[r]]
        if v == 1 then score = score + 3 elseif v == 2 then score = score - 3 end
    end
    for i = 1, NWIN do
        local w = WINDOWS[i]
        local p1, p2 = 0, 0
        for k = 1, 4 do
            local v = g[w[k]]
            if v == 1 then p1 = p1 + 1 elseif v == 2 then p2 = p2 + 1 end
        end
        if p2 == 0 then
            if p1 == 4 then score = score + 100
            elseif p1 == 3 then score = score + 5
            elseif p1 == 2 then score = score + 2 end
        elseif p1 == 0 then
            if p2 == 4 then score = score - 100
            elseif p2 == 3 then score = score - 5
            elseif p2 == 2 then score = score - 2 end
        end
    end
    return score
end

local WIN_DIRS = { 1, W, W + 1, W - 1 }

-- Does the piece of `p` at flat square s complete four in a row?
local function isWin(g, s, p)
    for k = 1, 4 do
        local d = WIN_DIRS[k]
        local n = 1
        local t = s + d
        while g[t] == p do n = n + 1; t = t + d end
        t = s - d
        while g[t] == p do n = n + 1; t = t - d end
        if n >= 4 then return true end
    end
    return false
end

-- Search state (one search at a time).
local g, height          -- flat grid; height[c] = row a piece dropped in c lands on (0 = full)
local deadline, aborted, nodes

local function timeUp()
    nodes = nodes + 1
    if deadline and nodes % 256 == 0 and clock() > deadline then
        aborted = true
    end
    return aborted
end

-- Negamax: value for the side to move `me`. Wins score 10000 + remaining
-- depth so that sooner wins are preferred, as before.
local function search(depth, alpha, beta, me)
    if timeUp() then return 0 end
    if depth == 0 then
        local e = evaluate(g)
        return me == 1 and e or -e
    end
    local op = 3 - me
    local best = -INF
    for i = 1, COLS do
        local col = COL_ORDER[i]
        local r = height[col]
        if r > 0 then
            local s = sq(r, col)
            local v
            g[s] = me
            if isWin(g, s, me) then
                v = 10000 + depth
            else
                height[col] = r - 1
                v = -search(depth - 1, -beta, -alpha, op)
                height[col] = r
            end
            g[s] = 0
            if aborted then return 0 end
            if v > best then
                best = v
                if v > alpha then
                    alpha = v
                    if alpha >= beta then break end
                end
            end
        end
    end
    if best == -INF then return 0 end   -- board full: draw
    return best
end

local RANK = {}
for i, col in ipairs(COL_ORDER) do RANK[col] = i end

-- One root iteration at `depth`. Ties go to the column earliest in
-- COL_ORDER, like the old fixed-depth engine, so an unbudgeted search
-- plays exactly the column it used to.
-- Returns the best column of those fully searched (nil if none), whether
-- every column was searched, and the scores.
local function searchRoot(root, depth, me)
    local op = 3 - me
    local best_col, best_v = nil, -INF
    local scores = {}
    for i = 1, #root do
        local col = root[i]
        local r = height[col]
        local s = sq(r, col)
        -- A column that would win a tie must prove it ties: search it with
        -- a window one point lower so an equal score comes back exact.
        local a = best_v
        if best_col and RANK[col] < RANK[best_col] then a = best_v - 1 end
        g[s] = me
        height[col] = r - 1
        local v = -search(depth - 1, -INF, -a, op)
        height[col] = r
        g[s] = 0
        if aborted then return best_col, false, scores end
        scores[col] = v
        if v > best_v or (v == best_v and best_col and RANK[col] < RANK[best_col]) then
            best_v, best_col = v, col
        end
    end
    return best_col, true, scores
end

-- ---------------------------------------------------------------------------
-- Public AI entry point
-- Returns best column (1-7) or nil if no move available.
-- depth:  maximum search depth (easy=3, medium=5, hard=7).
-- budget: seconds of thinking allowed (on the e-reader), or nil for no
--         limit. Search deepens one ply at a time up to `depth` and keeps
--         the best column of the deepest iteration that had time to finish.
-- AI always plays as player 2 by convention in single-player mode, but the
-- search is run from the current player's perspective.
-- ---------------------------------------------------------------------------

function P4Board:getAIMove(depth, budget)
    depth = depth or 5
    if self.status ~= "playing" then return nil end

    local current  = self.turn        -- 1 or 2
    local opponent = (current == 1) and 2 or 1

    g, height = {}, {}
    for i = 0, (ROWS + 2) * W - 1 do g[i] = EDGE end
    for c = 1, COLS do
        height[c] = 0
        for r = 1, ROWS do
            g[sq(r, c)] = self.grid[r][c]
            if self.grid[r][c] == 0 then height[c] = r end
        end
    end

    local root = {}
    for _, col in ipairs(COL_ORDER) do
        if height[col] > 0 then root[#root + 1] = col end
    end
    if #root == 0 then return nil end

    -- Immediate win check (depth 1)
    for _, col in ipairs(root) do
        local s = sq(height[col], col)
        g[s] = current
        local win = isWin(g, s, current)
        g[s] = 0
        if win then return col end   -- take immediate win
    end

    -- Block opponent's immediate win
    local block
    for _, col in ipairs(root) do
        local s = sq(height[col], col)
        g[s] = opponent
        if isWin(g, s, opponent) then block = col end
        g[s] = 0
    end
    if block then return block end

    deadline = budget and (clock() + budget * P4Board.AI_TIME_SCALE) or nil
    aborted, nodes = false, 0

    -- Fallback if not even depth 1 finishes: the most central column.
    local best_col = root[1]
    self.ai_depth = 0
    for d = 1, depth do
        local col, complete, scores = searchRoot(root, d, current)
        if complete then
            best_col = col
            self.ai_depth = d
            -- Next iteration: best column first, then by this one's scores.
            table.sort(root, function(x, y)
                if x == col then return y ~= col end
                if y == col then return false end
                if scores[x] ~= scores[y] then return scores[x] > scores[y] end
                return RANK[x] < RANK[y]
            end)
        else
            -- The previous best is searched first, so a column that beat it
            -- in this unfinished iteration is a better-informed choice.
            if col and scores[root[1]] then best_col = col end
            break
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
