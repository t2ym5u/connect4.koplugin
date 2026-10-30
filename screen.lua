-- ---------------------------------------------------------------------------
-- P4Screen — Connect Four (Puissance 4) game screen
-- ---------------------------------------------------------------------------

local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local MenuHelper  = require("menu_helper")
local ScreenBase  = require("screen_base")

local P4Board       = lrequire("board")
local P4BoardWidget = lrequire("board_widget")

-- ---------------------------------------------------------------------------
-- P4Screen
-- ---------------------------------------------------------------------------

local GAME_RULES_EN = _([[
Connect Four (Puissance 4) — Rules

Two players alternate dropping coloured pieces into the grid.

Rules:
• Tap a column to drop your piece into it — it falls to the lowest empty row.
• The first player to connect four pieces in a row wins.
• Four in a row may be horizontal, vertical, or diagonal.
• If the entire board fills with no winner, the game is a draw.
]])

local GAME_RULES_FR = [[
Puissance 4 — Règles

Deux joueurs font tomber alternativement des pions colorés dans la grille.

Règles :
• Appuyez sur une colonne pour y faire tomber votre pion — il tombe dans la case vide la plus basse.
• Le premier joueur à aligner quatre pions gagne.
• L'alignement peut être horizontal, vertical ou diagonal.
• Si toute la grille est remplie sans gagnant, la partie est nulle.
]]

local P4Screen = ScreenBase:extend{}

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function P4Screen:init()
    local state = self.plugin:loadState()
    self.board  = P4Board:new()
    if not self.board:load(state) then
        self.board:reset()
    end
    ScreenBase.init(self)  -- calls buildLayout()
    if self:_isAITurn() then
        self:triggerAI()
    end
end

-- Four in a row or a full grid ends the game.
function P4Screen:isRoundOver()
    return self.board.status ~= "playing"
end

