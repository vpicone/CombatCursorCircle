local ADDON_NAME, CCC = ...

local PI2 = math.pi * 2
local cos, sin = math.cos, math.sin

-- References for refresh
local controls = {}
local settingsCategory
local previewFrame, previewLineFrame, previewLines, previewElapsed

-------------------------------------------------------------------------------
-- UI Helpers
-------------------------------------------------------------------------------
local function CreateSectionHeader(parent, x, y, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    fs:SetTextColor(1, 0.82, 0)
    return fs
end

local sliderCount = 0
local function CreateSettingsSlider(parent, x, y, label, min, max, step, getter, setter, formatter)
    sliderCount = sliderCount + 1
    local name = "CCC_Slider" .. sliderCount

    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", x, y)
    title:SetText(label)

    local valueFs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    valueFs:SetPoint("LEFT", title, "LEFT", 270, 0)

    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", x, y - 15)
    slider:SetWidth(260)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    -- Hide template labels (they duplicate our custom ones)
    if slider.Text then slider.Text:SetText("") end
    if slider.Low then slider.Low:SetText("") end
    if slider.High then slider.High:SetText("") end

    local updating = false

    local function UpdateDisplay(val)
        valueFs:SetText(formatter and formatter(val) or string.format("%g", val))
    end

    slider:SetScript("OnValueChanged", function(_, val)
        if updating then return end
        val = math.floor(val / step + 0.5) * step
        setter(val)
        UpdateDisplay(val)
    end)

    slider:SetValue(getter())
    UpdateDisplay(getter())

    return {
        Refresh = function()
            updating = true
            slider:SetValue(getter())
            updating = false
            UpdateDisplay(getter())
        end,
    }
end

local function CreateSettingsCheckbox(parent, x, y, label, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb:SetSize(26, 26)

    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    text:SetText(label)

    cb:SetChecked(getter())
    cb:SetScript("OnClick", function(self)
        setter(self:GetChecked())
    end)

    return {
        Refresh = function()
            cb:SetChecked(getter())
        end,
    }
end

local function CreateColorSwatch(parent, x, y, label, getColor, setColor)
    local swatch = CreateFrame("Button", nil, parent)
    swatch:SetPoint("TOPLEFT", x, y)
    swatch:SetSize(26, 26)

    local border = swatch:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.3, 0.3, 0.3, 1)

    local colorTex = swatch:CreateTexture(nil, "ARTWORK")
    colorTex:SetPoint("TOPLEFT", 2, -2)
    colorTex:SetPoint("BOTTOMRIGHT", -2, 2)
    local r, g, b = getColor()
    colorTex:SetColorTexture(r, g, b, 1)

    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
    text:SetText(label)

    swatch:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Click to change color")
        GameTooltip:Show()
    end)
    swatch:SetScript("OnLeave", function() GameTooltip:Hide() end)

    swatch:SetScript("OnClick", function()
        local cr, cg, cb = getColor()
        local info = {
            r = cr, g = cg, b = cb,
            hasOpacity = false,
            swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                setColor(nr, ng, nb)
                colorTex:SetColorTexture(nr, ng, nb, 1)
            end,
            cancelFunc = function(prev)
                setColor(prev.r, prev.g, prev.b)
                colorTex:SetColorTexture(prev.r, prev.g, prev.b, 1)
            end,
        }
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)

    return {
        Refresh = function()
            local r, g, b = getColor()
            colorTex:SetColorTexture(r, g, b, 1)
        end,
    }
end

local function CreateSettingsButton(parent, x, y, label, width, onClick)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetPoint("TOPLEFT", x, y)
    btn:SetSize(width, 24)
    btn:SetText(label)
    btn:SetScript("OnClick", onClick)
    return btn
end

-------------------------------------------------------------------------------
-- Preview
-------------------------------------------------------------------------------
local PREVIEW_SIZE = 200
local PREVIEW_MAX_RADIUS = 85

