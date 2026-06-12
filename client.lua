-- FiveM Heli Cam by mraes, version 1.3 (2017-06-12)
-- Modified by rjross2013 (2017-06-23)
-- Further modified by Loque (2017-08-15) with credits to the following for tips gleaned from their scripts: Guadmaz's Simple Police Searchlight, devilkkw's Speed Camera, nynjardin's Simple Outlaw Alert and IllidanS4's FiveM Entity Iterators.
-- Converted to ox_lib keybinds by filo studios. (2026-02-19)

---=========================
--- Config				====
---=========================
local fov_max = 80.0
local fov_min = 5.0 -- max zoom level (smaller fov is more zoom)
local zoomspeed = 3.0 -- camera zoom speed
local speed_lr = 4.0 -- speed by which the camera pans left-right
local speed_ud = 4.0 -- speed by which the camera pans up-down
local maxtargetdistance = 700 -- max distance at which target lock is maintained
local brightness = 1.0 -- default spotlight brightness
local spotradius = 4.0 -- default manual spotlight radius
local speed_measure = "Km/h" -- default unit to measure vehicle speed. Use either "Km/h" or "MPH".

local heliModels = {
    joaat("polmav"),
}

local helicamKeybinds = {}

---=========================
--- State				====
---=========================
local currentHeli = nil
local target_vehicle = nil
local target_plate = nil
local manual_spotlight = false
local tracking_spotlight = false
local pause_Tspotlight = false
local Fspotlight_state = false
local vehicle_display = 0 -- 0 = full info, 1 = model/plate only, 2 = off
local helicam = false
local fov = (fov_max + fov_min) * 0.5
local vision_state = 0 -- 0 = normal, 1 = nightvision, 2 = thermal

-- Shared table so onPressed keybind callbacks can access the active cam and locked vehicle
-- during the helicam render loop without polling
local helicamState = { cam = nil, locked_on_vehicle = nil }

AddEventHandler("onClientResourceStart", function(resource)
    if resource ~= cache.resource then return end
    DecorRegister("SpotvectorX", 3)
    DecorRegister("SpotvectorY", 3)
    DecorRegister("SpotvectorZ", 3)
    DecorRegister("Target", 3)
end)

---=========================
--- Helper Functions	====
---=========================

local function RotAnglesToVec(rot)
    local z = math.rad(rot.z)
    local x = math.rad(rot.x)
    local num = math.abs(math.cos(x))
    return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

local function ChangeVision()
    PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)
    if vision_state == 0 then
        SetNightvision(true)
        vision_state = 1
    elseif vision_state == 1 then
        SetNightvision(false)
        SetSeethrough(true)
        vision_state = 2
    else
        SetSeethrough(false)
        vision_state = 0
    end
end

local function ChangeDisplay()
    if vehicle_display == 0 then
        vehicle_display = 1
    elseif vehicle_display == 1 then
        vehicle_display = 2
    else
        vehicle_display = 0
    end
end

local function HideHUDThisFrame()
    HideHelpTextThisFrame()
    HideHudAndRadarThisFrame()
    HideHudComponentThisFrame(19) -- weapon wheel
    HideHudComponentThisFrame(1)  -- Wanted Stars
    HideHudComponentThisFrame(2)  -- Weapon icon
    HideHudComponentThisFrame(3)  -- Cash
    HideHudComponentThisFrame(4)  -- MP CASH
    HideHudComponentThisFrame(13) -- Cash Change
    HideHudComponentThisFrame(11) -- Floating Help Text
    HideHudComponentThisFrame(12) -- more floating help text
    HideHudComponentThisFrame(15) -- Subtitle Text
    HideHudComponentThisFrame(18) -- Game Stream
end

local function CheckInputRotation(cam, zoomvalue)
    local rightAxisX = GetDisabledControlNormal(0, 220)
    local rightAxisY = GetDisabledControlNormal(0, 221)
    local rotation = GetCamRot(cam, 2)
    if rightAxisX ~= 0.0 or rightAxisY ~= 0.0 then
        local new_z = rotation.z + rightAxisX * -1.0 * speed_ud * (zoomvalue + 0.1)
        local new_x = math.max(math.min(20.0, rotation.x + rightAxisY * -1.0 * speed_lr * (zoomvalue + 0.1)), -89.5)
        SetCamRot(cam, new_x, 0.0, new_z, 2)
    end
