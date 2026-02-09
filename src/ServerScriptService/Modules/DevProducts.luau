--[[
	DevProducts Module
	Contains dev product IDs and their purchase handlers.
	
	Usage:
	local DevProducts = require(path.to.DevProducts)
	DevProducts.Initialize(Knit) -- Call once during KnitInit
	
	local handler = DevProducts.PurchasesManager[productId]
	if handler then
		handler.OnPurchase(player)
	end
]]

local DevProducts = {}

-- Dev Product IDs
DevProducts.Ids = {
	MediumCashPack = 3533352608,
}

-- Purchases Manager - handlers are initialized when Initialize() is called
DevProducts.PurchasesManager = {}

-- Initialize purchase handlers (must be called after Knit is started)
function DevProducts.Initialize(Knit)
	local DataService = Knit.GetService("DataService")
	local NotificationService = Knit.GetService("NotificationService")
	
	DevProducts.PurchasesManager = {
		[DevProducts.Ids.MediumCashPack] = {
			Name = "MediumCashPack",
			OnPurchase = function(player)
				DataService:Update(player, "Currencies", function(currencies)
					currencies.Cash = (currencies.Cash or 0) + 10000
					return currencies
				end)
				
				if NotificationService then
					NotificationService:SendNotification(
						player,
						"You received 10,000 Cash!",
						NotificationService.Category.Success
					)
				end
				
				return true
			end
		},
	}
end

-- Helper function to get product ID by name
function DevProducts.GetProductId(productName: string): number?
	return DevProducts.Ids[productName]
end

-- Helper function to get product handler by ID
function DevProducts.GetHandler(productId: number)
	return DevProducts.PurchasesManager[productId]
end

return DevProducts