local function RefreshPreview()
    if not previewLineFrame then return end
    local db = CCC.db

    local radius = math.min(db.radius, PREVIEW_MAX_RADIUS)
    local thickness = db.thickness
    -- Auto-scale segments for smooth circle, same as ring.lua
    local minForSmooth = math.ceil(PI2 * radius / 10)
    local numSegments = math.max(db.segments, minForSmooth)
    local angleStep = PI2 / numSegments
    local overlap = thickness / (2 * radius)

    for i = 1, numSegments do
        local line = previewLines[i]
        if not line then
            line = previewLineFrame:CreateLine(nil, "ARTWORK")
            previewLines[i] = line
        end
        local a1 = (i - 1) * angleStep - overlap
        local a2 = i * angleStep + overlap
        line:SetStartPoint("CENTER", previewLineFrame, cos(a1) * radius, sin(a1) * radius)
        line:SetEndPoint("CENTER", previewLineFrame, cos(a2) * radius, sin(a2) * radius)
        line:SetThickness(thickness)
        line:SetColorTexture(db.colorR, db.colorG, db.colorB, 1)
        line:Show()
    end

    for i = numSegments + 1, #previewLines do
        previewLines[i]:Hide()
    end

    -- Opacity on the line container, not individual lines
    previewLineFrame:SetAlpha(db.opacity)

    -- Pulse state
    if db.pulse then
        previewElapsed = 0
        previewFrame.pulseActive = true
    else
        previewFrame.pulseActive = false
        previewFrame:SetAlpha(1)
    end
end

local function BuildPreviewCrosshair(frame)
    local size = 8
    local h = frame:CreateLine(nil, "OVERLAY")
    h:SetStartPoint("CENTER", frame, -size, 0)
    h:SetEndPoint("CENTER", frame, size, 0)
    h:SetThickness(1)
    h:SetColorTexture(1, 1, 1, 0.4)

    local v = frame:CreateLine(nil, "OVERLAY")
    v:SetStartPoint("CENTER", frame, 0, -size)
    v:SetEndPoint("CENTER", frame, 0, size)
    v:SetThickness(1)
    v:SetColorTexture(1, 1, 1, 0.4)
end

