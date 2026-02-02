local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))

local modules = ReplicatedStorage:WaitForChild("Modules")
local statsM = require(modules:WaitForChild("Stats"))

local PLACEHOLDER_HEADSHOT = "rbxasset://textures/ui/GuiImagePlaceholder.png"

local function SafeGetHeadshot(userId: number, size: Enum.ThumbnailSize?): string
	local thumbnailSize = size or Enum.ThumbnailSize.Size100x100
	local success, content = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, thumbnailSize)
	end)
	if success and content then
		return content
	end
	return PLACEHOLDER_HEADSHOT
end

local TradeUIController = Knit.CreateController({
	Name = "TradeUIController",
})

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local DefaultBackgroundColorSelected = Color3.fromRGB(61, 61, 61)
local DefaultBackgroundColorNotSelected = Color3.fromRGB(20, 23, 28)

local colorDetails = {
	LockIn = Color3.fromRGB(85, 85, 127),
	Accept = Color3.fromRGB(46, 204, 113)
}

local tradeButton: TextButton
local tradingScreenGui: ScreenGui
local cancelTrade: TextButton
local incomingRequestUI = {}
local mainTradeUI = {}
local playerListUI = {}

local tradeOfferedPets = {}
local tradePetConnections = {}
local _connections = {}

local function GetLocalTradePetsUI()
	local petsFrame = mainTradeUI.LocalFrame:FindFirstChild("Pets")
	if not petsFrame then return nil, nil end
	local scrollingFrame = petsFrame:FindFirstChild("ScrollingFrame")
	if not scrollingFrame then return nil, nil end
	local gridLayout = scrollingFrame:FindFirstChild("UIGridLayout")
	if not gridLayout then return nil, nil end
	local template = gridLayout:FindFirstChild("Template")
	return scrollingFrame, template
end

local function GetRemoteTradePetsUI()
	local petsFrame = mainTradeUI.RemoteFrame:FindFirstChild("Pets")
	if not petsFrame then return nil, nil end
	local scrollingFrame = petsFrame:FindFirstChild("ScrollingFrame")
	if not scrollingFrame then return nil, nil end
	local gridLayout = scrollingFrame:FindFirstChild("UIGridLayout")
	if not gridLayout then return nil, nil end
	local template = gridLayout:FindFirstChild("Template")
	return scrollingFrame, template
end

local function GetLockInButton()
	return mainTradeUI.LocalFrame:FindFirstChild("LockIn")
end

local function GetRemoteStatusLabel()
	return mainTradeUI.RemoteFrame:FindFirstChild("Status")
end

local function ClearTradePetConnections()
	for _, connection in ipairs(tradePetConnections) do
		connection:Disconnect()
	end
	tradePetConnections = {}
end

local function UpdateLockInButton()
	local lockInButton = GetLockInButton()
	if not lockInButton then return end
	local TradeController = Knit.GetController("TradeController")
	local tradeState = TradeController:GetTradeState()
	if not tradeState then return end
	local otherPlayerName = tradeState.OtherPlayer and tradeState.OtherPlayer.DisplayName or "other player"
	if tradeState.ILockedIn then
		if tradeState.TheyLockedIn then
			if tradeState.IAccepted then
				lockInButton.Text = "Waiting for " .. otherPlayerName .. " to accept..."
				lockInButton.BackgroundColor3 = colorDetails.LockIn
			else
				lockInButton.Text = "Accept"
				lockInButton.BackgroundColor3 = colorDetails.Accept
			end
		else
			lockInButton.Text = "Waiting for " .. otherPlayerName .. " to lock in..."
			lockInButton.BackgroundColor3 = colorDetails.LockIn
		end
	else
		lockInButton.Text = "Lock In"
		lockInButton.BackgroundColor3 = colorDetails.LockIn
	end
end

local function UpdateRemoteStatus()
	local statusLabel = GetRemoteStatusLabel()
	if not statusLabel then return end
	local TradeController = Knit.GetController("TradeController")
	local tradeState = TradeController:GetTradeState()
	if not tradeState then
		statusLabel.Text = ""
		return
	end
	local otherPlayerName = tradeState.OtherPlayer and tradeState.OtherPlayer.DisplayName or "Other player"
	if tradeState.TheyAccepted then
		statusLabel.Text = otherPlayerName .. " accepted ✓"
	elseif tradeState.TheyLockedIn then
		statusLabel.Text = otherPlayerName .. " locked in"
	else
		statusLabel.Text = otherPlayerName .. " is selecting..."
	end
