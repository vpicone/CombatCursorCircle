local ADDON_NAME, CCC = ...

-------------------------------------------------------------------------------
-- Defaults
-------------------------------------------------------------------------------
CCC.DEFAULTS = {
    enabled   = true,
    radius    = 40,
    thickness = 2,
    segments  = 48,
    colorR    = 1.0,
    colorG    = 0.2,
    colorB    = 0.2,
    opacity   = 0.8,
    fadeIn    = 0.3,
    fadeOut   = 0.5,
    pulse     = false,
    pulseSpeed = 1.5,
}

-------------------------------------------------------------------------------
-- Database
-------------------------------------------------------------------------------
local function InitDB()
    if not CombatCursorCircleDB then
        CombatCursorCircleDB = {}
    end
    for k, v in pairs(CCC.DEFAULTS) do
        if CombatCursorCircleDB[k] == nil then
            CombatCursorCircleDB[k] = v
        end
    end
    CCC.db = CombatCursorCircleDB
end

-------------------------------------------------------------------------------
-- Chat helpers
-------------------------------------------------------------------------------
local CHAT_PREFIX = "|cff00ccff[CCC]|r "

function CCC:PrintMessage(msg)
    print(CHAT_PREFIX .. msg)
end

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------
local function Clamp(val, lo, hi)
    if val < lo then return lo end
    if val > hi then return hi end
    return val
end

local function PrintHelp()
    CCC:PrintMessage("Commands:")
    CCC:PrintMessage("  /ccc toggle - Enable/disable the addon")
    CCC:PrintMessage("  /ccc radius <10-200> - Set ring radius")
    CCC:PrintMessage("  /ccc color <r> <g> <b> - Set color (0-1 each)")
    CCC:PrintMessage("  /ccc opacity <0-1> - Set ring opacity")
    CCC:PrintMessage("  /ccc thickness <1-10> - Set line thickness")
    CCC:PrintMessage("  /ccc segments <12-128> - Set segment count")
    CCC:PrintMessage("  /ccc pulse - Toggle pulse animation")
    CCC:PrintMessage("  /ccc pulsespeed <0.5-5> - Set pulse speed")
    CCC:PrintMessage("  /ccc fadein <0-2> - Set fade-in duration")
    CCC:PrintMessage("  /ccc fadeout <0-2> - Set fade-out duration")
    CCC:PrintMessage("  /ccc test - Preview ring for 3 seconds")
    CCC:PrintMessage("  /ccc status - Show current settings")
    CCC:PrintMessage("  /ccc reset - Restore defaults")
    CCC:PrintMessage("  /ccc options - Open settings panel")
end

local function PrintStatus()
    local db = CCC.db
    CCC:PrintMessage("Status:")
    CCC:PrintMessage(string.format("  Enabled: %s", db.enabled and "yes" or "no"))
    CCC:PrintMessage(string.format("  Radius: %d", db.radius))
    CCC:PrintMessage(string.format("  Color: %.2f, %.2f, %.2f", db.colorR, db.colorG, db.colorB))
    CCC:PrintMessage(string.format("  Opacity: %.2f", db.opacity))
    CCC:PrintMessage(string.format("  Thickness: %d", db.thickness))
    CCC:PrintMessage(string.format("  Segments: %d", db.segments))
    CCC:PrintMessage(string.format("  Pulse: %s (speed %.1f)", db.pulse and "on" or "off", db.pulseSpeed))
    CCC:PrintMessage(string.format("  Fade in: %.2fs / Fade out: %.2fs", db.fadeIn, db.fadeOut))
end

