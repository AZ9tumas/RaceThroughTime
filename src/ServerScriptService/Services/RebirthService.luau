--[[
	RebirthService
	Handles the rebirth system for long-term progression.
	
	Trigger:
	- Players can perform a Rebirth after reaching high milestones (distance/points)
	
	Effect:
	- Resets personal stars (fuel currency)
	- Keeps acquired pets
	- Grants permanent bonuses (cash multiplier, pet, speed boost multiplier)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Stats = require(ReplicatedStorage.Modules.Stats)
local RebirthStats = require(ReplicatedStorage.Modules.RebirthStats)

local RebirthService = Knit.CreateService({
	Name = "RebirthService",
	Client = {
		RebirthCompleted = Knit.CreateSignal(), -- Signal to notify client when rebirth is completed
		RebirthAvailable = Knit.CreateSignal(), -- Signal to notify client when rebirth becomes available
	},
})

-- Helper function for logging
local function Log(message: string)
	print(string.format("[RebirthService]: %s", message))
end

-- Generate a unique ID for pets
local function GeneratePetID(): string
	return HttpService:GenerateGUID(false)
end

--[[
	Check if a player can perform a rebirth.
	
	@param player Player - The player to check
	@return boolean, table? - Can rebirth, next rebirth config if can
]]
function RebirthService:CanPlayerRebirth(player: Player): (boolean, any?)
	local DataService = Knit.GetService("DataService")
	
	local stats = DataService:Get(player, "Stats")
	if not stats then
		return false, nil
	end
	
	local currentRebirthLevel = stats.Rebirths or 0
	local totalDistance = stats.TotalDistance or 0
	
	return RebirthStats.CanRebirth(currentRebirthLevel, totalDistance)
end

--[[
	Perform a rebirth for a player.
	
	@param player Player - The player performing the rebirth
	@return boolean, string?, table? - Success, error message, rebirth result data
]]
function RebirthService:PerformRebirth(player: Player): (boolean, string?, any?)
	local DataService = Knit.GetService("DataService")
	local NotificationService = Knit.GetService("NotificationService")
	local PetService = Knit.GetService("PetService")
	
	-- Check if player can rebirth
	local canRebirth, nextRebirth = self:CanPlayerRebirth(player)
	if not canRebirth or not nextRebirth then
		NotificationService:SendNotification(
			player,
			"You haven't reached the required milestone to rebirth!",
			NotificationService.Category.Warning
		)
		return false, "Cannot rebirth yet", nil
	end
	
	-- Get current stats before rebirth
	local currentStats = DataService:Get(player, "Stats")
	local previousLevel = currentStats.Rebirths or 0
	local newLevel = nextRebirth.Level
	
	-- Reset fuel (personal stars) - keep TotalDistance for tracking
	DataService:Update(player, "Stats", function(stats)
		stats.Fuel = Stats.StartingFuel -- Reset to starting fuel
		stats.Rebirths = newLevel -- Increment rebirth level
		-- TotalDistance is kept for future rebirth requirements
		return stats
	end)
	
	-- Grant pet reward
	local petRewardGranted = false
	local petInfo = nil
	
	if nextRebirth.PetReward then
		local petType = nextRebirth.PetReward
		local petConfig = Stats.Pets[petType]
		
		if petConfig then
			local petID = GeneratePetID()
			local newPetIndex = nil
			
			DataService:Update(player, "Inventory", function(inventory)
				if not inventory.PetInventory then
					inventory.PetInventory = {}
				end
				
				-- Add pet with stats from config
				local petEntry = {
					PetType = petType,
					Name = petConfig.Name .. " (Rebirth)",
					Multiplier = petConfig.Multiplier,
					FuelBonus = petConfig.FuelBonus or 1.1,
					PickupRangeBonus = petConfig.PickupRangeBonus or 1.0,
					RoamRange = petConfig.RoamRange or 30,
					StarCollectionRadius = petConfig.StarCollectionRadius or 5,
					Velocity = petConfig.Velocity or 20,
					World = nextRebirth.World or "Main",
					Level = petConfig.BaseTierLevel or 1,
					TierLevel = petConfig.BaseTierLevel or 1,
					TierName = "Common",
					Rarity = "Rebirth", -- Special rarity for rebirth pets
					ObtainedAt = os.time(),
				}
				table.insert(inventory.PetInventory, petEntry)
				newPetIndex = #inventory.PetInventory
				
				return inventory
			end)
			
			if newPetIndex then
				PetService:RegisterPetID(player, newPetIndex, petID)
				petRewardGranted = true
				petInfo = {
					Name = petConfig.Name .. " (Rebirth)",
					ID = petID,
					PetType = petType,
					World = nextRebirth.World,
				}
			end
		end
	end
	
	-- Calculate new total multipliers
	local newCashMultiplier = RebirthStats.CalculateTotalCashMultiplier(newLevel)
	local newSpeedMultiplier = RebirthStats.CalculateTotalSpeedMultiplier(newLevel)
	
	Log(string.format(
		"Player %s rebirthed to level %d (Cash: %.2fx, Speed: %.2fx)",
		player.Name,
		newLevel,
		newCashMultiplier,
		newSpeedMultiplier
	))
	
	-- Send success notification
	NotificationService:SendNotification(
		player,
		string.format("🌟 Rebirth Level %d Complete! 🌟", newLevel),
		NotificationService.Category.Success,
		5
	)
	
	-- Prepare result data
	local resultData = {
		NewRebirthLevel = newLevel,
		CashMultiplier = newCashMultiplier,
		SpeedMultiplier = newSpeedMultiplier,
		CashMultiplierBonus = nextRebirth.CashMultiplierBonus,
		SpeedBoostBonus = nextRebirth.SpeedBoostMultiplier,
		PetReward = petInfo,
		FuelReset = true,
	}
	
	-- Fire signal to client
	self.Client.RebirthCompleted:Fire(player, resultData)
	
	return true, nil, resultData
end

--[[
	Get rebirth information for a player.
	
	@param player Player - The player to check
	@return table - Rebirth status information
]]
function RebirthService:GetRebirthInfo(player: Player)
	local DataService = Knit.GetService("DataService")
	
	local stats = DataService:Get(player, "Stats")
	if not stats then
		return {
			CurrentLevel = 0,
			TotalDistance = 0,
			CanRebirth = false,
			NextRebirth = RebirthStats.GetRebirthByLevel(1),
			Progress = 0,
			Remaining = 0,
			CashMultiplier = 1.0,
			SpeedMultiplier = 1.0,
		}
	end
	
	local currentLevel = stats.Rebirths or 0
	local totalDistance = stats.TotalDistance or 0
	local canRebirth, nextRebirth = RebirthStats.CanRebirth(currentLevel, totalDistance)
	local progress, remaining = RebirthStats.GetRebirthProgress(currentLevel, totalDistance)
	
	return {
		CurrentLevel = currentLevel,
		TotalDistance = totalDistance,
		CanRebirth = canRebirth,
		NextRebirth = nextRebirth or RebirthStats.GetNextRebirth(currentLevel),
		Progress = progress,
		Remaining = remaining,
		CashMultiplier = RebirthStats.CalculateTotalCashMultiplier(currentLevel),
		SpeedMultiplier = RebirthStats.CalculateTotalSpeedMultiplier(currentLevel),
	}
end

--[[
	Get rebirth multipliers for a player.
	Used by Stats module to calculate bonuses.
	
	@param player Player - The player to check
	@return number, number - Cash multiplier, Speed multiplier
]]
function RebirthService:GetRebirthMultipliers(player: Player): (number, number)
	local DataService = Knit.GetService("DataService")
	
	local stats = DataService:Get(player, "Stats")
	if not stats then
		return 1.0, 1.0
	end
	
	local currentLevel = stats.Rebirths or 0
	
	return RebirthStats.CalculateTotalCashMultiplier(currentLevel),
		   RebirthStats.CalculateTotalSpeedMultiplier(currentLevel)
end

-- Client request to check rebirth availability
function RebirthService.Client:CanRebirth(player: Player): (boolean, any?)
	return RebirthService:CanPlayerRebirth(player)
end

-- Client request to perform rebirth
function RebirthService.Client:RequestRebirth(player: Player): (boolean, string?, any?)
	return RebirthService:PerformRebirth(player)
end

-- Client request to get rebirth info
function RebirthService.Client:GetRebirthInfo(player: Player)
	return RebirthService:GetRebirthInfo(player)
end

-- Client request to get rebirth multipliers
function RebirthService.Client:GetRebirthMultipliers(player: Player): (number, number)
	return RebirthService:GetRebirthMultipliers(player)
end

-- Clean up when player leaves
local function OnPlayerRemoving(player: Player)
	Log(string.format("Player %s left, cleaning up rebirth data", player.Name))
end

-- Knit lifecycle
function RebirthService:KnitInit()
	Players.PlayerRemoving:Connect(OnPlayerRemoving)
	Log("RebirthService initialized")
end

function RebirthService:KnitStart()
	Log("RebirthService started")
end

return RebirthService
