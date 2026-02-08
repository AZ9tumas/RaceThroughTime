--[[
	LauncherService
	Handles the launcher upgrade system for fuel-to-distance conversion multiplier.
	
	Launcher levels affect the multiplier applied when converting fuel to distance.
	
	Multiplier Formula:
	Multiplier = 1.1 * (1.523) ^ (Level - 1)
	
	Upgrade Requirement (for target level L > 1):
	MaxDistanceTraveled >= 1000 * (1.89) ^ (L - 2)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local LauncherService = Knit.CreateService({
	Name = "LauncherService",
	Client = {
		LauncherUpgraded = Knit.CreateSignal(), -- Signal to notify client when launcher is upgraded
		UpdateLauncherClient = Knit.CreateSignal(), -- Signal to notify client to update launcher UI
	},
})

-- Helper function for logging
local function Log(message: string)
	print(string.format("[LauncherService]: %s", message))
end

--[[
	Calculate the launcher multiplier for a given level.
	Multiplier = 1.1 * (1.523) ^ (Level - 1)
	
	@param level number - The launcher level (natural number >= 1)
	@return number - The multiplier value
]]
function LauncherService:GetMultiplier(level: number): number
	if level == 1 then return 1 end
	return 1.1 * math.pow(1.523, level - 1)
end

--[[
	Calculate the minimum max distance required to upgrade to a target level.
	Requirement = 1000 * (1.89) ^ (Level - 2)
	
	@param targetLevel number - The target level to upgrade to (must be > 1)
	@return number - The minimum max distance required
]]
function LauncherService:GetUpgradeRequirement(targetLevel: number): number
	if targetLevel <= 1 then
		return 0 -- No requirement for level 1
	end
	return 1000 * math.pow(1.89, targetLevel - 2)
end

--[[
	Check if a player can upgrade their launcher level.
	
	@param player Player - The player to check
	@return boolean, string? - Can upgrade, reason if not
]]
function LauncherService:CanUpgrade(player: Player): (boolean, string?)
	local DataService = Knit.GetService("DataService")
	
	local stats = DataService:Get(player, "Stats")
	if not stats then
		return false, "Could not load player stats"
	end
	
	local currentLevel = stats.LauncherLevel or 1
	local maxDistance = stats.MaxDistanceTraveled or 0
	local targetLevel = currentLevel + 1
	
	local requirement = self:GetUpgradeRequirement(targetLevel)
	
	if maxDistance >= requirement then
		return true, nil
	else
		return false, string.format(
			"Need %.0f max distance to upgrade to level %d (current: %.0f)",
			requirement,
			targetLevel,
			maxDistance
		)
	end
end

--[[
	Upgrade the player's launcher level.
	
	@param player Player - The player to upgrade
	@return boolean, string?, table? - Success, error message, upgrade result
]]
function LauncherService:UpgradeLevel(player: Player): (boolean, string?, any?)
	local DataService = Knit.GetService("DataService")
	local NotificationService = Knit.GetService("NotificationService")
	
	-- Check if player can upgrade
	local canUpgrade, reason = self:CanUpgrade(player)
	if not canUpgrade then
		if NotificationService then
			NotificationService:SendNotification(
				player,
				reason or "Cannot upgrade launcher",
				NotificationService.Category.Warning
			)
		end
		return false, reason, nil
	end
	
	-- Get current level
	local stats = DataService:Get(player, "Stats")
	local currentLevel = stats.LauncherLevel or 1
	local newLevel = currentLevel + 1
	
	-- Calculate multipliers
	local oldMultiplier = self:GetMultiplier(currentLevel)
	local newMultiplier = self:GetMultiplier(newLevel)
	
	-- Update launcher level
	DataService:Update(player, "Stats", function(s)
		s.LauncherLevel = newLevel
		return s
	end)
	
	Log(string.format(
		"Player %s upgraded launcher from level %d to %d (multiplier: %.2fx -> %.2fx)",
		player.Name,
		currentLevel,
		newLevel,
		oldMultiplier,
		newMultiplier
	))
	
	-- Send success notification
	if NotificationService then
		NotificationService:SendNotification(
			player,
			string.format("🚀 Launcher upgraded to Level %d! (%.2fx multiplier)", newLevel, newMultiplier),
			NotificationService.Category.Success,
			5
		)
	end
	
	-- Prepare result data
	local resultData = {
		PreviousLevel = currentLevel,
		NewLevel = newLevel,
		PreviousMultiplier = oldMultiplier,
		NewMultiplier = newMultiplier,
		NextRequirement = self:GetUpgradeRequirement(newLevel + 1),
	}
	
	-- Fire signal to client
	self.Client.LauncherUpgraded:Fire(player, resultData)

	-- Fire UpdateLauncherClient to update the 3D UI immediately
	self:FireUpdateLauncherClient(player)
	
	return true, nil, resultData
end

--[[
	Get launcher information for a player.
	
	@param player Player - The player to check
	@return table - Launcher status information
]]
function LauncherService:GetLauncherInfo(player: Player)
	local DataService = Knit.GetService("DataService")
	
	local stats = DataService:Get(player, "Stats")
	if not stats then
		return {
			Level = 1,
			Multiplier = 1.1,
			MaxDistance = 0,
			CanUpgrade = false,
			NextRequirement = self:GetUpgradeRequirement(2),
			Progress = 0,
		}
	end
	
	local level = stats.LauncherLevel or 1
	local maxDistance = stats.MaxDistanceTraveled or 0
	local multiplier = self:GetMultiplier(level)
	local canUpgrade, _ = self:CanUpgrade(player)
	local nextRequirement = self:GetUpgradeRequirement(level + 1)
	
	-- Calculate progress towards next level (0 to 1)
	local progress = 0
	if nextRequirement > 0 then
		progress = math.clamp(maxDistance / nextRequirement, 0, 1)
	end
	
	return {
		Level = level,
		Multiplier = multiplier,
		MaxDistance = maxDistance,
		CanUpgrade = canUpgrade,
		NextRequirement = nextRequirement,
		Progress = progress,
	}
end

--[[
	Get the launcher multiplier for a player.
	Used by other services for fuel-to-distance calculations.
	
	@param player Player - The player to check
	@return number - The player's launcher multiplier
]]
function LauncherService:GetPlayerMultiplier(player: Player): number
	local DataService = Knit.GetService("DataService")
	
	local stats = DataService:Get(player, "Stats")
	if not stats then
		return 1.1 -- Default level 1 multiplier
	end
	
	local level = stats.LauncherLevel or 1
	return self:GetMultiplier(level)
end

--[[
	Fire UpdateLauncherClient signal to update the client's launcher UI.
	Called by DataService after any successful data update.
	
	@param player Player - The player to update
]]
function LauncherService:FireUpdateLauncherClient(player: Player)
	local launcherInfo = self:GetLauncherInfo(player)
	self.Client.UpdateLauncherClient:Fire(player, launcherInfo)
end

-- Client request to check if can upgrade
function LauncherService.Client:CanUpgrade(player: Player): (boolean, string?)
	return LauncherService:CanUpgrade(player)
end

-- Client request to upgrade launcher level
function LauncherService.Client:RequestUpgrade(player: Player): (boolean, string?, any?)
	return LauncherService:UpgradeLevel(player)
end

-- Client request to get launcher info
function LauncherService.Client:GetLauncherInfo(player: Player)
	return LauncherService:GetLauncherInfo(player)
end

-- Client request to get multiplier
function LauncherService.Client:GetMultiplier(player: Player): number
	return LauncherService:GetPlayerMultiplier(player)
end

-- Clean up when player leaves
local function OnPlayerRemoving(player: Player)
	Log(string.format("Player %s left, cleaning up launcher data", player.Name))
end

-- Knit lifecycle
function LauncherService:KnitInit()
	Players.PlayerRemoving:Connect(OnPlayerRemoving)
	Log("LauncherService initialized")
end

function LauncherService:KnitStart()
	Log("LauncherService started")
end

return LauncherService
