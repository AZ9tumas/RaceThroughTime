
local handler = {
    _connections = {},
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- modules
local modules = ReplicatedStorage:WaitForChild("Modules")
local statsM = require(modules:WaitForChild("Stats"))

-- Knit for service communication
local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))

-- Debounce state for track requests
local isRequestingTrack = false

-- Gate settings from Stats
local GATE_PROXIMITY_DISTANCE = statsM.GateProximityDistance
local MAX_GATE_INDEX = statsM.MaxGateIndex

-- Track gate references
local TrackGates = Workspace:WaitForChild("RTT_Map_Final"):WaitForChild("Track_System"):WaitForChild("Track_Gates")

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

-- Check if player is near any gate
local function IsPlayerNearGate(): boolean
    local character = player.Character
    if not character then return false end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return false end
    
    local playerPosition = rootPart.Position
    
    -- Check distance to each gate
    for i = 0, MAX_GATE_INDEX do
        local gateName = "Gate_" .. i
        local gate = TrackGates:FindFirstChild(gateName)
        if gate then
            local gatePosition: Vector3
            if gate:IsA("BasePart") then
                gatePosition = gate.Position
            elseif gate:IsA("Model") then
                local primaryPart = gate.PrimaryPart or gate:FindFirstChildWhichIsA("BasePart")
                if primaryPart then
                    gatePosition = primaryPart.Position
                end
            end
            
            if gatePosition then
                local distance = (playerPosition - gatePosition).Magnitude
                if distance <= GATE_PROXIMITY_DISTANCE then
                    return true
                end
            end
        end
    end
    
    return false
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
    -- Debounce: prevent spam requests while one is already in progress
    if isRequestingTrack then
        print("[InitUI]: Track request already in progress, ignoring click")
        return
    end
    
    -- Check if player is already on track (via TrackController)
    local TrackController = Knit.GetController("TrackController")
    if TrackController and TrackController:IsOnTrack() then
        print("[InitUI]: Already on track, ignoring click")
        return
    end
    
    -- Set debounce flag
    isRequestingTrack = true
    
    -- Get the TrackService and send request to start running on track
    local TrackService = Knit.GetService("TrackService")
    
    -- Fade in the loading screen before making the request
    local LoadingScreenController = Knit.GetController("LoadingScreenController")
    if LoadingScreenController then
        LoadingScreenController:ShowLoadingScreen()
    end

    local NotificationController = Knit.GetController("NotificationController")

    
    TrackService:RequestTrackStart():andThen(function(success: boolean, gateName: string?)
        print(success, gateName)
    
        if success then
            print("[InitUI]: Track start successful")
            runButton.Visible = false
        else
            print(string.format("[InitUI]: Track start failed - %s", gateName or "Unknown error"))

            NotificationController:ShowNotification(
                "Failed to start track: " .. (gateName or "Unknown error"),
                NotificationController.Category.Error,
                5
            )
            
            -- Fade out loading screen on failure
            if LoadingScreenController then
                LoadingScreenController:HideLoadingScreen()
            end
            -- Reset debounce on failure so player can try again
            isRequestingTrack = false
        end
    end)
end)

-- Function to reset debounce when track ends (called externally)
function handler.ResetTrackDebounce()
    isRequestingTrack = false
end

-- Update run button visibility based on gate proximity
local function UpdateRunButtonVisibility()
    -- Don't show if player is on track or requesting track
    local TrackController = Knit.GetController("TrackController")
    if TrackController and TrackController:IsOnTrack() then
        runButton.Visible = false
        return
    end
    
    if isRequestingTrack then
        runButton.Visible = false
        return
    end
    
    -- Show only if near a gate
    runButton.Visible = IsPlayerNearGate()
end

handler._connections["RenderStepped"] = RunService.RenderStepped:Connect(function()
    handler.UpdateFuelUI(fuelVal.Value)
    handler.UpdateCashUI(cashVal.Value)
    handler.UpdateGemsUI(gemsVal.Value)
    UpdateRunButtonVisibility()
end)

return handler