end

local function HandleZoom(cam)
    if IsControlJustPressed(0, 241) then -- Scroll up
        fov = math.max(fov - zoomspeed, fov_min)
    end
    if IsControlJustPressed(0, 242) then -- Scroll down
        fov = math.min(fov + zoomspeed, fov_max)
    end
    local current_fov = GetCamFov(cam)
    if math.abs(fov - current_fov) < 0.1 then
        fov = current_fov
    end
    SetCamFov(cam, current_fov + (fov - current_fov) * 0.05)
end

local function GetVehicleInView(cam)
    local coords = GetCamCoord(cam)
    local forward_vector = RotAnglesToVec(GetCamRot(cam, 2))
    local rayhandle = CastRayPointToPoint(coords, coords + (forward_vector * 200.0), 10, cache.vehicle, 0)
    local _, _, _, _, entityHit = GetRaycastResult(rayhandle)
    if entityHit > 0 and IsEntityAVehicle(entityHit) then
        return entityHit
    end
end

local function RenderVehicleInfo(vehicle)
    if not DoesEntityExist(vehicle) then return end
    local model = GetEntityModel(vehicle)
    local vehname = GetLabelText(GetDisplayNameFromVehicleModel(model))
    local licenseplate = GetVehicleNumberPlateText(vehicle)
    local vehspeed = GetEntitySpeed(vehicle) * (speed_measure == "MPH" and 2.236936 or 3.6)
    SetTextFont(0)
    SetTextProportional(1)
    SetTextScale(0.0, vehicle_display == 0 and 0.49 or 0.55)
    SetTextColour(255, 255, 255, 255)
    SetTextDropshadow(0, 0, 0, 0, 255)
    SetTextEdge(1, 0, 0, 0, 255)
    SetTextDropShadow()
    SetTextOutline()
    SetTextEntry("STRING")
    if vehicle_display == 0 then
        AddTextComponentString(("Speed: %d %s\nModel: %s\nPlate: %s"):format(math.ceil(vehspeed), speed_measure, vehname, licenseplate))
    else
        AddTextComponentString(("Model: %s\nPlate: %s"):format(vehname, licenseplate))
    end
    DrawText(0.45, 0.9)
end

local function ReleaseTarget()
    if target_vehicle then
        DecorRemove(target_vehicle, "Target")
    end
    if tracking_spotlight then
        TriggerServerEvent("heli:tracking.spotlight.toggle")
        tracking_spotlight = false
    end
    pause_Tspotlight = false
    target_vehicle = nil
    target_plate = nil
    helicamState.locked_on_vehicle = nil
end

local function StartTrackingSpotlight(vehicle)
    local netID = VehToNet(vehicle)
    local plate = GetVehicleNumberPlateText(vehicle)
    local px, py, pz = table.unpack(GetEntityCoords(vehicle))
    pause_Tspotlight = false
    tracking_spotlight = true
    TriggerServerEvent("heli:tracking.spotlight", netID, plate, px, py, pz)
end

local function BuildFreeCam(heli, rot, saved_fov)
    local cam = CreateCam("DEFAULT_SCRIPTED_FLY_CAMERA", true)
    AttachCamToEntity(cam, heli, 0.0, 0.0, -1.5, true)
    SetCamRot(cam, rot, 2)
    SetCamFov(cam, saved_fov)
    RenderScriptCams(true, false, 0, 1, 0)
    return cam
end

---=========================
--- Entity Enumerator	====
---=========================
-- From IllidanS4: https://gist.github.com/IllidanS4/9865ed17f60576425369fc1da70259b2

local entityEnumerator = {
    __gc = function(enum)
        if enum.destructor and enum.handle then
            enum.destructor(enum.handle)
        end
        enum.destructor = nil
        enum.handle = nil
    end
}

local function EnumerateEntities(initFunc, moveFunc, disposeFunc)
    return coroutine.wrap(function()
        local iter, id = initFunc()
        if not id or id == 0 then
            disposeFunc(iter)
            return
        end
        local enum = {handle = iter, destructor = disposeFunc}
        setmetatable(enum, entityEnumerator)
        local next = true
        repeat
            coroutine.yield(id)
            next, id = moveFunc(iter)
        until not next
        enum.destructor, enum.handle = nil, nil
        disposeFunc(iter)
    end)
end

