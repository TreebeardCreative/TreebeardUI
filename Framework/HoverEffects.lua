-- Shared TreebeardUI hover visuals. Consumers provide appearance choices;
-- TreebeardUI owns the hover lifecycle and texture sizing.
local _, private = ...
if (private.__TBUISkip or private.__TreebeardUISkip) then return end
local TBU = (private.__TBUIRuntime or private.__TreebeardUIRuntime) or private

local HoverEffects = {}
HoverEffects.__index = HoverEffects

local function Clamp(value, minimum, maximum, fallback)
    value = tonumber(value)
    if value == nil then value = fallback end
    return math.max(minimum, math.min(maximum, value))
end

local function Normalize(options)
    if type(options) ~= "table" or type(options.fill) ~= "table" then return nil end
    local fill = options.fill
    if type(fill.texture) ~= "string" and type(fill.atlas) ~= "string" then return nil end
    local line = options.line
    if line ~= nil and (type(line) ~= "table" or type(line.texture) ~= "string") then return nil end

    local tint = options.tint
    local red, green, blue = 1, 1, 1
    if type(tint) == "table" then
        red = Clamp(tint[1], 0, 1, 1)
        green = Clamp(tint[2], 0, 1, 1)
        blue = Clamp(tint[3], 0, 1, 1)
    end

    return {
        fill = fill,
        line = line,
        tint = { red, green, blue },
        fillOpacity = Clamp(options.fillOpacity, 0, 1, 1),
        lineOpacity = Clamp(line and line.opacity or options.lineOpacity, 0, 1, 1),
        fillBlendMode = options.fillBlendMode or "BLEND",
        lineBlendMode = options.lineBlendMode or "BLEND",
        sizeScale = Clamp(options.sizeScale, 0.01, 20, 1),
        fillWidthScale = Clamp(options.fillWidthScale, 0.01, 20, 1),
        lineWidthScale = Clamp(options.lineWidthScale, 0.01, 20, 1),
        fillHeightScale = options.fillHeightScale and Clamp(options.fillHeightScale, 0.01, 20, 1) or nil,
        verticalPadding = Clamp(options.verticalPadding, 0, 10000, 0),
        fillGap = Clamp(options.fillGap, 0, 10000, 0),
    }
end

local function SetFillTexture(texture, fill, blendMode)
    local appliedAtlas = false
    if type(fill.atlas) == "string" and texture.SetAtlas then
        appliedAtlas = pcall(texture.SetAtlas, texture, fill.atlas, true)
    end
    if not appliedAtlas then
        texture:SetTexture(fill.texture or fill.fallback)
    end
    texture:SetBlendMode(fill.blendMode or blendMode)
end

function HoverEffects:Attach(frame, options)
    if not frame or type(frame.CreateTexture) ~= "function" or type(frame.HookScript) ~= "function" then
        return nil, "frame must support textures and HookScript"
    end
    local normalized = Normalize(options)
    if not normalized then return nil, "fill texture configuration is required" end

    local fill = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
    local line = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    fill:SetDrawLayer("BACKGROUND", 0)
    line:SetDrawLayer("BACKGROUND", 1)
    fill:Hide()
    line:Hide()

    local effect = setmetatable({
        frame = frame,
        fillTexture = fill,
        lineTexture = line,
        options = normalized,
        enabled = true,
        hovering = false,
    }, HoverEffects)

    function effect:RefreshBounds()
        if not self.enabled then return end
        local config = self.options
        local width = math.max(1, self.frame:GetWidth() or 0)
        local height = math.max(1, self.frame:GetHeight() or 0)
        local scale = config.sizeScale
        local lineHeight = (height + config.verticalPadding * 2) * scale
        local fillHeight = config.fillHeightScale
            and height * config.fillHeightScale * scale
            or ((height + config.verticalPadding * 2) * 0.5 - config.fillGap) * scale

        self.fillTexture:ClearAllPoints()
        self.fillTexture:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
        self.fillTexture:SetSize(width * config.fillWidthScale * scale, math.max(1, fillHeight))
        if config.line then
            self.lineTexture:ClearAllPoints()
            self.lineTexture:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
            self.lineTexture:SetSize(width * config.lineWidthScale * scale, math.max(1, lineHeight))
        end
    end

    function effect:SetOptions(nextOptions)
        local nextConfig = Normalize(nextOptions)
        if not nextConfig then return false end
        self.options = nextConfig
        local config = self.options
        SetFillTexture(self.fillTexture, config.fill, config.fillBlendMode)
        self.fillTexture:SetAlpha(config.fillOpacity)
        self.fillTexture:SetVertexColor(unpack(config.tint))
        if config.line then
            self.lineTexture:SetTexture(config.line.texture)
            self.lineTexture:SetBlendMode(config.line.blendMode or config.lineBlendMode)
            self.lineTexture:SetAlpha(config.lineOpacity)
            self.lineTexture:SetVertexColor(unpack(config.tint))
        else
            self.lineTexture:Hide()
        end
        self:RefreshBounds()
        self:RefreshVisibility()
        return true
    end

    function effect:RefreshVisibility()
        local visible = self.enabled and self.hovering and self.frame:IsShown()
        if visible then self.fillTexture:Show() else self.fillTexture:Hide() end
        if visible and self.options.line then self.lineTexture:Show() else self.lineTexture:Hide() end
    end

    function effect:SetEnabled(enabled)
        self.enabled = enabled ~= false
        self:RefreshVisibility()
    end

    local function UpdateHover(self, hovering)
        effect.hovering = hovering and true or false
        effect:RefreshVisibility()
    end
    frame:HookScript("OnEnter", function(self) UpdateHover(self, true) end)
    frame:HookScript("OnLeave", function(self) UpdateHover(self, false) end)
    frame:HookScript("OnHide", function(self)
        effect.hovering = false
        effect:RefreshVisibility()
    end)
    frame:HookScript("OnShow", function(self)
        effect.hovering = self.IsMouseOver and self:IsMouseOver() or false
        effect:RefreshVisibility()
    end)
    frame:HookScript("OnSizeChanged", function() effect:RefreshBounds() end)

    effect:SetOptions(options)
    return effect
end

TBU.HoverEffects = HoverEffects
