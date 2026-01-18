--[[
	RebirthService
	Handles the rebirth system for long-term progression.
	
	Trigger:
	- Players can perform a Rebirth after accumulating enough Cash
	
	Effect:
	- Resets personal stars (fuel currency)
	- Spends the required cash
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
	local currencies = DataService:Get(player, "Currencies")
	if not stats or not currencies then
		return false, nil
	end
	
	local currentRebirthLevel = stats.Rebirths or 0
	local currentCash = currencies.Cash or 0
	
	return RebirthStats.CanRebirth(currentRebirthLevel, currentCash)
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
			"You don't have enough Cash to rebirth!",
			NotificationService.Category.Warning
		)
		return false, "Cannot rebirth yet", nil
	end
	
	-- Get current stats before rebirth
	local currentStats = DataService:Get(player, "Stats")
	local previousLevel = currentStats.Rebirths or 0
	local newLevel = nextRebirth.Level
	
	-- Spend cash required for rebirth
	DataService:Update(player, "Currencies", function(currencies)
		currencies.Cash = (currencies.Cash or 0) - nextRebirth.CashRequired
		return currencies
	end)
	
	-- Reset fuel (personal stars)
	DataService:Update(player, "Stats", function(stats)
		stats.Fuel = Stats.StartingFuel -- Reset to starting fuel
		stats.Rebirths = newLevel -- Increment rebirth level
		return stats
	end)
	
	-- Handle KeepPets setting - if false, clear pet inventory
	local keptPets = nextRebirth.KeepPets
	if not keptPets then
		DataService:Update(player, "Inventory", function(inventory)
			inventory.PetInventory = {}
			inventory.EquippedPets = {}
			return inventory
		end)
		Log(string.format("Player %s lost all pets on rebirth (KeepPets = false)", player.Name))
	end
	
	-- Grant Bonus rewards (Gems, Cash, World)
	local bonus = nextRebirth.Bonus
	if bonus then
		-- Grant bonus gems
		if bonus.Gems and bonus.Gems > 0 then
			DataService:Update(player, "Currencies", function(currencies)
				currencies.Gems = (currencies.Gems or 0) + bonus.Gems
				return currencies
			end)
			Log(string.format("Player %s received %d bonus gems on rebirth", player.Name, bonus.Gems))
		end
		
		-- Grant bonus cash
		if bonus.Cash and bonus.Cash > 0 then
			DataService:Update(player, "Currencies", function(currencies)
				currencies.Cash = (currencies.Cash or 0) + bonus.Cash
				return currencies
			end)
			Log(string.format("Player %s received %d bonus cash on rebirth", player.Name, bonus.Cash))
		end
		
		-- Grant bonus world unlock
		if bonus.World then
			local WorldService = Knit.GetService("WorldService")
			WorldService:GiveWorldToPlayer(player, bonus.World)
			Log(string.format("Player %s unlocked bonus world %s on rebirth", player.Name, bonus.World))
		end
	end
	
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
	local newMultiplier = RebirthStats.CalculateTotalMultiplier(newLevel)
	
	Log(string.format(
		"Player %s rebirthed to level %d (Cash: %.2fx, Speed: %.2fx, Multiplier: %.2fx, KeepPets: %s)",
		player.Name,
		newLevel,
		newCashMultiplier,
		newSpeedMultiplier,
		newMultiplier,
		tostring(keptPets)
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
		Multiplier = newMultiplier,
		CashMultiplierBonus = nextRebirth.CashMultiplierBonus,
		SpeedBoostBonus = nextRebirth.SpeedBoostMultiplier,
		MultiplierBonus = nextRebirth.Multiplier,
		PetReward = petInfo,
		FuelReset = true,
		KeepPets = keptPets,
		Bonus = bonus,
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
	local currencies = DataService:Get(player, "Currencies")
	if not stats or not currencies then
		return {
			CurrentLevel = 0,
			CurrentCash = 0,
			CanRebirth = false,
			NextRebirth = RebirthStats.GetRebirthByLevel(1),
			Progress = 0,
			Remaining = 0,
			CashMultiplier = 1.0,
			SpeedMultiplier = 1.0,
			Multiplier = 1.0,
		}
	end
	
	local currentLevel = stats.Rebirths or 0
	local currentCash = currencies.Cash or 0
	local canRebirth, nextRebirth = RebirthStats.CanRebirth(currentLevel, currentCash)
	local progress, remaining = RebirthStats.GetRebirthProgress(currentLevel, currentCash)
	
	return {
		CurrentLevel = currentLevel,
		CurrentCash = currentCash,
		CanRebirth = canRebirth,
		NextRebirth = nextRebirth or RebirthStats.GetNextRebirth(currentLevel),
		Progress = progress,
		Remaining = remaining,
		CashMultiplier = RebirthStats.CalculateTotalCashMultiplier(currentLevel),
		SpeedMultiplier = RebirthStats.CalculateTotalSpeedMultiplier(currentLevel),
		Multiplier = RebirthStats.CalculateTotalMultiplier(currentLevel),
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