local function EnumerateVehicles()
    return EnumerateEntities(FindFirstVehicle, FindNextVehicle, EndFindVehicle)
end

local function FindVehicleByPlate(plate)
    for vehicle in EnumerateVehicles() do
        if GetVehicleNumberPlateText(vehicle) == plate then
            return vehicle
        end
    end
end

---=========================
--- Helicam Render Loop	====
---=========================

local function startHelicamLoop(heli)
    local lPed = cache.ped

    SetTimecycleModifier("heliGunCam")
    SetTimecycleModifierStrength(0.3)

    local scaleform = RequestScaleformMovie("HELI_CAM")
    while not HasScaleformMovieLoaded(scaleform) do
        Wait(0)
    end

    local cam = CreateCam("DEFAULT_SCRIPTED_FLY_CAMERA", true)
    AttachCamToEntity(cam, heli, 0.0, 0.0, -1.5, true)
    SetCamRot(cam, 0.0, 0.0, GetEntityHeading(heli))
    SetCamFov(cam, fov)
    RenderScriptCams(true, false, 0, 1, 0)

    PushScaleformMovieFunction(scaleform, "SET_CAM_LOGO")
    PushScaleformMovieFunctionParameterInt(0) -- 0 = no logo, 1 = LSPD
    PopScaleformMovieFunctionVoid()

    helicamState.cam = cam
    helicamState.locked_on_vehicle = nil

    while helicam and not IsEntityDead(lPed) and GetVehiclePedIsIn(lPed) == heli and GetEntityHeightAboveGround(heli) >= 1.5 do
        -- Sync cam reference in case an onPressed callback swapped it (e.g. lock-off rebuilds cam)
        cam = helicamState.cam

        local zoomvalue = (1.0 / (fov_max - fov_min)) * (fov - fov_min)
        local locked = helicamState.locked_on_vehicle

        if locked then
            if DoesEntityExist(locked) then
                PointCamAtEntity(cam, locked, 0.0, 0.0, 0.0, true)
                RenderVehicleInfo(locked)

                -- Auto-release if target flies out of range
                local dist = #(GetEntityCoords(heli) - GetEntityCoords(locked))
                if dist > maxtargetdistance then
                    PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)
                    ReleaseTarget()
                    -- Rebuild free cam at current angle
                    local rot = GetCamRot(cam, 2)
                    local saved_fov = GetCamFov(cam)
                    DestroyCam(cam, false)
                    cam = BuildFreeCam(heli, rot, saved_fov)
                    helicamState.cam = cam
                end
            else
                -- Entity deleted
                target_vehicle = nil
                helicamState.locked_on_vehicle = nil
            end
        else
            CheckInputRotation(cam, zoomvalue)
            local vehicle_detected = GetVehicleInView(cam)
            if vehicle_detected and DoesEntityExist(vehicle_detected) then
                RenderVehicleInfo(vehicle_detected)
            end
        end

        HandleZoom(cam)
        HideHUDThisFrame()

        PushScaleformMovieFunction(scaleform, "SET_ALT_FOV_HEADING")
        PushScaleformMovieFunctionParameterFloat(GetEntityCoords(heli).z)
        PushScaleformMovieFunctionParameterFloat(zoomvalue)
        PushScaleformMovieFunctionParameterFloat(GetCamRot(cam, 2).z)
        PopScaleformMovieFunctionVoid()
        DrawScaleformMovieFullscreen(scaleform, 255, 255, 255, 255)

        if manual_spotlight then
            local forward_vector = RotAnglesToVec(GetCamRot(cam, 2))
            local camcoords = GetCamCoord(cam)
            DecorSetInt(lPed, "SpotvectorX", forward_vector.x)
            DecorSetInt(lPed, "SpotvectorY", forward_vector.y)
            DecorSetInt(lPed, "SpotvectorZ", forward_vector.z)
            DrawSpotLight(camcoords, forward_vector, 255, 255, 255, 800.0, 10.0, brightness, spotradius, 1.0, 1.0)
        end

        Wait(0)
    end

    -- Cleanup
    if manual_spotlight then
        manual_spotlight = false
        TriggerServerEvent("heli:manual.spotlight.toggle")
    end
    helicam = false
    helicamState.cam = nil
    helicamState.locked_on_vehicle = nil
    ClearTimecycleModifier()
    fov = (fov_max + fov_min) * 0.5
    RenderScriptCams(false, false, 0, 1, 0)
    SetScaleformMovieAsNoLongerNeeded(scaleform)
    DestroyCam(cam, false)
    SetNightvision(false)
    SetSeethrough(false)
    vision_state = 0