end

local function UpdateLocalTradePets()
	local scrollingFrame, template = GetLocalTradePetsUI()
	if not scrollingFrame or not template then return end
	ClearTradePetConnections()
	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child.Name ~= "Template" and child.Name ~= "UIGridLayout" and (child:IsA("Frame") or child:IsA("TextButton")) then
			child:Destroy()
		end
	end
	local UIController = Knit.GetController("UIController")
	local TradeController = Knit.GetController("TradeController")
	local data = UIController:GetData()
	local petInventory = data.Inventory.PetInventory
	if not petInventory then return end
	local tradeState = TradeController:GetTradeState()
	local offeredSet = {}
	if tradeState and tradeState.MyOffers then
		for _, offer in ipairs(tradeState.MyOffers) do
			offeredSet[offer.PetIndex] = true
		end
	end
	for index, petData in ipairs(petInventory) do
		local petFrame = template:Clone()
		petFrame.Name = "TradePet_" .. index
		petFrame.Visible = true
		local nameLabel = petFrame:FindFirstChild("PetName")
		if nameLabel then
			nameLabel.Text = petData.Name or "Unknown Pet"
		end
		local multiplierFrame = petFrame:FindFirstChild("Multiplier")
		if multiplierFrame then
			local multiplierLabel = multiplierFrame:FindFirstChild("TextLabel")
			if multiplierLabel then
				multiplierLabel.Text = string.format("x%.1f", petData.Multiplier or 1.0)
			end
		end
		if petFrame:FindFirstChild("UIStroke") and petData.TierLevel then
			petFrame.UIStroke.Color = statsM.TierColors[petData.TierLevel] or Color3.fromRGB(49, 49, 49)
		end
		local isOffered = offeredSet[index] == true
		if isOffered then
			petFrame.BackgroundColor3 = DefaultBackgroundColorSelected
		else
			petFrame.BackgroundColor3 = DefaultBackgroundColorNotSelected
		end
		if petFrame:IsA("TextButton") then
			local petIndex = index
			local conn = petFrame.MouseButton1Click:Connect(function()
				local currentTradeState = TradeController:GetTradeState()
				if not currentTradeState then return end
				if currentTradeState.ILockedIn then return end
				local currentlyOffered = false
				if currentTradeState.MyOffers then
					for _, offer in ipairs(currentTradeState.MyOffers) do
						if offer.PetIndex == petIndex then
							currentlyOffered = true
							break
						end
					end
				end
				if currentlyOffered then
					TradeController:RemovePet(petIndex)
				else
					TradeController:OfferPet(petIndex)
				end
			end)
			table.insert(tradePetConnections, conn)
		end
		petFrame.Parent = scrollingFrame
	end
end

local function UpdateRemoteTradePets()
	local scrollingFrame, template = GetRemoteTradePetsUI()
	if not scrollingFrame or not template then return end
	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child.Name ~= "Template" and child.Name ~= "UIGridLayout" and (child:IsA("Frame") or child:IsA("TextButton")) then
			child:Destroy()
		end
	end
	local TradeController = Knit.GetController("TradeController")
	local tradeState = TradeController:GetTradeState()
	if not tradeState or not tradeState.TheirOffers then return end
	for _, offer in ipairs(tradeState.TheirOffers) do
		local petData = offer.PetData
		if not petData then continue end
		local petFrame = template:Clone()
		petFrame.Name = "RemotePet_" .. offer.PetIndex
		petFrame.Visible = true
		local nameLabel = petFrame:FindFirstChild("PetName")
		if nameLabel then
			nameLabel.Text = petData.Name or "Unknown Pet"
		end
		local multiplierFrame = petFrame:FindFirstChild("Multiplier")
		if multiplierFrame then
			local multiplierLabel = multiplierFrame:FindFirstChild("TextLabel")
			if multiplierLabel then
				multiplierLabel.Text = string.format("x%.1f", petData.Multiplier or 1.0)
			end
		end
		if petFrame:FindFirstChild("UIStroke") and petData.TierLevel then
			petFrame.UIStroke.Color = statsM.TierColors[petData.TierLevel] or Color3.fromRGB(49, 49, 49)
		end
		petFrame.BackgroundColor3 = DefaultBackgroundColorSelected
		petFrame.Parent = scrollingFrame
	end
