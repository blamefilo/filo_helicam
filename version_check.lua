SetTimeout(math.random(5000, 10000), function()
    local hasEscrowIgnore = false
    local resourceName = GetCurrentResourceName()
    local currentVersion = GetResourceMetadata(resourceName, 'version', 0)
    local apiUrl = ("https://filoversionchecker.vercel.app/api/check-version?resource=%s&version=%s&escrow=%s"):format(resourceName, currentVersion, (hasEscrowIgnore and "true" or "false"))

    for i = 0, GetNumResourceMetadata(resourceName, "dependency") do
        local dep = GetResourceMetadata(resourceName, "dependency", i)
        if dep == "/assetpacks" then
            hasEscrowIgnore = true
        end
    end

    PerformHttpRequest(apiUrl, function(errorCode, resultData, headers)
        if errorCode == 200 or errorCode == 0 then
            local data = json.decode(resultData)
            if data then
                print(data.text)
            end
        else
            print(('^5[^2filo studios.^5] ^7Could not check version for ^3%s^7. Error code: %s'):format(resourceName, errorCode))
        end
    end, 'GET')
end)