end

---=========================
--- Vehicle Cache		====
--- Spawns the heli thread only while in a valid heli model.
--- No thread runs when the player is not in a recognised heli.
---=========================

lib.onCache("vehicle", function(vehicle)
    if not vehicle then
        -- Left vehicle — reset all state
        if helicam then helicam = false end
        if tracking_spotlight then
            TriggerServerEvent("heli:tracking.spotlight.toggle")
            tracking_spotlight = false
        end
        if Fspotlight_state then
            Fspotlight_state = false
            TriggerServerEvent("heli:forward.spotlight", false)
        end
        target_vehicle = nil
        target_plate = nil
        currentHeli = nil

		for _, keybind in ipairs(helicamKeybinds) do
			keybind:disable(true)
		end

        return
    end

    if not lib.table.contains(heliModels, GetEntityModel(vehicle)) then return end

	for _, keybind in ipairs(helicamKeybinds) do
		keybind:disable(false)
	end
    currentHeli = vehicle

    CreateThread(function()
        while currentHeli do
            -- Outside helicam: check if tracked target has gone out of range (pilot seat only)
            if not helicam and target_vehicle and GetPedInVehicleSeat(currentHeli, -1) == cache.ped then
                local dist = #(GetEntityCoords(currentHeli) - GetEntityCoords(target_vehicle))
                if dist > maxtargetdistance then
                    PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)
                    ReleaseTarget()
                end
            end

            -- Render target info overlay outside helicam
            if not helicam and target_vehicle and vehicle_display ~= 2 then
                RenderVehicleInfo(target_vehicle)
            end

            -- When helicam is activated, hand off to the render loop (blocks here until helicam exits)
            if helicam then
                startHelicamLoop(currentHeli)
            end

            -- Light wait: all discrete input is event-driven via onPressed keybinds.
            -- We only need this loop for the distance check and info overlay.
            Wait(0)
        end
    end)
end)

---=========================
--- Keybinds			====
---=========================

helicamKeybinds[#helicamKeybinds + 1] = lib.addKeybind({
    name = 'toggle_helicam',
    description = Config.Keybinds["toggle_helicam"].description,
    defaultKey = Config.Keybinds["toggle_helicam"].defaultKey,
    defaultMapper = Config.Keybinds["toggle_helicam"].defaultMapper,
	disabled = true,
    onPressed = function()
        if not currentHeli then return end
        if GetEntityHeightAboveGround(currentHeli) < 1.5 then return end
        PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)
        if helicam then
            -- Exiting helicam: hand off manual spotlight to tracking spotlight if applicable
            if manual_spotlight and target_vehicle then
                TriggerServerEvent("heli:manual.spotlight.toggle")
                StartTrackingSpotlight(target_vehicle)
            end
            helicam = false -- signals startHelicamLoop to exit
        else
            helicam = true -- thread will pick this up and call startHelicamLoop
        end
    end
})

helicamKeybinds[#helicamKeybinds + 1] = lib.addKeybind({
    name = 'toggle_vision',
    description = Config.Keybinds["toggle_vision"].description,
    defaultMapper = Config.Keybinds["toggle_vision"].defaultMapper,
    defaultKey = Config.Keybinds["toggle_vision"].defaultKey,
	disabled = true,
    onPressed = function()
        if not currentHeli or not helicam then return end
        ChangeVision()
    end
})

helicamKeybinds[#helicamKeybinds + 1] = lib.addKeybind({
    name = 'toggle_display',
    description = Config.Keybinds["toggle_display"].description,
    defaultKey = Config.Keybinds["toggle_display"].defaultKey,
    defaultMapper = Config.Keybinds["toggle_display"].defaultMapper,
	disabled = true,
    onPressed = function()
        if not currentHeli then return end
        ChangeDisplay()
    end
})

