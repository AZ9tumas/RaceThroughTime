local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

return function ()
    local dataService = Knit.GetService("DataService")
    print(dataService)

    
end