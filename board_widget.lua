-- ---------------------------------------------------------------------------
-- P4BoardWidget — renders the Connect Four board (6 rows × 7 cols)
-- Extends GridWidgetBase
--
-- Player 1 = Yellow  → drawn as solid BLACK square (e-ink: dark)
-- Player 2 = Red     → drawn as WHITE square with BLACK border (e-ink: light)
-- Empty cell         → GRAY_D circle (light gray hole)
-- Frame background   → GRAY_4 (dark board)
-- Last-drop column   → subtle GRAY_9 highlight stripe behind cells
-- ---------------------------------------------------------------------------

local Blitbuffer  = require("ffi/blitbuffer")
local Geom        = require("ui/geometry")

local gwb            = require("grid_widget_base")
local GridWidgetBase = gwb.GridWidgetBase
local drawLine       = gwb.drawLine

-- Colors
local C_FRAME      = Blitbuffer.COLOR_GRAY_4   -- board frame / dark slots
local C_EMPTY      = Blitbuffer.COLOR_GRAY_D   -- empty cell
local C_HIGHLIGHT  = Blitbuffer.COLOR_GRAY_9   -- last-drop column tint
local C_P1_FILL    = Blitbuffer.COLOR_BLACK    -- player 1 piece (yellow → black on e-ink)
local C_P1_BORDER  = Blitbuffer.COLOR_GRAY_4
local C_P2_FILL    = Blitbuffer.COLOR_WHITE    -- player 2 piece (red → white on e-ink)
local C_P2_BORDER  = Blitbuffer.COLOR_BLACK
local C_BORDER     = Blitbuffer.COLOR_BLACK

-- ---------------------------------------------------------------------------
-- P4BoardWidget
-- ---------------------------------------------------------------------------

local P4BoardWidget = GridWidgetBase:extend{
    board        = nil,
    size_ratio   = 0.85,
    onCellAction = nil,  -- callback(col)
}

function P4BoardWidget:init()
    self.cols = 7
    self.rows = 6
    GridWidgetBase.init(self)
end

-- Tapping anywhere in a column triggers a drop in that column.
function P4BoardWidget:onCellTap(r, c)
    if self.onCellAction then
        self.onCellAction(c)
    end
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

function P4BoardWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.dimen.w, h = self.dimen.h }

    local board = self.board
    local cw    = self.cell_w
    local ch    = self.cell_h
    local size  = self.size

    -- Background: dark frame fills the entire widget
    bb:paintRect(x, y, size, size, C_FRAME)

    -- Highlight last-drop column
    local last_col = board and board.last_col
    if last_col then
        local hx = x + math.floor((last_col - 1) * cw)
        bb:paintRect(hx, y, math.ceil(cw), size, C_HIGHLIGHT)
    end

    -- Draw each cell
    for r = 1, 6 do
        for c = 1, 7 do
            local cx = x + math.floor((c - 1) * cw)
            local cy = y + math.floor((r - 1) * ch)
            local cew = math.ceil(cw)
            local ceh = math.ceil(ch)

            -- Padding around the piece
            local pad = math.max(3, math.floor(math.min(cw, ch) * 0.10))
            local pw  = cew - 2 * pad
            local ph  = ceh - 2 * pad
            if pw < 1 then pw = 1 end
            if ph < 1 then ph = 1 end

            local val = board and board.grid[r][c] or 0

            if val == 0 then
                -- Empty: light gray square (simulates a round hole)
                bb:paintRect(cx + pad, cy + pad, pw, ph, C_EMPTY)

            elseif val == 1 then
                -- Player 1: solid dark square
                bb:paintRect(cx + pad, cy + pad, pw, ph, C_P1_FILL)
                -- Inner border for definition
                local bw = math.max(1, math.floor(math.min(pw, ph) * 0.06))
                bb:paintRect(cx+pad,        cy+pad,        pw, bw,  C_P1_BORDER)
                bb:paintRect(cx+pad,        cy+pad+ph-bw,  pw, bw,  C_P1_BORDER)
                bb:paintRect(cx+pad,        cy+pad,        bw, ph,  C_P1_BORDER)
                bb:paintRect(cx+pad+pw-bw,  cy+pad,        bw, ph,  C_P1_BORDER)

            else
                -- Player 2: white square with black border
                local bw = math.max(1, math.floor(math.min(pw, ph) * 0.08))
                bb:paintRect(cx + pad, cy + pad, pw, ph, C_P2_FILL)
                bb:paintRect(cx+pad,        cy+pad,        pw, bw,  C_P2_BORDER)
                bb:paintRect(cx+pad,        cy+pad+ph-bw,  pw, bw,  C_P2_BORDER)
                bb:paintRect(cx+pad,        cy+pad,        bw, ph,  C_P2_BORDER)
                bb:paintRect(cx+pad+pw-bw,  cy+pad,        bw, ph,  C_P2_BORDER)
            end
        end
    end

    -- Grid lines (thin separators between cells, over the frame)
    local line_color = Blitbuffer.COLOR_GRAY_4
    for i = 1, 6 do  -- 6 vertical lines (between 7 columns)
        local lx = x + math.floor(i * cw)
        drawLine(bb, lx, y, 1, size, line_color)
    end
    for i = 1, 5 do  -- 5 horizontal lines (between 6 rows)
        local ly = y + math.floor(i * ch)
        drawLine(bb, x, ly, size, 1, line_color)
    end

    -- Outer border
    local thick = math.max(2, math.floor(math.min(cw, ch) * 0.06))
    bb:paintRect(x,           y,            size,  thick, C_BORDER)
    bb:paintRect(x,           y+size-thick, size,  thick, C_BORDER)
    bb:paintRect(x,           y,            thick, size,  C_BORDER)
    bb:paintRect(x+size-thick, y,           thick, size,  C_BORDER)
end

return P4BoardWidget