helicamKeybinds[#helicamKeybinds + 1] = lib.addKeybind({
    name = 'toggle_spotlight',
    description = Config.Keybinds["toggle_spotlight"].description,
    defaultKey = Config.Keybinds["toggle_spotlight"].defaultKey,
    defaultMapper = Config.Keybinds["toggle_spotlight"].defaultMapper,
	disabled = true,
    onPressed = function()
        if not currentHeli then return end
        if GetPedInVehicleSeat(currentHeli, -1) ~= cache.ped then return end
        PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)

        if helicam then
            -- Inside helicam: cycle manual spotlight
            if tracking_spotlight then
                pause_Tspotlight = true
                TriggerServerEvent("heli:pause.tracking.spotlight", true)
                manual_spotlight = not manual_spotlight
                if manual_spotlight then
                    local cam = helicamState.cam
                    if cam then
                        local fv = RotAnglesToVec(GetCamRot(cam, 2))
                        DecorSetInt(cache.ped, "SpotvectorX", fv.x)
                        DecorSetInt(cache.ped, "SpotvectorY", fv.y)
                        DecorSetInt(cache.ped, "SpotvectorZ", fv.z)
                    end
                    TriggerServerEvent("heli:manual.spotlight")
                else
                    TriggerServerEvent("heli:manual.spotlight.toggle")
                end
            elseif Fspotlight_state then
                Fspotlight_state = false
                TriggerServerEvent("heli:forward.spotlight", false)
                manual_spotlight = not manual_spotlight
                if manual_spotlight then
                    TriggerServerEvent("heli:manual.spotlight")
                else
                    TriggerServerEvent("heli:manual.spotlight.toggle")
                end
            else
                manual_spotlight = not manual_spotlight
                if manual_spotlight then
                    TriggerServerEvent("heli:manual.spotlight")
                else
                    TriggerServerEvent("heli:manual.spotlight.toggle")
                end
            end
        else
            -- Outside helicam: toggle forward or tracking spotlight
            if target_vehicle then
                if tracking_spotlight then
                    pause_Tspotlight = not pause_Tspotlight
                    TriggerServerEvent("heli:pause.tracking.spotlight", pause_Tspotlight)
                else
                    if Fspotlight_state then
                        Fspotlight_state = false
                        TriggerServerEvent("heli:forward.spotlight", false)
                    end
                    StartTrackingSpotlight(target_vehicle)
                end
            else
                if tracking_spotlight then
                    tracking_spotlight = false
                    pause_Tspotlight = false
                    TriggerServerEvent("heli:tracking.spotlight.toggle")
                end
                Fspotlight_state = not Fspotlight_state
                TriggerServerEvent("heli:forward.spotlight", Fspotlight_state)
            end
        end
    end
})

helicamKeybinds[#helicamKeybinds + 1] = lib.addKeybind({
    name = 'toggle_lock_on',
    description = Config.Keybinds["toggle_lock_on"].description,
    defaultKey = Config.Keybinds["toggle_lock_on"].defaultKey,
    defaultMapper = Config.Keybinds["toggle_lock_on"].defaultMapper,
	disabled = true,
    onPressed = function()
        if not currentHeli then return end

        if helicam then
            local locked = helicamState.locked_on_vehicle
            if locked then
                -- Release lock
                PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)
                ReleaseTarget()
                -- Rebuild free cam so we can pan freely again
                local cam = helicamState.cam
                if cam then
                    local rot = GetCamRot(cam, 2)
                    local saved_fov = GetCamFov(cam)
                    DestroyCam(cam, false)
                    helicamState.cam = BuildFreeCam(currentHeli, rot, saved_fov)
                end
            else
                -- Lock on to whatever vehicle is in the camera's crosshair
                local cam = helicamState.cam
                if not cam then return end
                local detected = GetVehicleInView(cam)
                if not detected then return end

                PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)

                if target_vehicle then
                    DecorRemove(target_vehicle, "Target")
                end

                target_vehicle = detected
                target_plate = GetVehicleNumberPlateText(target_vehicle)
                NetworkRequestControlOfEntity(target_vehicle)
                local netID = VehToNet(target_vehicle)
                SetNetworkIdCanMigrate(netID, true)
                NetworkRegisterEntityAsNetworked(netID)
                SetNetworkIdExistsOnAllMachines(target_vehicle, true)
                SetEntityAsMissionEntity(target_vehicle, true, true)
                DecorSetInt(target_vehicle, "Target", 2)
                helicamState.locked_on_vehicle = target_vehicle

                if tracking_spotlight then
                    -- Re-target tracking spotlight to new vehicle
                    TriggerServerEvent("heli:tracking.spotlight.toggle")
                    if not pause_Tspotlight then
                        StartTrackingSpotlight(target_vehicle)
                    else
                        tracking_spotlight = false
                        pause_Tspotlight = false
                    end
                end
            end
        elseif GetPedInVehicleSeat(currentHeli, -1) == cache.ped then
            -- Outside helicam, pilot only: manually release target
            if not target_vehicle then return end
            PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)
            ReleaseTarget()
        end
    end
})

