--[[
	KnitClientInit
	Initializes Knit on the client side.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

-- Add all controllers from the Controllers folder
Knit.AddControllers(script.Parent.Controllers)

-- Start Knit and notify when ready
Knit.Start():andThen(function()
	local AssetLoaderController = Knit.GetController("AssetLoaderController")
	if AssetLoaderController then
		AssetLoaderController:OnKnitServicesReady()
	end
end):catch(function(err)
	warn("[Knit]: Client failed to start -", err)
end)
