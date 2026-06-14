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

local ButtonTable     = require("ui/widget/buttontable")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("gettext")

local MenuHelper  = require("menu_helper")
local ScreenBase  = require("screen_base")

local P4Board       = lrequire("board")
local P4BoardWidget = lrequire("board_widget")

local DeviceScreen = Device.screen

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

function P4Screen:serializeState()
    return self.board:serialize()
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function P4Screen:buildLayout()
    local board = self.board

    self.board_widget = P4BoardWidget:new{
        board        = board,
        onCellAction = function(col) self:onColumnTap(col) end,
    }

    local is_landscape = self:isLandscape()
    local sw = DeviceScreen:getWidth()

    local board_frame = FrameContainer:new{
        padding = Size.padding.default,
        margin  = Size.margin.default,
        self.board_widget,
    }

    local board_frame_size = self.board_widget.size
        + (Size.padding.default + Size.margin.default) * 2

    local button_width
    if is_landscape then
        local right_w = sw - board_frame_size - Size.span.horizontal_default * 2
        button_width  = math.max(right_w - Size.span.horizontal_default, 100)
    else
        button_width = math.floor(sw * 0.94)
    end

    -- Column selector buttons 1-7 (above the board in portrait)
    local col_buttons_row = {}
    for c = 1, 7 do
        local col = c
        col_buttons_row[#col_buttons_row + 1] = {
            text     = tostring(c),
            callback = function() self:onColumnTap(col) end,
        }
    end
    local col_buttons = ButtonTable:new{
        width                 = board_frame_size,
        shrink_unneeded_width = true,
        buttons               = { col_buttons_row },
    }
    self.col_buttons = col_buttons

    -- Action buttons: New | Players | Difficulty | Close
    local action_buttons = ButtonTable:new{
        width                 = button_width,
        shrink_unneeded_width = true,
        buttons = {{
            { text = _("Nouveau"),   callback = function() self:onNewGame() end },
            { text = self:_playersLabel(),
              id   = "players_btn",
              callback = function() self:openPlayersMenu() end },
            { text = self:_diffLabel(),
              id   = "diff_btn",
              callback = function() self:openDifficultyMenu() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
            self:makeCloseButtonConfig(),
        }},
    }
    self.action_buttons = action_buttons

    if is_landscape then
        -- Landscape: board + column buttons on left, controls on right
        local board_col = VerticalGroup:new{
            align = "center",
            col_buttons,
            VerticalSpan:new{ width = Size.span.vertical_default },
            board_frame,
        }
        local right_panel = VerticalGroup:new{
            align = "center",
            action_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
        }
        self.layout = HorizontalGroup:new{
            align = "center",
            board_col,
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            right_panel,
        }
    else
        -- Portrait: action buttons top, then column buttons, then board, then status
        self.layout = VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ width = Size.span.vertical_large },
            action_buttons,
            VerticalSpan:new{ width = Size.span.vertical_default },
            col_buttons,
            board_frame,
            VerticalSpan:new{ width = Size.span.vertical_default },
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
        }
    end

    self[1] = self.layout
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
        self:updateStatus(_("Colonne pleine, choisissez une autre."))

    elseif result == "won" then
        self.plugin:saveState(self:serializeState())
        local w = self:_winnerLabel(self.board.winner)
        self:updateStatus(w .. " " .. _("gagne !"))
        self:showMessage(w .. " " .. _("gagne !"), 3)

    elseif result == "draw" then
        self.plugin:saveState(self:serializeState())
        self:updateStatus(_("Match nul !"))
        self:showMessage(_("Match nul !"), 3)

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
    self:updateStatus(_("L'IA réfléchit..."))

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
                self:updateStatus(w .. " " .. _("gagne !"))
                self:showMessage(w .. " " .. _("gagne !"), 3)
            elseif result == "draw" then
                self:updateStatus(_("Match nul !"))
                self:showMessage(_("Match nul !"), 3)
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
            status = self:_winnerLabel(board.winner) .. " " .. _("gagne !")
        elseif board.status == "draw" then
            status = _("Match nul !")
        else
            local turn_label = self:_playerLabel(board.turn)
            status = turn_label .. " " .. _("joue")
            if players == 1 then
                local pc = self.plugin:getSetting("player_num", 1)
                local ai_num  = (pc == 1) and 2 or 1
                local ai_name = self:_playerLabel(ai_num)
                status = status .. "  ·  " .. dlabel .. " " .. string.format(_("(IA=%s)"), ai_name)
            end
        end
    end
    ScreenBase.updateStatus(self, status)
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

function P4Screen:_playerLabel(num)
    if num == 1 then
        return _("Joueur 1 (Jaune)")
    else
        return _("Joueur 2 (Rouge)")
    end
end

function P4Screen:_winnerLabel(num)
    if num == 1 then
        return _("Joueur 1 (Jaune)")
    else
        return _("Joueur 2 (Rouge)")
    end
end

function P4Screen:_playersLabel()
    local players = self.plugin:getSetting("players", 1)
    return players == 1 and _("1 joueur") or _("2 joueurs")
end

function P4Screen:_diffLabel()
    local diff = self.plugin:getSetting("difficulty", "medium")
    return MenuHelper.DIFFICULTY_LABELS[diff] or diff
end

-- ---------------------------------------------------------------------------
-- Menus
-- ---------------------------------------------------------------------------

function P4Screen:openPlayersMenu()
    local players = self.plugin:getSetting("players", 1)
    MenuHelper.openPickerMenu{
        title      = _("Mode de jeu"),
        items      = {
            { id = 1, text = _("1 joueur (contre IA)") },
            { id = 2, text = _("2 joueurs") },
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
        title      = _("Vous jouez en tant que"),
        items      = {
            { id = 1, text = _("1er joueur (Jaune)") },
            { id = 2, text = _("2ème joueur (Rouge)") },
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