helicamKeybinds[#helicamKeybinds + 1] = lib.addKeybind({
    name = 'toggle_rappel',
    description = Config.Keybinds["toggle_rappel"].description,
    defaultKey = Config.Keybinds["toggle_rappel"].defaultKey,
    defaultMapper = Config.Keybinds["toggle_rappel"].defaultMapper,
	disabled = true,
    onPressed = function()
        if not currentHeli then return end
        if GetEntityHeightAboveGround(currentHeli) < 1.5 then return end
        local lPed = cache.ped
        if GetPedInVehicleSeat(currentHeli, 1) == lPed or GetPedInVehicleSeat(currentHeli, 2) == lPed then
            PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)
            TaskRappelFromHeli(lPed, 1)
        else
            SetNotificationTextEntry("STRING")
            AddTextComponentString("~r~Can't rappel from this seat")
            DrawNotification(false, false)
            PlaySoundFrontend(-1, "5_Second_Timer", "DLC_HEISTS_GENERAL_FRONTEND_SOUNDS", false)
        end
    end
})

helicamKeybinds[#helicamKeybinds + 1] = lib.addKeybind({
    name = 'spotlight_light_up',
    description = Config.Keybinds["spotlight_light_up"].description,
    defaultKey = Config.Keybinds["spotlight_light_up"].defaultKey,
    defaultMapper = Config.Keybinds["spotlight_light_up"].defaultMapper,
	disabled = true,
    onPressed = function()
        if not currentHeli then return end
        TriggerServerEvent("heli:light.up")
    end
})

helicamKeybinds[#helicamKeybinds + 1] = lib.addKeybind({
    name = 'spotlight_light_down',
    description = Config.Keybinds["spotlight_light_down"].description,
    defaultKey = Config.Keybinds["spotlight_light_down"].defaultKey,
    defaultMapper = Config.Keybinds["spotlight_light_down"].defaultMapper,
	disabled = true,
    onPressed = function()
        if not currentHeli then return end
        TriggerServerEvent("heli:light.down")
    end
})

helicamKeybinds[#helicamKeybinds + 1] = lib.addKeybind({
    name = 'spotlight_radius_up',
    description = Config.Keybinds["spotlight_radius_up"].description,
    defaultKey = Config.Keybinds["spotlight_radius_up"].defaultKey,
    defaultMapper = Config.Keybinds["spotlight_radius_up"].defaultMapper,
	disabled = true,
    onPressed = function()
        if not currentHeli then return end
        TriggerServerEvent("heli:radius.up")
    end
})

helicamKeybinds[#helicamKeybinds + 1] = lib.addKeybind({
    name = 'spotlight_radius_down',
    description = Config.Keybinds["spotlight_radius_down"].description,
    defaultKey = Config.Keybinds["spotlight_radius_down"].defaultKey,
    defaultMapper = Config.Keybinds["spotlight_radius_down"].defaultMapper,
	disabled = true,
    onPressed = function()
        if not currentHeli then return end
        TriggerServerEvent("heli:radius.down")
    end
})

---=========================
--- Net Events			====
---=========================

RegisterNetEvent('heli:forward.spotlight')
AddEventHandler('heli:forward.spotlight', function(serverID, state)
    local heli = GetVehiclePedIsIn(GetPlayerPed(GetPlayerFromServerId(serverID)), false)
    SetVehicleSearchlight(heli, state, false)
end)

