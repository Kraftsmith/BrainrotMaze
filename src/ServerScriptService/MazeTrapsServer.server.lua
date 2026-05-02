-- MazeTrapsServer (Script in ServerScriptService)
-- Тонкий диспетчер: каждую MazeTrap-модель отдаёт TrapBehaviors по её TrapType.
-- Спека: Game Design/Labyrinths.md § 4.

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

local TrapBehaviors = require(ServerStorage:WaitForChild("TrapBehaviors"))
local Util = require(ServerStorage:WaitForChild("Util"))

local TRAP_TAG = "MazeTrap"
local DEBOUNCE = 1.5 -- секунды между TrapHit на одного игрока

local trapHitEvent = ServerStorage:WaitForChild("BrainrotEvents"):WaitForChild("TrapHit")

------------------------------------------------------------------------
-- Shared hit context (debounce + log + emit)
-- Возвращает true если hit прошёл (игроку залитан + дроп уйдёт через TrapHit),
-- false если debounce'нуло — handler в этом случае не играет звук и т.п.
------------------------------------------------------------------------

local lastHit = {}

local function fireHit(player, trap)
	local now = os.clock()
	local last = lastHit[player]
	if last and now - last < DEBOUNCE then return false end
	lastHit[player] = now

	trapHitEvent:Fire(player)
	print(("[MazeTrapsServer] %s tripped %s @ %s"):format(
		player.Name, trap:GetAttribute("TrapType") or "?", Util.locationOf(player)
	))
	return true
end

Players.PlayerRemoving:Connect(function(p) lastHit[p] = nil end)

------------------------------------------------------------------------
-- Bind every trap (initial + future)
------------------------------------------------------------------------

local ctx = { fireHit = fireHit }

local function bindTrap(trap)
	TrapBehaviors.bind(trap, ctx)
end

for _, t in CollectionService:GetTagged(TRAP_TAG) do bindTrap(t) end
CollectionService:GetInstanceAddedSignal(TRAP_TAG):Connect(bindTrap)

print(("[MazeTrapsServer] ready, %d traps active"):format(#CollectionService:GetTagged(TRAP_TAG)))
