
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
local otherFrames: Frame = mainUi:WaitForChild("OtherFrames")

-- sub frames
local dailyButton: TextButton = leftPanel:WaitForChild("DailyButton")
local dailyFrame: Frame = otherFrames:WaitForChild("DailyFrame")
local shopButton: TextButton = leftPanel:WaitForChild("ShopButton")
local shopFrame: Frame = otherFrames:WaitForChild("StoreFrame")

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

-- daily frame
handler._connections["DailyButton"] = dailyButton.MouseButton1Click:Connect(function()
    dailyFrame.Visible = not dailyFrame.Visible
end)

local dailyFrameMain = dailyFrame:WaitForChild("Main")
local cardHolderFrame = dailyFrameMain:WaitForChild("CardHolder")
local cardHolders = {
    DayOne = {
        Frame = cardHolderFrame:WaitForChild("1"),
        RedeemButton = cardHolderFrame:WaitForChild("1"):WaitForChild("Claim"):WaitForChild("Interact"),
        Image = cardHolderFrame:WaitForChild("1"):WaitForChild("ImageLabel"),
        TextLabel = cardHolderFrame:WaitForChild("1"):WaitForChild("Amount"),
    },
    DayTwo = {
        Frame = cardHolderFrame:WaitForChild("2"),
        RedeemButton = cardHolderFrame:WaitForChild("2"):WaitForChild("Claim"):WaitForChild("Interact"),
        Image = cardHolderFrame:WaitForChild("2"):WaitForChild("ImageLabel"),
        TextLabel = cardHolderFrame:WaitForChild("2"):WaitForChild("Amount"),
    },
    DayThree = {
        Frame = cardHolderFrame:WaitForChild("3"),
        RedeemButton = cardHolderFrame:WaitForChild("3"):WaitForChild("Claim"):WaitForChild("Interact"),
        Image = cardHolderFrame:WaitForChild("3"):WaitForChild("ImageLabel"),
        TextLabel = cardHolderFrame:WaitForChild("3"):WaitForChild("Amount"),
    },
    DayFour = {
        Frame = cardHolderFrame:WaitForChild("4"),
        RedeemButton = cardHolderFrame:WaitForChild("4"):WaitForChild("Claim"):WaitForChild("Interact"),
        Image = cardHolderFrame:WaitForChild("4"):WaitForChild("ImageLabel"),
        TextLabel = cardHolderFrame:WaitForChild("4"):WaitForChild("Amount"),
    },
    DayFive = {
        Frame = cardHolderFrame:WaitForChild("5"),
        RedeemButton = cardHolderFrame:WaitForChild("5"):WaitForChild("Claim"):WaitForChild("Interact"),
        Image = cardHolderFrame:WaitForChild("5"):WaitForChild("ImageLabel"),
        TextLabel = cardHolderFrame:WaitForChild("5"):WaitForChild("Amount"),
    },
}

print(cardHolders, "Card Holders")

-- Connect all daily reward claim buttons to the server
-- Client only sends the request - server handles everything including notifications
local DailyRewardService = Knit.GetService("DailyRewardService")
local DataService = Knit.GetService("DataService")

for _, cardData in pairs(cardHolders) do
    handler._connections["Day" .. cardData.Frame.Name] = cardData.RedeemButton.MouseButton1Click:Connect(function()
        -- Send claim request to server - server handles all logic and notifications
        DailyRewardService:RequestCollectReward()
        -- Close the daily frame after clicking
        dailyFrame.Visible = false
    end)
end

-- Function to update UI with loaded data from server
-- Called after data has been loaded on the server
function handler.UpdateDataOnClient(data)
    -- Update daily rewards UI if data contains reward status
    if data and data.rewardStatus then
        local status = data.rewardStatus
        -- Could update UI elements here based on streak, canCollect, etc.
        print("[InitUI]: Daily reward status updated - Streak:", status.streak, "Can Collect:", status.canCollect)
    end
    
    -- Initial UI updates from leaderstats (already replicated)
    handler.UpdateFuelUI(fuelVal.Value)
    handler.UpdateCashUI(cashVal.Value)
    handler.UpdateGemsUI(gemsVal.Value)
    
    print("[InitUI]: Client data updated")
end

-- Listen for DataReady signal from server to update UI
handler._connections["DataReady"] = DataService.DataReady:Connect(function()
    -- Get reward status from server to update UI
    local rewardStatus = DailyRewardService:GetRewardStatus()
    handler.UpdateDataOnClient({ rewardStatus = rewardStatus })
end)

handler._connections["RenderStepped"] = RunService.RenderStepped:Connect(function()
    handler.UpdateFuelUI(fuelVal.Value)
    handler.UpdateCashUI(cashVal.Value)
    handler.UpdateGemsUI(gemsVal.Value)
    UpdateRunButtonVisibility()
end)

return handler