RegisterNetEvent('heli:Tspotlight')
AddEventHandler('heli:Tspotlight', function(serverID, target_netID, recv_plate, targetposx, targetposy, targetposz)
    -- Multi-fallback client-side target identification
    local found = nil
    if GetVehicleNumberPlateText(NetToVeh(target_netID)) == recv_plate then
        found = NetToVeh(target_netID)
    elseif GetVehicleNumberPlateText(DoesVehicleExistWithDecorator("Target")) == recv_plate then
        found = DoesVehicleExistWithDecorator("Target")
    elseif GetVehicleNumberPlateText(GetClosestVehicle(targetposx, targetposy, targetposz, 25.0, 0, 70)) == recv_plate then
        found = GetClosestVehicle(targetposx, targetposy, targetposz, 25.0, 0, 70)
    else
        found = FindVehicleByPlate(recv_plate)
    end

    Tspotlight_target = found
    local heliPed = GetPlayerPed(GetPlayerFromServerId(serverID))
    local heli = GetVehiclePedIsIn(heliPed, false)
    Tspotlight_toggle = true
    Tspotlight_pause = false
    tracking_spotlight = true

    while not IsEntityDead(heliPed) and GetVehiclePedIsIn(heliPed) == heli and Tspotlight_target and Tspotlight_toggle do
        Wait(1)
        local helicoords = GetEntityCoords(heli)
        local targetcoords = GetEntityCoords(Tspotlight_target)
        local spotVector = targetcoords - helicoords
        local dist = Vdist(targetcoords, helicoords)
        if not Tspotlight_pause then
            DrawSpotLight(helicoords.x, helicoords.y, helicoords.z, spotVector.x, spotVector.y, spotVector.z, 255, 255, 255, dist + 20, 10.0, brightness, 4.0, 1.0, 0.0)
        end
        if dist > maxtargetdistance then
            DecorRemove(Tspotlight_target, "Target")
            target_vehicle = nil
            tracking_spotlight = false
            TriggerServerEvent("heli:tracking.spotlight.toggle")
            Tspotlight_target = nil
            break
        end
    end

    Tspotlight_toggle = false
    Tspotlight_pause = false
    Tspotlight_target = nil
    tracking_spotlight = false
end)

RegisterNetEvent('heli:Tspotlight.toggle')
AddEventHandler('heli:Tspotlight.toggle', function()
    Tspotlight_toggle = false
    tracking_spotlight = false
end)

RegisterNetEvent('heli:pause.Tspotlight')
AddEventHandler('heli:pause.Tspotlight', function(serverID, pause)
    Tspotlight_pause = pause
end)

RegisterNetEvent('heli:Mspotlight')
AddEventHandler('heli:Mspotlight', function(serverID)
    if GetPlayerServerId(PlayerId()) == serverID then return end -- pilot sees their own spotlight directly
    local heliPed = GetPlayerPed(GetPlayerFromServerId(serverID))
    local heli = GetVehiclePedIsIn(heliPed, false)
    Mspotlight_toggle = true
    while not IsEntityDead(heliPed) and GetVehiclePedIsIn(heliPed) == heli and Mspotlight_toggle do
        Wait(0)
        local helicoords = GetEntityCoords(heli)
        local spotoffset = helicoords + vector3(0.0, 0.0, -1.5)
        local svx = DecorGetInt(heliPed, "SpotvectorX")
        local svy = DecorGetInt(heliPed, "SpotvectorY")
        local svz = DecorGetInt(heliPed, "SpotvectorZ")
        if svx then
            DrawSpotLight(spotoffset.x, spotoffset.y, spotoffset.z, svx, svy, svz, 255, 255, 255, 800.0, 10.0, brightness, spotradius, 1.0, 1.0)
        end
    end
    Mspotlight_toggle = false
    DecorSetInt(heliPed, "SpotvectorX", nil)
    DecorSetInt(heliPed, "SpotvectorY", nil)
    DecorSetInt(heliPed, "SpotvectorZ", nil)
end)

RegisterNetEvent('heli:Mspotlight.toggle')
AddEventHandler('heli:Mspotlight.toggle', function()
    Mspotlight_toggle = false
end)

RegisterNetEvent('heli:light.up')
AddEventHandler('heli:light.up', function()
    if brightness < 10 then
        brightness = brightness + 1.0
        PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)
    end
end)

RegisterNetEvent('heli:light.down')
AddEventHandler('heli:light.down', function()
    if brightness > 1.0 then
        brightness = brightness - 1.0
        PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)
    end
end)

RegisterNetEvent('heli:radius.up')
AddEventHandler('heli:radius.up', function()
    if spotradius < 10.0 then
        spotradius = spotradius + 1.0
        PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)
    end
end)

RegisterNetEvent('heli:radius.down')
AddEventHandler('heli:radius.down', function()
    if spotradius > 4.0 then
        spotradius = spotradius - 1.0
        PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false)
    end
end)