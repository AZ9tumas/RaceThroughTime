--[[
	StarterPackController
	Handles the Starter Pack UI button.
	When StarterCard is pressed, prompts the StarterPack dev product purchase.
	On successful purchase, the server hatches a Limited Historical Egg automatically.
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local StarterPackController = Knit.CreateController({
	Name = "StarterPackController",
})

local STARTER_PACK_PRODUCT_ID = 3540557146

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

function StarterPackController:KnitInit()
end

function StarterPackController:KnitStart()
	local starterPack = PlayerGui:WaitForChild("StarterPack")
	local starterCard = starterPack:WaitForChild("StarterCard")

	starterCard.MouseButton1Click:Connect(function()
		MarketplaceService:PromptProductPurchase(player, STARTER_PACK_PRODUCT_ID)
	end)
end

return StarterPackController
