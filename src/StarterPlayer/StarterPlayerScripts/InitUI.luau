
local handler = {
    _connections = {},
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- modules
local modules = ReplicatedStorage:WaitForChild("Modules")
local statsM = require(modules:WaitForChild("Stats"))

-- Knit for service communication
local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))

-- ui
local mainUi: ScreenGui = PlayerGui:WaitForChild("RaceThroughTime_UI")
local leftPanel: Frame = mainUi:WaitForChild("LeftPanel")
local cashDisplay: TextLabel = leftPanel:WaitForChild("CashDisplay")
local GemsDisplay: TextLabel = leftPanel:WaitForChild("GemsDisplay")
local centerHUD: Frame = mainUi:WaitForChild("CenterHUD")
local runButton: TextButton = centerHUD:WaitForChild("RunButton")
local fuelBar = centerHUD:WaitForChild("FuelBar")
local fuelText: TextLabel = fuelBar:WaitForChild("FuelText")
local fuelBarFill = fuelBar:WaitForChild("Fill")

-- vals
local leaderstats = player:WaitForChild("leaderstats")
local gemsVal = leaderstats:WaitForChild("Gems")
local cashVal = leaderstats:WaitForChild("Cash")
local statsfolder = player:WaitForChild("Stats")
local fuelVal = statsfolder:WaitForChild("Fuel")

-- Tween settings for smooth fuel bar animation
local tweenInfo = TweenInfo.new(
    0.3,                            -- Duration
    Enum.EasingStyle.Quad,          -- Easing style
    Enum.EasingDirection.Out,       -- Easing direction
    0,                              -- Repeat count
    false,                          -- Reverses
    0                               -- Delay
)

-- Track current tween to cancel if needed
local currentFuelTween = nil

-- Helper function to truncate large numbers
local function truncateNumber(n: number)
    -- add support till trillion
    if n >= 1e12 then
        return string.format("%.2fT", n / 1e12)
    elseif n >= 1e9 then
        return string.format("%.2fB", n / 1e9)
    elseif n >= 1e6 then
        return string.format("%.2fM", n / 1e6)
    elseif n >= 1e3 then
        return string.format("%.2fK", n / 1e3)
    end

    return tostring(n)
end

function handler.UpdateFuelUI(amount: number)
    local maxFuel = statsM.FuelMultiplier()
    local fillRatio = math.clamp(amount / maxFuel, 0, 1)
    local targetSize = UDim2.new(fillRatio, 0, 1, 0)
    
    -- Cancel existing tween if running
    if currentFuelTween then
        currentFuelTween:Cancel()
    end
    
    -- Create and play smooth tween for fuel bar fill
    currentFuelTween = TweenService:Create(fuelBarFill, tweenInfo, {Size = targetSize})
    currentFuelTween:Play()
    
    -- Update fuel text
    fuelText.Text = "⭐ FUEL: " .. math.floor(amount)
end

function handler.UpdateCashUI(amount: number)
    cashDisplay.Text = "💵 " .. truncateNumber(amount)
end

function handler.UpdateGemsUI(amount: number)
    GemsDisplay.Text = "💎 " .. truncateNumber(amount)
end

handler._connections["RunButton"] = runButton.MouseButton1Click:Connect(function()
    -- Get the TrackService and send request to start running on track
    local TrackService = Knit.GetService("TrackService")
    
    -- Fade in the loading screen before making the request
    local LoadingScreenController = Knit.GetController("LoadingScreenController")
    if LoadingScreenController then
        LoadingScreenController:ShowLoadingScreen()
    end
    
    local success, gateName, totalDistance = TrackService:RequestTrackStart()
    
    if success then
        print("[InitUI]: Track start successful")
    else
        print(string.format("[InitUI]: Track start failed - %s", gateName or "Unknown error"))
        -- Fade out loading screen on failure
        if LoadingScreenController then
            LoadingScreenController:HideLoadingScreen()
        end
    end
end)

handler._connections["RenderStepped"] = game:GetService("RunService").RenderStepped:Connect(function()
    handler.UpdateFuelUI(fuelVal.Value)
    handler.UpdateCashUI(cashVal.Value)
    handler.UpdateGemsUI(gemsVal.Value)
end)

return handler