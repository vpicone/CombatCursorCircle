local ADDON_NAME, CCC = ...

local PI2 = math.pi * 2
local cos, sin = math.cos, math.sin
local GetCursorPosition = GetCursorPosition

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------
local ringFrame       -- main frame (alpha used for fade/pulse animations)
local lineFrame       -- child frame holding lines (alpha = configured opacity)
local lines = {}      -- line texture pool
local activeSegments = 0
local isShowing = false
local testTimer = nil

-- Animation references
local fadeInGroup, fadeOutGroup
local pulseFrame, pulseElapsed

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

-- Auto-scale segment count so each segment is at most ~10px long
local function CalcEffectiveSegments(radius, userSegments)
    local minForSmooth = math.ceil(PI2 * radius / 10)
    return math.max(userSegments, minForSmooth)
end

-------------------------------------------------------------------------------
-- Ring initialisation
-------------------------------------------------------------------------------
function CCC:InitRing()
    ringFrame = CreateFrame("Frame", "CombatCursorCircleFrame", UIParent)
    ringFrame:SetFrameStrata("HIGH")
    ringFrame:SetSize(1, 1)
    ringFrame:Hide()

    -- Line container: flattened render layers means overlapping segments
    -- composite at full opacity first, then the frame alpha applies once.
    -- This lets us use overlap to close joint gaps without double-alpha artifacts.
    lineFrame = CreateFrame("Frame", nil, ringFrame)
    lineFrame:SetAllPoints(ringFrame)
    if lineFrame.SetFlattensRenderLayers then
        lineFrame:SetFlattensRenderLayers(true)
    end

    -- Cursor tracking (only runs while frame is shown)
    ringFrame:SetScript("OnUpdate", function()
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        ringFrame:ClearAllPoints()
        ringFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end)

    self:BuildLines()
    self:SetupAnimations()
end

-------------------------------------------------------------------------------
-- Line geometry
-------------------------------------------------------------------------------
function CCC:BuildLines()
    local db = self.db
    local radius = db.radius
    local thickness = db.thickness
    local numSegments = CalcEffectiveSegments(radius, db.segments)
    local angleStep = PI2 / numSegments
    -- Extend each segment slightly so adjacent segments overlap at joints
    local overlap = thickness / (2 * radius)

    for i = 1, numSegments do
        local line = lines[i]
        if not line then
            line = lineFrame:CreateLine(nil, "OVERLAY")
            lines[i] = line
        end

        local a1 = (i - 1) * angleStep - overlap
        local a2 = i * angleStep + overlap
        line:SetStartPoint("CENTER", lineFrame, cos(a1) * radius, sin(a1) * radius)
        line:SetEndPoint("CENTER", lineFrame, cos(a2) * radius, sin(a2) * radius)
        line:SetThickness(thickness)
        -- Full alpha on the texture; opacity is controlled by lineFrame
        line:SetColorTexture(db.colorR, db.colorG, db.colorB, 1)
        line:Show()
    end

    -- Hide excess lines from previous higher segment count
    for i = numSegments + 1, #lines do
        lines[i]:Hide()
    end

    activeSegments = numSegments
    lineFrame:SetAlpha(db.opacity)
end

-------------------------------------------------------------------------------
-- Appearance (color/opacity only, no geometry rebuild)
-------------------------------------------------------------------------------
function CCC:UpdateRingAppearance()
    local db = self.db
    for i = 1, activeSegments do
        local line = lines[i]
        if line then
            line:SetColorTexture(db.colorR, db.colorG, db.colorB, 1)
        end
    end
    lineFrame:SetAlpha(db.opacity)
end

-------------------------------------------------------------------------------
-- Full rebuild (geometry + appearance)
-------------------------------------------------------------------------------
function CCC:RebuildRing()
    if not ringFrame then return end
    self:BuildLines()
end

