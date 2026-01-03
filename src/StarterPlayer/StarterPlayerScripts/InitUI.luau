
local handler = {
    _connections = {},
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- modules
local modules = ReplicatedStorage:WaitForChild("Modules")
local statsM = require(modules:WaitForChild("Stats"))

-- ui
local mainUi: ScreenGui = PlayerGui:WaitForChild("RaceThroughTime_UI")
local leftPanel: Frame = mainUi:WaitForChild("LeftPanel")
local cashDisplay: TextLabel = leftPanel:WaitForChild("CashDisplay")
local GemsDisplay: TextLabel = leftPanel:WaitForChild("GemsDisplay")
local fuelBar = mainUi:WaitForChild("CenterHUD"):WaitForChild("FuelBar")
local fuelText: TextLabel = fuelBar:WaitForChild("FuelText")
local fuelBarFill = fuelBar:WaitForChild("Fill")

-- vals
local leaderstats = player:WaitForChild("leaderstats")
local gemsVal = leaderstats:WaitForChild("Gems")
local cashVal = leaderstats:WaitForChild("Cash")
local statsfolder = player:WaitForChild("Stats")
local fuelVal = statsfolder:WaitForChild("Fuel")

function handler.UpdateFuelUI(amount: number)
    fuelBarFill.Size = UDim2.new(amount / statsM.MaxBaseFuel, 0, 1, 0)
    fuelText.Text = "⭐ FUEL: " .. amount
end

local function truncateNumber(n: number)
    -- add support till trillion
    if n >= 1e6 then
        return string.format("%.2fM", n / 1e6)
    end

    return tostring(n)
end

handler._connections["RenderStepped"] = game:GetService("RunService").RenderStepped:Connect(function()
    handler.UpdateFuelUI(fuelVal.Value)
    cashDisplay.Text = truncateNumber(0)
    GemsDisplay.Text = truncateNumber(0)
end)

return handler