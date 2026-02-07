local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local MonetizationController = Knit.CreateController({
	Name = "MonetizationController",
})

local MonetizationService

function MonetizationController:HasGamePass(gamePassName: string): boolean
	if not MonetizationService then
		return false
	end
	
	local success, result = pcall(function()
		return MonetizationService:HasGamePassClient(gamePassName)
	end)
	
	if success then
		return result
	end
	return false
end

function MonetizationController:HasInstantHatch(): boolean
	return self:HasGamePass("InstantHatch")
end

function MonetizationController:HasDoubleStars(): boolean
	return self:HasGamePass("DoubleStars")
end

function MonetizationController:KnitInit()
end

function MonetizationController:KnitStart()
	MonetizationService = Knit.GetService("MonetizationService")
end

return MonetizationController