end

function TradeUIController:ShowTradeUI(otherPlayer: Player)
	local UIController = Knit.GetController("UIController")
	UIController:CloseAllFrames()
	playerListUI.PlayerListFrame.Visible = false
	incomingRequestUI.IncomingRequestFrame.Visible = false
	tradeOfferedPets = {}
	mainTradeUI.MainTradeFrame.Visible = true
	local petsFrame = mainTradeUI.RemoteFrame:FindFirstChild("Pets")
	if petsFrame then
		local playerLabel = petsFrame:FindFirstChild("Player")
		if playerLabel and playerLabel:IsA("TextLabel") then
			playerLabel.Text = otherPlayer.DisplayName
		end
	end
	UpdateLocalTradePets()
	UpdateRemoteTradePets()
	UpdateLockInButton()
	UpdateRemoteStatus()
end

function TradeUIController:HideTradeUI()
	mainTradeUI.MainTradeFrame.Visible = false
	ClearTradePetConnections()
	tradeOfferedPets = {}
end

function TradeUIController:ShowIncomingRequest(fromPlayer: Player)
	incomingRequestUI.InfoLabel.Text = fromPlayer.DisplayName .. " wants to trade!"
	incomingRequestUI.IncomingRequestFrame.Visible = true
	incomingRequestUI.IncomingRequestFrame:SetAttribute("FromPlayer", fromPlayer.UserId)
end

function TradeUIController:HideIncomingRequest()
	incomingRequestUI.IncomingRequestFrame.Visible = false
end

function TradeUIController:UpdatePlayerList()
	for _, child in ipairs(playerListUI.ScrollingFrame:GetChildren()) do
		if child.Name ~= "UIListLayout" and child.Name ~= "Template" then
			child:Destroy()
		end
	end
	local TradeController = Knit.GetController("TradeController")
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer == player then continue end
		local template = playerListUI.Template:Clone()
		template.Name = otherPlayer.Name
		template.Visible = true
		template.Username.Text = otherPlayer.DisplayName
		task.spawn(function()
			local content = SafeGetHeadshot(otherPlayer.UserId, Enum.ThumbnailSize.Size420x420)
			template.HeadShot.Image = content
		end)
		template.Trade.MouseButton1Click:Connect(function()
			TradeController:RequestTrade(otherPlayer)
		end)
		template.Parent = playerListUI.ScrollingFrame
	end
end

function TradeUIController:TogglePlayerList()
	local UIController = Knit.GetController("UIController")
	local wasVisible = playerListUI.PlayerListFrame.Visible
	UIController:CloseAllFrames()
	playerListUI.PlayerListFrame.Visible = not wasVisible
	if playerListUI.PlayerListFrame.Visible then
		self:UpdatePlayerList()
	end
end

function TradeUIController:RefreshLocalPets()
	UpdateLocalTradePets()
end

function TradeUIController:RefreshRemotePets()
	UpdateRemoteTradePets()
end

function TradeUIController:RefreshLockInButton()
	UpdateLockInButton()
end

function TradeUIController:RefreshRemoteStatus()
	UpdateRemoteStatus()
end

function TradeUIController:KnitInit()
	local mainUi: ScreenGui = PlayerGui:WaitForChild("RaceThroughTime_UI")
	local leftPanel: Frame = mainUi:WaitForChild("LeftPanel")
	tradeButton = leftPanel:WaitForChild("TradeButton")
	tradingScreenGui = PlayerGui:WaitForChild("TradingSuite")
	cancelTrade = tradingScreenGui:WaitForChild("MainTradeFrame"):WaitForChild("Cancel")
	incomingRequestUI = {
		IncomingRequestFrame = tradingScreenGui:WaitForChild("IncomingRequest"),
		InfoLabel = tradingScreenGui:WaitForChild("IncomingRequest"):WaitForChild("Info"),
		Accept = tradingScreenGui:WaitForChild("IncomingRequest"):WaitForChild("Accept"),
		Decline = tradingScreenGui:WaitForChild("IncomingRequest"):WaitForChild("Decline")
	}
	mainTradeUI = {
		MainTradeFrame = tradingScreenGui:WaitForChild("MainTradeFrame"),
		LocalFrame = tradingScreenGui:WaitForChild("MainTradeFrame"):WaitForChild("Local"),
		RemoteFrame = tradingScreenGui:WaitForChild("MainTradeFrame"):WaitForChild("Remote"),
	}
	playerListUI = {
		PlayerListFrame = tradingScreenGui:WaitForChild("PlayerListFrame"),
		ScrollingFrame = tradingScreenGui:WaitForChild("PlayerListFrame"):WaitForChild("ScrollingFrame"),
		Template = tradingScreenGui:WaitForChild("PlayerListFrame"):WaitForChild("ScrollingFrame"):WaitForChild("UIListLayout"):WaitForChild("Template"),
	}
