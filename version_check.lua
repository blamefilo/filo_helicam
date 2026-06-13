CreateThread(function()
    local hasEscrowIgnore = false
    local resourceName = GetCurrentResourceName()
    local currentVersion = GetResourceMetadata(resourceName, 'version', 0)
    local apiUrl = "https://filoversionchecker.vercel.app/api/check-version?resource=" .. resourceName .. "&version=" .. currentVersion .. "&escrow=" .. (hasEscrowIgnore and "true" or "false")

    for i = 0, GetNumResourceMetadata(resourceName, "dependency") do
        local dep = GetResourceMetadata(resourceName, "dependency", i)
        if dep == "/assetpacks" then
            hasEscrowIgnore = true
        end
    end

    PerformHttpRequest(apiUrl, function(errorCode, resultData, headers)
        if errorCode == 200 then
            local data = json.decode(resultData)
            if data then
                print(data.text)
            end
        end
    end, 'GET')
end)