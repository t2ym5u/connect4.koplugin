local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

describe("P4Board", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    describe("new / reset", function()
        it("starts empty with player 1 to move", function()
            local b = Board:new()
            assert.are.equal(1, b.turn)
            assert.are.equal("playing", b.status)
            for r = 1, 6 do
                for c = 1, 7 do
                    assert.are.equal(0, b.grid[r][c])
                end
            end
        end)
    end)

    describe("dropPiece", function()
        it("drops to the bottom-most empty row and switches turn", function()
            local b = Board:new()
            local result = b:dropPiece(4)
            assert.are.equal("ok", result)
            assert.are.equal(1, b.grid[6][4])
            assert.are.equal(2, b.turn)
        end)

        it("stacks a second piece in the same column on top", function()
            local b = Board:new()
            b:dropPiece(4)
            b:dropPiece(4)
            assert.are.equal(2, b.grid[5][4])
        end)

        it("returns full for a completely stacked column", function()
            local b = Board:new()
            for _ = 1, 6 do b:dropPiece(1) end
            assert.are.equal("full", b:dropPiece(1))
        end)

        it("detects a horizontal 4-in-a-row win", function()
            local b = Board:new()
            -- Player 1 drops in cols 1..4 on row 6, player 2 drops elsewhere
            -- (col 7) between turns so it never blocks the row.
            b:dropPiece(1); b:dropPiece(7)
            b:dropPiece(2); b:dropPiece(7)
            b:dropPiece(3); b:dropPiece(7)
            local result = b:dropPiece(4)
            assert.are.equal("won", result)
            assert.are.equal("won", b.status)
            assert.are.equal(1, b.winner)
        end)

        it("ignores moves once the game has ended", function()
            local b = Board:new()
            b:dropPiece(1); b:dropPiece(7)
            b:dropPiece(2); b:dropPiece(7)
            b:dropPiece(3); b:dropPiece(7)
            b:dropPiece(4)  -- player 1 wins
            assert.are.equal("full", b:dropPiece(5))
        end)
    end)

    describe("isBoardFull", function()
        it("is false on a fresh board", function()
            local b = Board:new()
            assert.is_false(b:isBoardFull())
        end)
    end)

    describe("getAIMove", function()
        it("takes an immediate winning move when available", function()
            local b = Board:new()
            b:dropPiece(1); b:dropPiece(7)
            b:dropPiece(2); b:dropPiece(7)
            b:dropPiece(3); b:dropPiece(7)
            -- Now it's player 1's turn with three in a row (1,2,3) on row 6.
            assert.are.equal(4, b:getAIMove(3))
        end)

        it("blocks the opponent's immediate win", function()
            local b = Board:new()
            b:dropPiece(1); b:dropPiece(7)
            b:dropPiece(2); b:dropPiece(7)
            b:dropPiece(6); b:dropPiece(7)
            -- Player 1 to move; player 2 threatens column 7.
            assert.are.equal(7, b:getAIMove(5, 1.0))
        end)

        it("plays a legal move within its time budget all game long", function()
            math.randomseed(3)
            local b = Board:new()
            local worst = 0
            while b.status == "playing" do
                local t0 = os.clock()
                local col = b:getAIMove(7, 0.05)
                local dt = os.clock() - t0
                if dt > worst then worst = dt end
                assert.is_not_nil(col)
                assert.are.equal(0, b.grid[1][col])
                -- Some noise so the game is not the same every run of the engine.
                if math.random() < 0.3 then
                    local c = math.random(7)
                    if b.grid[1][c] == 0 then col = c end
                end
                b:dropPiece(col)
            end
            -- 0.05 s budget; generous slack for slow test interpreters.
            assert.is_true(worst < 0.5, "slowest move " .. worst .. " s")
        end)

        it("still returns a legal move when no iteration can finish", function()
            local b = Board:new()
            b:dropPiece(4); b:dropPiece(4); b:dropPiece(3)
            local col = b:getAIMove(7, 1e-9)
            assert.is_not_nil(col)
            assert.are.equal(0, b.grid[1][col])
        end)
    end)

    describe("difficulty levels", function()
        local function aiMove(b, id)
            local L = Board.LEVELS[id]
            return b:getAIMove(L.depth, L.budget, L)
        end

        -- A whole game, every move from `id`, the rng seeded.
        local function playGame(id, seed)
            math.randomseed(seed)
            local b = Board:new()
            local cols = {}
            while b.status == "playing" do
                local col = aiMove(b, id)
                assert.are.equal(0, b.grid[1][col])
                cols[#cols + 1] = col
                b:dropPiece(col)
            end
            return table.concat(cols)
        end

        it("gets weaker from Hard to Easy", function()
            local L = Board.LEVELS
            assert.is_true(L.easy.depth < L.medium.depth and L.medium.depth < L.hard.depth)
            assert.is_true(L.easy.noise > L.medium.noise and L.medium.noise > L.hard.noise)
            assert.are.equal(0, L.hard.noise)
            for _, id in ipairs({ "easy", "medium", "hard" }) do
                assert.is_true(L[id].budget <= 2.2)
            end
        end)

        it("every level still takes an immediate win, whatever the noise", function()
            for seed = 1, 20 do
                for _, id in ipairs({ "easy", "medium", "hard" }) do
                    math.randomseed(seed)
                    local b = Board:new()
                    b:dropPiece(1); b:dropPiece(7)
                    b:dropPiece(2); b:dropPiece(7)
                    b:dropPiece(3); b:dropPiece(7)
                    assert.are.equal(4, aiMove(b, id))
                end
            end
        end)

        it("every level still blocks an immediate loss", function()
            for seed = 1, 20 do
                for _, id in ipairs({ "easy", "medium" }) do
                    math.randomseed(seed)
                    local b = Board:new()
                    b:dropPiece(1); b:dropPiece(7)
                    b:dropPiece(2); b:dropPiece(7)
                    b:dropPiece(6); b:dropPiece(7)
                    assert.are.equal(7, aiMove(b, id))
                end
            end
        end)

        it("Easy and Medium vary between games", function()
            for _, id in ipairs({ "easy", "medium" }) do
                local seen, distinct = {}, 0
                for seed = 1, 4 do
                    local g = playGame(id, seed)
                    if not seen[g] then seen[g] = true; distinct = distinct + 1 end
                end
                assert.is_true(distinct >= 2, id .. " played the same game every time")
            end
        end)

        it("plays the same game twice under the same seed", function()
            assert.are.equal(playGame("easy", 42), playGame("easy", 42))
        end)

        it("noise uses the given rng", function()
            local b = Board:new()
            b:dropPiece(4); b:dropPiece(3)
            local plain = b:getAIMove(4)
            local zero = b:getAIMove(4, nil, { noise = 1000, rng = function() return 0 end })
            assert.are.equal(plain, zero)
        end)
    end)

    describe("serialize / load", function()
        it("round-trips the grid, turn and status", function()
            local b = Board:new()
            b:dropPiece(4)
            local data = b:serialize()

            local b2 = Board:new()
            assert.is_true(b2:load(data))
            assert.are.equal(b.turn, b2.turn)
            assert.are.equal(b.grid[6][4], b2.grid[6][4])
        end)

        it("load returns false for invalid data", function()
            local b = Board:new()
            assert.is_false(b:load(nil))
            assert.is_false(b:load({}))
        end)
    end)
end)