end

function TradeUIController:KnitStart()
	local TradeController = Knit.GetController("TradeController")
	local InventoryUIController = Knit.GetController("InventoryUIController")

	_connections["TradeRequestReceived"] = TradeController.OnTradeRequestReceived:Connect(function(fromPlayer)
		self:ShowIncomingRequest(fromPlayer)
	end)

	_connections["TradeRequestCancelled"] = TradeController.OnTradeRequestCancelled:Connect(function(fromPlayer)
		local currentFromId = incomingRequestUI.IncomingRequestFrame:GetAttribute("FromPlayer")
		if currentFromId == fromPlayer.UserId then
			self:HideIncomingRequest()
		end
	end)

	_connections["TradeStarted"] = TradeController.OnTradeStarted:Connect(function(otherPlayer)
		self:HideIncomingRequest()
		self:ShowTradeUI(otherPlayer)
	end)

	_connections["TradeEnded"] = TradeController.OnTradeEnded:Connect(function(reason)
		self:HideTradeUI()
	end)

	_connections["OffersUpdated"] = TradeController.OnOffersUpdated:Connect(function(myOffers, theirOffers)
		UpdateLocalTradePets()
		UpdateRemoteTradePets()
		UpdateLockInButton()
	end)

	_connections["PlayerLockedIn"] = TradeController.OnPlayerLockedIn:Connect(function(lockedPlayer, isMe)
		UpdateLockInButton()
		UpdateRemoteStatus()
		if isMe then
			UpdateLocalTradePets()
		end
	end)

	_connections["PlayerAccepted"] = TradeController.OnPlayerAccepted:Connect(function(acceptedPlayer, isMe)
		UpdateLockInButton()
		UpdateRemoteStatus()
	end)

	_connections["TradeCompleted"] = TradeController.OnTradeCompleted:Connect(function(receivedPets)
		self:HideTradeUI()
		InventoryUIController:UpdatePetsInventory()
	end)

	_connections["AcceptTradeRequest"] = incomingRequestUI.Accept.MouseButton1Click:Connect(function()
		local fromUserId = incomingRequestUI.IncomingRequestFrame:GetAttribute("FromPlayer")
		if fromUserId then
			local fromPlayer = Players:GetPlayerByUserId(fromUserId)
			if fromPlayer then
				TradeController:AcceptRequest(fromPlayer)
			end
		end
		self:HideIncomingRequest()
	end)

	_connections["DeclineTradeRequest"] = incomingRequestUI.Decline.MouseButton1Click:Connect(function()
		local fromUserId = incomingRequestUI.IncomingRequestFrame:GetAttribute("FromPlayer")
		if fromUserId then
			local fromPlayer = Players:GetPlayerByUserId(fromUserId)
			if fromPlayer then
				TradeController:DeclineRequest(fromPlayer)
			end
		end
		self:HideIncomingRequest()
	end)

	_connections["TradeLockIn"] = GetLockInButton().MouseButton1Click:Connect(function()
		local tradeState = TradeController:GetTradeState()
		if not tradeState then return end
		if tradeState.ILockedIn and tradeState.TheyLockedIn then
			if not tradeState.IAccepted then
				TradeController:Accept()
			end
		elseif not tradeState.ILockedIn then
			TradeController:LockIn()
		end
	end)

	_connections["CancelTrade"] = cancelTrade.MouseButton1Click:Connect(function()
		TradeController:Cancel()
		self:HideTradeUI()
	end)

	_connections["TradeButton"] = tradeButton.MouseButton1Click:Connect(function()
		self:TogglePlayerList()
	end)
end

return TradeUIController
