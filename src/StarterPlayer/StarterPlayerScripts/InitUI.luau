
local handler = {
    _connections = {},
    data = {
        Currencies = {
            Cash = 0,
            Gems = 0,
        },
        Stats = {
            TotalDistance = 0,
            Points = 0,
            Rebirths = 0,
            Fuel = 100, -- Starting fuel for players
        },
        Progression = {
            CurrentWorld = "Main",
            UnlockedWorlds = { "Main" },
        },
        Inventory = {
            PetInventory = {},
            EquippedPets = {},
            Potions = {},
            Eggs = {},
        },
        Meta = {
            DailyStreak = 0,
            LastClaim = 0,
            CollectedRewards = {}, -- Tracks which daily reward IDs have been collected
            UpdateVersion = 0,
            Settings = {
                Music = true,
                SFX = true,
            },
        },
    }
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

-- Get TrackGates for the player's current world
local function GetTrackGatesForCurrentWorld(): Folder?
    local currentWorld = handler.data.Progression.CurrentWorld or "Main"
    local worldFolder = Workspace:FindFirstChild(currentWorld)
    if worldFolder then
        local trackSystem = worldFolder:FindFirstChild("Track_System")
        if trackSystem then
            return trackSystem:FindFirstChild("Track_Gates")
        end
    end
    
    -- Fallback to Main world
    local mainWorld = Workspace:FindFirstChild("Main")
    if mainWorld then
        local trackSystem = mainWorld:FindFirstChild("Track_System")
        if trackSystem then
            return trackSystem:FindFirstChild("Track_Gates")
        end
    end
    
    return nil
end

-- ui
local mainUi: ScreenGui = PlayerGui:WaitForChild("RaceThroughTime_UI")
local uiShop: ScreenGui = PlayerGui:WaitForChild("UI_Shop")
local leftPanel: Frame = mainUi:WaitForChild("LeftPanel")
local cashDisplay: TextLabel = leftPanel:WaitForChild("CashDisplay")
local GemsDisplay: TextLabel = leftPanel:WaitForChild("GemsDisplay")
local centerHUD: Frame = mainUi:WaitForChild("CenterHUD")
local runButton: TextButton = centerHUD:WaitForChild("RunButton")
local fuelBar = centerHUD:WaitForChild("FuelBar")
local fuelText: TextLabel = fuelBar:WaitForChild("FuelText")
local otherFrames: Frame = mainUi:WaitForChild("OtherFrames")
local worldlabel: TextLabel = mainUi:WaitForChild("TopInfo"):WaitForChild("WorldName")

-- sub frames
local dailyButton: TextButton = leftPanel:WaitForChild("DailyButton")
local dailyFrame: Frame = otherFrames:WaitForChild("DailyFrame")
local shopButton: TextButton = leftPanel:WaitForChild("ShopButton")

-- Shop Internal UI
local shopMain = uiShop:WaitForChild("MainFrame")
local shopTop = shopMain:WaitForChild("Top")
local shopCashCount = shopTop:WaitForChild("Cash"):WaitForChild("Count")
local shopGemsCount = shopTop:WaitForChild("Gems"):WaitForChild("Count")

local shopEggsContainer = shopMain:WaitForChild("ScrollingFrame"):WaitForChild("Eggs"):WaitForChild("MainFrame")
local standardEggBuy = shopEggsContainer:WaitForChild("StandardEgg"):WaitForChild("Buy")

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
    
    -- Get track gates for current world
    local trackGates = GetTrackGatesForCurrentWorld()
    if not trackGates then return false end
    
    -- Check distance to each gate
    for i = 0, MAX_GATE_INDEX do
        local gateName = "Gate_" .. i
        local gate = trackGates:FindFirstChild(gateName)
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
    -- Update fuel text
    fuelText.Text = "⭐ FUEL: " .. math.floor(amount)
end

function handler.UpdateCashUI(amount: number)
    cashDisplay.Text = "💵 " .. truncateNumber(amount)
    shopCashCount.Text = truncateNumber(amount)
end

function handler.UpdateGemsUI(amount: number)
    GemsDisplay.Text = "💎 " .. truncateNumber(amount)
    shopGemsCount.Text = truncateNumber(amount)
end

function handler.UpdateShopUI()
    -- Check if Standard Egg is owned
    local eggs = handler.data.Inventory.Eggs or {}
    if eggs["StandardEgg"] then
        standardEggBuy.Text = "Purchased"
    end
end


-- Function to update UI with loaded data from server
-- Called after data has been loaded on the server
function handler.UpdateDataOnClient(newData)
    -- Update handler.Data with new data
    if newData then
        handler.data = newData
    end

    -- Initial UI updates from leaderstats (already replicated)
    handler.UpdateFuelUI(fuelVal.Value)
    handler.UpdateCashUI(cashVal.Value)
    handler.UpdateGemsUI(gemsVal.Value)
    handler.UpdateRewardsStatus()
    handler.UpdateShopUI()
end

handler._connections["RunButton"] = runButton.MouseButton1Click:Connect(function()
    -- Debounce: prevent spam requests while one is already in progress
    if isRequestingTrack then
        return
    end
    
    -- Check if player is already on track (via TrackController)
    local TrackController = Knit.GetController("TrackController")
    if TrackController and TrackController:IsOnTrack() then
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
local dailyFrameCloseButton = dailyFrame:WaitForChild("Close")
local cardHolderFrame = dailyFrameMain:WaitForChild("CardHolder")
local cardHolders = {
    DayOne = {
        Day = 1,
        Frame = cardHolderFrame:WaitForChild("1"),
        RedeemButton = cardHolderFrame:WaitForChild("1"):WaitForChild("Claim"):WaitForChild("Interact"),
        Image = cardHolderFrame:WaitForChild("1"):WaitForChild("ImageLabel"),
        TextLabel = cardHolderFrame:WaitForChild("1"):WaitForChild("Amount"),
    },
    DayTwo = {
        Day = 2,
        Frame = cardHolderFrame:WaitForChild("2"),
        RedeemButton = cardHolderFrame:WaitForChild("2"):WaitForChild("Claim"):WaitForChild("Interact"),
        Image = cardHolderFrame:WaitForChild("2"):WaitForChild("ImageLabel"),
        TextLabel = cardHolderFrame:WaitForChild("2"):WaitForChild("Amount"),
    },
    DayThree = {
        Day = 3,
        Frame = cardHolderFrame:WaitForChild("3"),
        RedeemButton = cardHolderFrame:WaitForChild("3"):WaitForChild("Claim"):WaitForChild("Interact"),
        Image = cardHolderFrame:WaitForChild("3"):WaitForChild("ImageLabel"),
        TextLabel = cardHolderFrame:WaitForChild("3"):WaitForChild("Amount"),
    },
    DayFour = {
        Day = 4,
        Frame = cardHolderFrame:WaitForChild("4"),
        RedeemButton = cardHolderFrame:WaitForChild("4"):WaitForChild("Claim"):WaitForChild("Interact"),
        Image = cardHolderFrame:WaitForChild("4"):WaitForChild("ImageLabel"),
        TextLabel = cardHolderFrame:WaitForChild("4"):WaitForChild("Amount"),
    },
    DayFive = {
        Day = 5,
        Frame = cardHolderFrame:WaitForChild("5"),
        RedeemButton = cardHolderFrame:WaitForChild("5"):WaitForChild("Claim"):WaitForChild("Interact"),
        Image = cardHolderFrame:WaitForChild("5"):WaitForChild("ImageLabel"),
        TextLabel = cardHolderFrame:WaitForChild("5"):WaitForChild("Amount"),
    },
}

function handler.UpdateRewardsStatus()
    -- Get DailyRewardService to check collected rewards
    local collectedRewards = handler.data.Meta.CollectedRewards or {}
    local DailyRewardsConfig = require(modules:WaitForChild("DailyRewards"))
    
    -- Update each card's status based on collected rewards
    for _, cardData in pairs(cardHolders) do
        local rewardID = DailyRewardsConfig.GetRewardIDForDay(cardData.Day)
        if rewardID and collectedRewards[rewardID] then
            cardData.RedeemButton.Parent.PriceLabel.Text = "REDEEMED"
        end
    end
end

-- Connect all daily reward claim buttons to the server
-- Client only sends the request - server handles everything including notifications
local DailyRewardService = Knit.GetService("DailyRewardService")
local DataService = Knit.GetService("DataService")

for _, cardData in pairs(cardHolders) do
    handler._connections["Day" .. cardData.Frame.Name] = cardData.RedeemButton.MouseButton1Click:Connect(function()
        -- Send claim request to server with the specific day number
        local success, _ = DailyRewardService:RequestCollectReward(cardData.Day)
        
        handler.UpdateRewardsStatus()
        
        -- Close the daily frame after clicking
        dailyFrame.Visible = false
    end)
end

handler._connections["DailyFrameClose"] = dailyFrameCloseButton.MouseButton1Click:Connect(function()
    dailyFrame.Visible = false
end)

handler._connections["ShopButton"] = shopButton.MouseButton1Click:Connect(function()
    shopMain.Visible = not shopMain.Visible
end)

-- shop
local EggService = Knit.GetService("EggService")

handler._connections["StandardEggBuy"] = standardEggBuy.MouseButton1Click:Connect(function()
    
    -- Check if already purchased
    local eggs = handler.data.Inventory.Eggs or {}
    if eggs["StandardEgg"] then
        return
    end

    EggService:RequestPurchaseEgg("StandardEgg"):andThen(function(success, errorMsg, eggInfo)
        if success and eggInfo then
            print("Purchased StandardEgg with ID:", eggInfo.id)
            
            -- Update local data
            if not handler.data.Inventory.Eggs then
                handler.data.Inventory.Eggs = {}
            end
            
            handler.data.Inventory.Eggs["StandardEgg"] = {
                id = eggInfo.id,
                purchased = true
            }
            
            handler.UpdateShopUI()
            print("Purchased StandardEgg with ID:", eggInfo.id)
        else
            print("Failed to purchase StandardEgg:", errorMsg or "Unknown error")
        end
    end)
end)

handler._connections["ShopClose"] = shopMain:WaitForChild("Close").MouseButton1Click:Connect(function()
    shopMain.Visible = false
end)

-- Listen for DataReady signal from server to update UI
handler._connections["DataReady"] = DataService.DataReady:Connect(function(data)
    -- Call UpdateDataOnClient when data is ready
    handler.UpdateDataOnClient(data)
end)

handler._connections["RenderStepped"] = RunService.RenderStepped:Connect(function()
    worldlabel.Text = "🌍 " .. (handler.data.Progression.CurrentWorld or "Main")
    handler.UpdateFuelUI(fuelVal.Value)
    handler.UpdateCashUI(cashVal.Value)
    handler.UpdateGemsUI(gemsVal.Value)
    UpdateRunButtonVisibility()
end)

return handler