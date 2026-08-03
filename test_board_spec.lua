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