function CCC:HandleSlashCommand(input)
    local args = {}
    for word in input:gmatch("%S+") do
        args[#args + 1] = word:lower()
    end
    local cmd = args[1]

    if not cmd then
        PrintHelp()
        return
    end

    local db = self.db

    if cmd == "toggle" then
        db.enabled = not db.enabled
        self:PrintMessage("Addon " .. (db.enabled and "|cff00ff00enabled|r" or "|cffff0000disabled|r"))
        if not db.enabled then
            self:HideRing()
        end

    elseif cmd == "radius" then
        local val = tonumber(args[2])
        if not val then self:PrintMessage("Usage: /ccc radius <10-200>"); return end
        db.radius = Clamp(math.floor(val), 10, 200)
        self:PrintMessage("Radius set to " .. db.radius)
        self:RebuildRing()

    elseif cmd == "color" then
        local r, g, b = tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
        if not (r and g and b) then self:PrintMessage("Usage: /ccc color <r> <g> <b> (0-1 each)"); return end
        db.colorR = Clamp(r, 0, 1)
        db.colorG = Clamp(g, 0, 1)
        db.colorB = Clamp(b, 0, 1)
        self:PrintMessage(string.format("Color set to %.2f, %.2f, %.2f", db.colorR, db.colorG, db.colorB))
        self:UpdateRingAppearance()

    elseif cmd == "opacity" then
        local val = tonumber(args[2])
        if not val then self:PrintMessage("Usage: /ccc opacity <0-1>"); return end
        db.opacity = Clamp(val, 0, 1)
        self:PrintMessage(string.format("Opacity set to %.2f", db.opacity))
        self:UpdateRingAppearance()

    elseif cmd == "thickness" then
        local val = tonumber(args[2])
        if not val then self:PrintMessage("Usage: /ccc thickness <1-10>"); return end
        db.thickness = Clamp(math.floor(val), 1, 10)
        self:PrintMessage("Thickness set to " .. db.thickness)
        self:RebuildRing()

    elseif cmd == "segments" then
        local val = tonumber(args[2])
        if not val then self:PrintMessage("Usage: /ccc segments <12-128>"); return end
        db.segments = Clamp(math.floor(val), 12, 128)
        self:PrintMessage("Segments set to " .. db.segments)
        self:RebuildRing()

    elseif cmd == "pulse" then
        db.pulse = not db.pulse
        self:PrintMessage("Pulse " .. (db.pulse and "|cff00ff00on|r" or "|cffff0000off|r"))
        self:UpdatePulseAnimation()

    elseif cmd == "pulsespeed" then
        local val = tonumber(args[2])
        if not val then self:PrintMessage("Usage: /ccc pulsespeed <0.5-5>"); return end
        db.pulseSpeed = Clamp(val, 0.5, 5.0)
        self:PrintMessage(string.format("Pulse speed set to %.1f", db.pulseSpeed))

    elseif cmd == "fadein" then
        local val = tonumber(args[2])
        if not val then self:PrintMessage("Usage: /ccc fadein <0-2>"); return end
        db.fadeIn = Clamp(val, 0, 2)
        self:PrintMessage(string.format("Fade-in set to %.2fs", db.fadeIn))
        self:UpdateFadeAnimations()

    elseif cmd == "fadeout" then
        local val = tonumber(args[2])
        if not val then self:PrintMessage("Usage: /ccc fadeout <0-2>"); return end
        db.fadeOut = Clamp(val, 0, 2)
        self:PrintMessage(string.format("Fade-out set to %.2fs", db.fadeOut))
        self:UpdateFadeAnimations()

    elseif cmd == "test" then
        self:TestRing(3)

    elseif cmd == "options" or cmd == "settings" or cmd == "config" then
        self:OpenSettings()

    elseif cmd == "status" then
        PrintStatus()

    elseif cmd == "reset" then
        for k, v in pairs(self.DEFAULTS) do
            db[k] = v
        end
        self:PrintMessage("Settings restored to defaults.")
        self:RebuildRing()
        self:UpdateFadeAnimations()
        self:UpdatePulseAnimation()

    else
        self:PrintMessage("Unknown command: " .. cmd)
        PrintHelp()
    end
end

function CCC:InitSlashCommands()
    SLASH_COMBATCURSORCIRCLE1 = "/ccc"
    SLASH_COMBATCURSORCIRCLE2 = "/combatcursor"
    SlashCmdList["COMBATCURSORCIRCLE"] = function(msg)
        CCC:HandleSlashCommand(msg or "")
    end
end

-------------------------------------------------------------------------------
-- AddonCompartment (minimap menu)
-------------------------------------------------------------------------------
function CombatCursorCircle_OnAddonCompartmentClick(_, button)
    if button == "LeftButton" then
        CCC.db.enabled = not CCC.db.enabled
        CCC:PrintMessage("Addon " .. (CCC.db.enabled and "|cff00ff00enabled|r" or "|cffff0000disabled|r"))
        if not CCC.db.enabled then
            CCC:HideRing()
        end
    else
        CCC:OpenSettings()
    end
end

function CombatCursorCircle_OnAddonCompartmentEnter(_, menuButtonFrame)
    GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT")
    GameTooltip:AddLine("CombatCursorCircle")
    GameTooltip:AddLine("Left-click: Toggle on/off", 1, 1, 1)
    GameTooltip:AddLine("Right-click: Open settings", 1, 1, 1)
    GameTooltip:Show()
end

function CombatCursorCircle_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

-------------------------------------------------------------------------------
-- Event handling
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        InitDB()
        CCC:InitRing()
        CCC:InitSlashCommands()
        CCC:InitSettings()
        -- Handle login during combat (reconnect)
        if InCombatLockdown() and CCC.db.enabled then
            CCC:ShowRing()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if CCC.db.enabled then
            CCC:ShowRing()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        CCC:HideRing()
    end
end)