-------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------
function CCC:InitSettings()
    local canvas = CreateFrame("Frame")
    canvas:Hide()

    local y = -16

    -- Title
    local title = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 20, y)
    title:SetText("CombatCursorCircle")

    local subtitle = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", 20, y - 22)
    subtitle:SetText("Draws a ring around your cursor during combat.")
    subtitle:SetTextColor(0.7, 0.7, 0.7)

    y = -55

    -- Enable
    controls.enabled = CreateSettingsCheckbox(canvas, 20, y, "Enable addon",
        function() return CCC.db.enabled end,
        function(val)
            CCC.db.enabled = val
            if not val then CCC:HideRing() end
        end
    )

    -----------------------------------------------------------------------
    -- Ring section
    -----------------------------------------------------------------------
    y = -90
    CreateSectionHeader(canvas, 20, y, "Ring")
    y = y - 25

    controls.radius = CreateSettingsSlider(canvas, 20, y, "Radius", 10, 200, 1,
        function() return CCC.db.radius end,
        function(val)
            CCC.db.radius = val
            CCC:RebuildRing()
            RefreshPreview()
        end,
        function(v) return string.format("%d px", v) end
    )
    y = y - 42

    controls.thickness = CreateSettingsSlider(canvas, 20, y, "Thickness", 1, 10, 1,
        function() return CCC.db.thickness end,
        function(val)
            CCC.db.thickness = val
            CCC:RebuildRing()
            RefreshPreview()
        end,
        function(v) return string.format("%d px", v) end
    )
    y = y - 42

    controls.opacity = CreateSettingsSlider(canvas, 20, y, "Opacity", 0, 1, 0.05,
        function() return CCC.db.opacity end,
        function(val)
            CCC.db.opacity = val
            CCC:UpdateRingAppearance()
            RefreshPreview()
        end,
        function(v) return string.format("%.0f%%", v * 100) end
    )

    -----------------------------------------------------------------------
    -- Color section
    -----------------------------------------------------------------------
    y = y - 48
    CreateSectionHeader(canvas, 20, y, "Color")
    y = y - 28

    controls.color = CreateColorSwatch(canvas, 20, y, "Ring color  (click to change)",
        function() return CCC.db.colorR, CCC.db.colorG, CCC.db.colorB end,
        function(r, g, b)
            CCC.db.colorR = r
            CCC.db.colorG = g
            CCC.db.colorB = b
            CCC:UpdateRingAppearance()
            RefreshPreview()
        end
    )

    -----------------------------------------------------------------------
    -- Animations section
    -----------------------------------------------------------------------
    y = y - 40
    CreateSectionHeader(canvas, 20, y, "Animations")
    y = y - 25

    controls.fadeIn = CreateSettingsSlider(canvas, 20, y, "Fade In", 0, 2, 0.05,
        function() return CCC.db.fadeIn end,
        function(val)
            CCC.db.fadeIn = val
            CCC:UpdateFadeAnimations()
        end,
        function(v) return string.format("%.2fs", v) end
    )
    y = y - 42

    controls.fadeOut = CreateSettingsSlider(canvas, 20, y, "Fade Out", 0, 2, 0.05,
        function() return CCC.db.fadeOut end,
        function(val)
            CCC.db.fadeOut = val
            CCC:UpdateFadeAnimations()
        end,
        function(v) return string.format("%.2fs", v) end
    )
    y = y - 36

    controls.pulse = CreateSettingsCheckbox(canvas, 20, y, "Pulse animation",
        function() return CCC.db.pulse end,
        function(val)
            CCC.db.pulse = val
            CCC:UpdatePulseAnimation()
            RefreshPreview()
        end
    )
    y = y - 34

    controls.pulseSpeed = CreateSettingsSlider(canvas, 20, y, "Pulse Speed", 0.5, 5, 0.1,
        function() return CCC.db.pulseSpeed end,
        function(val) CCC.db.pulseSpeed = val end,
        function(v) return string.format("%.1f", v) end
    )

    -----------------------------------------------------------------------
    -- Buttons
    -----------------------------------------------------------------------
    y = y - 50

    CreateSettingsButton(canvas, 20, y, "Reset Defaults", 130, function()
        for k, v in pairs(CCC.DEFAULTS) do
            CCC.db[k] = v
        end
        CCC:RebuildRing()
        CCC:UpdateFadeAnimations()
        CCC:UpdatePulseAnimation()
        CCC:RefreshSettingsControls()
        CCC:PrintMessage("Settings restored to defaults.")
    end)

    CreateSettingsButton(canvas, 160, y, "Test Ring (3s)", 130, function()
        CCC:TestRing(3)
    end)

    -----------------------------------------------------------------------
    -- Preview (right side)
    -----------------------------------------------------------------------
    previewLines = {}
    previewElapsed = 0

    CreateSectionHeader(canvas, 390, -55, "Preview")

    local previewBorder = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
    previewBorder:SetPoint("TOPLEFT", 380, -80)
    previewBorder:SetSize(PREVIEW_SIZE + 10, PREVIEW_SIZE + 10)
    previewBorder:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })

    previewFrame = CreateFrame("Frame", nil, previewBorder)
    previewFrame:SetPoint("CENTER")
    previewFrame:SetSize(PREVIEW_SIZE, PREVIEW_SIZE)
    previewFrame:SetClipsChildren(true)
    previewFrame.pulseActive = false

    -- Line container with flattened render layers (overlap without alpha artifacts)
    previewLineFrame = CreateFrame("Frame", nil, previewFrame)
    previewLineFrame:SetAllPoints(previewFrame)
    if previewLineFrame.SetFlattensRenderLayers then
        previewLineFrame:SetFlattensRenderLayers(true)
    end

    -- Pulse animation in preview
    previewFrame:SetScript("OnUpdate", function(self, dt)
        if not self.pulseActive then return end
        previewElapsed = previewElapsed + dt
        local speed = CCC.db.pulseSpeed
        local wave = 0.5 + 0.5 * sin(previewElapsed * speed * PI2)
        local alpha = 0.4 + 0.6 * wave
        self:SetAlpha(alpha)
    end)

    BuildPreviewCrosshair(previewFrame)
    RefreshPreview()

    -- "Cursor" label below preview
    local cursorNote = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cursorNote:SetPoint("TOP", previewBorder, "BOTTOM", 0, -4)
    cursorNote:SetText("+ = cursor position")
    cursorNote:SetTextColor(0.5, 0.5, 0.5)

    -----------------------------------------------------------------------
    -- Refresh controls when the panel is shown (e.g. after slash changes)
    -----------------------------------------------------------------------
    canvas:SetScript("OnShow", function()
        CCC:RefreshSettingsControls()
    end)

    -----------------------------------------------------------------------
    -- Register with Blizzard Settings API
    -----------------------------------------------------------------------
    local category = Settings.RegisterCanvasLayoutCategory(canvas, "CombatCursorCircle")
    Settings.RegisterAddOnCategory(category)
    settingsCategory = category
end

-------------------------------------------------------------------------------
-- Refresh all controls from current db values
-------------------------------------------------------------------------------
function CCC:RefreshSettingsControls()
    for _, ctrl in pairs(controls) do
        if ctrl.Refresh then
            ctrl.Refresh()
        end
    end
    RefreshPreview()
end

-------------------------------------------------------------------------------
-- Open the settings panel
-------------------------------------------------------------------------------
function CCC:OpenSettings()
    if not settingsCategory then return end
    if InCombatLockdown() then
        self:PrintMessage("Cannot open settings in combat.")
        return
    end
    Settings.OpenToCategory(settingsCategory:GetID())
end