function P4Screen:serializeState()
    return self.board:serialize()
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function P4Screen:buildLayout()
    local is_landscape = self:isLandscape()

    -- Title bar with Options menu
    local title_bar = self:buildTitleBar(_("Connect Four"), function()
        return {
            { text = _("New game"),         callback = function() self:onNewGame() end },
            { text = self:_diffLabel(),     callback = function() self:openDifficultyMenu() end },
            { text = self:_playersLabel(),  callback = function() self:openPlayersMenu() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

    local controls_w = self:getControlsWidth()
    self.status_text:setMaxWidth(controls_w)
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
    }

    -- Column selector 1-7 above the board. It is built at the board's width
    -- so each key sits over its column; a first copy only measures its height.
    -- It is the game's action bar: once the game is over it offers New game.
    local function buildColumnPad(width)
        local keys = {}
        for c = 1, 7 do
            local col = c
            keys[c] = { text = tostring(c), callback = function() self:onColumnTap(col) end }
        end
        return self:buildActionBar({ keys }, width)
    end
    local pad_h = buildColumnPad(controls_w):getSize().h + Size.span.vertical_default

    -- The widget paints its own thick outer border, so the frame has none.
    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    self.board_widget = P4BoardWidget:new{
        board        = self.board,
        max_width    = budget_w,
        max_height   = budget_h - pad_h,
        onCellAction = function(col) self:onColumnTap(col) end,
    }
    local board_frame = FrameContainer:new{
        padding    = 0,
        margin     = 0,
        bordersize = 0,
        self.board_widget,
    }
    self.col_buttons = buildColumnPad(self.board_widget:getSize().w)
    local board_col = VerticalGroup:new{
        align = "center",
        self.col_buttons,
        VerticalSpan:new{ width = Size.span.vertical_default },
        board_frame,
    }

    if is_landscape then
        local content = HorizontalGroup:new{
            align = "center",
            board_col,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        }
        self:buildLandscapeLayout(title_bar, content)
    else
        self:buildPortraitLayout(title_bar, board_col,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

-- ---------------------------------------------------------------------------
-- Column tap handler (human move)
-- ---------------------------------------------------------------------------

function P4Screen:onColumnTap(col)
    if self.board.status ~= "playing" then return end
    if self:_isAITurn() then return end

    local result = self.board:dropPiece(col)
    self.board_widget:refresh()

    if result == "full" then
        self:updateStatus(_("Column full, choose another one."))

    elseif result == "won" then
        self.plugin:saveState(self:serializeState())
        local w = self:_winnerLabel(self.board.winner)
        self:updateStatus(w .. " " .. _("wins!"))
        self:showMessage(w .. " " .. _("wins!"), 3)

    elseif result == "draw" then
        self.plugin:saveState(self:serializeState())
        self:updateStatus(_("Draw!"))
        self:showMessage(_("Draw!"), 3)

    else  -- "ok"
        self.plugin:saveState(self:serializeState())
        self:updateStatus()
        if self:_isAITurn() then
            self:triggerAI()
        end
    end
end

-- ---------------------------------------------------------------------------
-- AI trigger
-- ---------------------------------------------------------------------------

function P4Screen:_isAITurn()
    if self.plugin:getSetting("players", 1) ~= 1 then return false end
    local pc = self.plugin:getSetting("player_num", 1)  -- human is player pc
    return self.board.turn ~= pc and self.board.status == "playing"
end

function P4Screen:triggerAI()
    if self.board.status ~= "playing" then return end
    self:updateStatus(_("AI is thinking..."))

    local diff  = self.plugin:getSetting("difficulty", "medium")
    local depth = (diff == "easy") and 3 or (diff == "hard") and 7 or 5

    UIManager:scheduleIn(0.05, function()
        if self.board.status ~= "playing" then return end
        local col = self.board:getAIMove(depth)
        if col then
            local result = self.board:dropPiece(col)
            self.board_widget:refresh()
            self.plugin:saveState(self:serializeState())

            if result == "won" then
                local w = self:_winnerLabel(self.board.winner)
                self:updateStatus(w .. " " .. _("wins!"))
                self:showMessage(w .. " " .. _("wins!"), 3)
            elseif result == "draw" then
                self:updateStatus(_("Draw!"))
                self:showMessage(_("Draw!"), 3)
            else
                self:updateStatus()
            end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- New game
-- ---------------------------------------------------------------------------

function P4Screen:onNewGame()
    self.board:reset()
    self.plugin:saveState(self:serializeState())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
    if self:_isAITurn() then
        UIManager:scheduleIn(0.1, function() self:triggerAI() end)
    end
end

-- ---------------------------------------------------------------------------
-- Status bar
-- ---------------------------------------------------------------------------

function P4Screen:updateStatus(msg)
    local status
    if msg then
        status = msg
    else
        local board   = self.board
        local players = self.plugin:getSetting("players", 1)
        local diff    = self.plugin:getSetting("difficulty", "medium")
        local dlabel  = MenuHelper.DIFFICULTY_LABELS[diff] or diff

        if board.status == "won" then
            status = self:_winnerLabel(board.winner) .. " " .. _("wins!")
        elseif board.status == "draw" then
            status = _("Draw!")
        else
            status = self:joinStatus(
                T("%1×%2", 7, 6),
                players == 1 and dlabel or nil,
                T(_("Turn: %1"), self:_playerLabel(board.turn)))
        end
    end
    ScreenBase.updateStatus(self, status)
    -- Every drop (player's or AI's) ends here.
    self:refreshActionBar()
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

function P4Screen:_playerLabel(num)
    if num == 1 then
        return _("Player 1 (Yellow)")
    else
        return _("Player 2 (Red)")
    end
end

function P4Screen:_winnerLabel(num)
    if num == 1 then
        return _("Player 1 (Yellow)")
    else
        return _("Player 2 (Red)")
    end
end

function P4Screen:_playersLabel()
    return T(_("Players: %1"), self.plugin:getSetting("players", 1))
end

function P4Screen:_diffLabel()
    local diff = self.plugin:getSetting("difficulty", "medium")
    return T(_("Difficulty: %1"), MenuHelper.DIFFICULTY_LABELS[diff] or diff)
end

-- ---------------------------------------------------------------------------
-- Menus
-- ---------------------------------------------------------------------------

function P4Screen:openPlayersMenu()
    local players = self.plugin:getSetting("players", 1)
    MenuHelper.openPickerMenu{
        title      = _("Players"),
        items      = {
            { id = 1, text = _("1 player (vs AI)") },
            { id = 2, text = _("2 players") },
        },
        current_id = players,
        on_select  = function(id)
            self.plugin:saveSetting("players", id)
            -- Update button label
            local btn = self.action_buttons and self.action_buttons:getButtonById("players_btn")
            if btn then btn:setText(self:_playersLabel(), btn.width) end
            if id == 1 then
                self:openPlayerNumMenu()
            else
                self:updateStatus()
            end
        end,
        parent = self,
    }
end

function P4Screen:openPlayerNumMenu()
    local pc = self.plugin:getSetting("player_num", 1)
    MenuHelper.openPickerMenu{
        title      = _("You are playing as"),
        items      = {
            { id = 1, text = _("1st player (Yellow)") },
            { id = 2, text = _("2nd player (Red)") },
        },
        current_id = pc,
        on_select  = function(id)
            self.plugin:saveSetting("player_num", id)
            self:updateStatus()
            -- If it's now the AI's turn on the current board, trigger
            if self:_isAITurn() and self.board.status == "playing" then
                self:triggerAI()
            end
        end,
        parent = self,
    }
end

function P4Screen:openDifficultyMenu()
    MenuHelper.openDifficultyMenu{
        current   = self.plugin:getSetting("difficulty", "medium"),
        on_select = function(id)
            self.plugin:saveSetting("difficulty", id)
            local btn = self.action_buttons and self.action_buttons:getButtonById("diff_btn")
            if btn then btn:setText(self:_diffLabel(), btn.width) end
            self:updateStatus()
        end,
        parent = self,
    }
end

return P4Screen
