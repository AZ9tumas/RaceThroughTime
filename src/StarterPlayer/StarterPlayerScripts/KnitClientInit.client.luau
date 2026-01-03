--[[
	KnitClientInit
	Initializes Knit on the client side.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

-- Add all controllers from the Controllers folder
Knit.AddControllers(script.Parent.Controllers)

-- Start Knit
Knit.Start():catch(function(err)
	warn("[Knit]: Client failed to start -", err)
end)