-------------------------------------------------------------------------------
-- Animations
-------------------------------------------------------------------------------
function CCC:SetupAnimations()
    -- Fade-in
    fadeInGroup = ringFrame:CreateAnimationGroup()
    local fadeInAnim = fadeInGroup:CreateAnimation("Alpha")
    fadeInAnim:SetFromAlpha(0)
    fadeInAnim:SetToAlpha(1)
    fadeInAnim:SetDuration(self.db.fadeIn)
    fadeInAnim:SetSmoothing("OUT")
    fadeInGroup:SetScript("OnPlay", function()
        ringFrame:SetAlpha(0)
    end)
    fadeInGroup:SetScript("OnFinished", function()
        ringFrame:SetAlpha(1)
    end)

    -- Fade-out
    fadeOutGroup = ringFrame:CreateAnimationGroup()
    local fadeOutAnim = fadeOutGroup:CreateAnimation("Alpha")
    fadeOutAnim:SetFromAlpha(1)
    fadeOutAnim:SetToAlpha(0)
    fadeOutAnim:SetDuration(self.db.fadeOut)
    fadeOutAnim:SetSmoothing("IN")
    fadeOutGroup:SetScript("OnFinished", function()
        ringFrame:SetAlpha(1)
        ringFrame:Hide()
        isShowing = false
    end)

    -- Pulse (child frame with its own OnUpdate)
    pulseFrame = CreateFrame("Frame", nil, ringFrame)
    pulseFrame:Hide()
    pulseElapsed = 0
    pulseFrame:SetScript("OnUpdate", function(_, dt)
        if not isShowing then return end
        pulseElapsed = pulseElapsed + dt
        local speed = CCC.db.pulseSpeed
        local wave = 0.5 + 0.5 * sin(pulseElapsed * speed * PI2)
        local alpha = 0.4 + 0.6 * wave
        ringFrame:SetAlpha(alpha)
    end)
end

function CCC:UpdateFadeAnimations()
    if not fadeInGroup then return end
    local children

    children = { fadeInGroup:GetAnimations() }
    if children[1] then
        children[1]:SetDuration(self.db.fadeIn)
    end

    children = { fadeOutGroup:GetAnimations() }
    if children[1] then
        children[1]:SetDuration(self.db.fadeOut)
    end
end

function CCC:UpdatePulseAnimation()
    if not pulseFrame then return end
    if self.db.pulse and isShowing then
        pulseElapsed = 0
        pulseFrame:Show()
    else
        pulseFrame:Hide()
        if isShowing and ringFrame then
            ringFrame:SetAlpha(1)
        end
    end
end

-------------------------------------------------------------------------------
-- Show / Hide with animation orchestration
-------------------------------------------------------------------------------
function CCC:ShowRing()
    if not ringFrame then return end

    -- Cancel any pending test timer
    if testTimer then
        testTimer:Cancel()
        testTimer = nil
    end

    -- Stop fade-out if it's playing
    if fadeOutGroup:IsPlaying() then
        fadeOutGroup:Stop()
    end

    ringFrame:Show()
    isShowing = true

    if self.db.fadeIn > 0 then
        fadeInGroup:Play()
    else
        ringFrame:SetAlpha(1)
    end

    -- Start pulse if enabled
    if self.db.pulse then
        pulseElapsed = 0
        pulseFrame:Show()
    end
end

function CCC:HideRing()
    if not ringFrame or not isShowing then return end

    -- Stop pulse
    pulseFrame:Hide()

    -- Stop fade-in if still playing
    if fadeInGroup:IsPlaying() then
        fadeInGroup:Stop()
    end

    if self.db.fadeOut > 0 then
        ringFrame:SetAlpha(1)
        fadeOutGroup:Play()
    else
        ringFrame:Hide()
        isShowing = false
    end
end

-------------------------------------------------------------------------------
-- Test mode
-------------------------------------------------------------------------------
function CCC:TestRing(duration)
    if not ringFrame then return end
    duration = duration or 3

    -- If in actual combat, skip test
    if InCombatLockdown() and isShowing then
        self:PrintMessage("Already in combat!")
        return
    end

    -- Cancel previous test timer
    if testTimer then
        testTimer:Cancel()
        testTimer = nil
    end

    self:ShowRing()
    self:PrintMessage(string.format("Test mode: showing ring for %d seconds.", duration))

    testTimer = C_Timer.NewTimer(duration, function()
        testTimer = nil
        -- Don't hide if real combat started during test
        if not InCombatLockdown() then
            CCC:HideRing()
        end
    end)
end
