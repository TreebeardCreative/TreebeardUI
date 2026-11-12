local _, private = ...
if (private.__TBUISkip or private.__TreebeardUISkip) then return end
local TBU = (private.__TBUIRuntime or private.__TreebeardUIRuntime) or private

-- Reusable border surfaces. The border, optional canvas, and inset content
-- frame remain separate so consumers can compose each part independently.
local BorderStyles = {}
TBU.BorderStyles = BorderStyles

local WHITE = "Interface\\Buttons\\WHITE8X8"
local TREATMENTS = {
    square = { edgeFile = WHITE, defaultEdgeSize = 1 },
    rounded = { edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", defaultEdgeSize = 16 },
    toast = {
        edgeFile = "Interface\\FriendsFrame\\UI-Toast-Border",
        defaultEdgeSize = 12,
        tileEdge = true,
    },
    nineSlice = { template = "TooltipBorderBackdropTemplate", defaultEdgeSize = 16 },
}

local function ClampOpacity(value, fallback)
    local opacity = tonumber(value)
    if opacity == nil then opacity = fallback or 100 end
    return math.max(0, math.min(100, opacity)) / 100
end

local function NormalizeInsets(value, fallback)
    local insets = { left = fallback, right = fallback, top = fallback, bottom = fallback }
    if type(value) == "number" then
        local amount = math.max(0, value)
        insets.left, insets.right, insets.top, insets.bottom = amount, amount, amount, amount
    elseif type(value) == "table" then
        local horizontal = tonumber(value.horizontal)
        local vertical = tonumber(value.vertical)
        insets.left = math.max(0, tonumber(value.left) or horizontal or fallback)
        insets.right = math.max(0, tonumber(value.right) or horizontal or fallback)
        insets.top = math.max(0, tonumber(value.top) or vertical or fallback)
        insets.bottom = math.max(0, tonumber(value.bottom) or vertical or fallback)
    end
    return insets
end

local function ConfigureBorderLayer(borderFrame, surface, treatment, edgeSize)
    local descriptor = TREATMENTS[treatment]
    borderFrame:ClearAllPoints()
    borderFrame:SetAllPoints(surface)
    borderFrame:SetFrameLevel(surface:GetFrameLevel() + 1)
    borderFrame:EnableMouse(false)
    if descriptor.template then return end

    borderFrame:SetBackdrop({
        edgeFile = descriptor.edgeFile,
        edgeSize = edgeSize,
        tileEdge = descriptor.tileEdge,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
end

local function GetBorderLayer(surface, treatment)
    local layer = surface._tbuBorderLayers[treatment]
    if not layer then
        local descriptor = TREATMENTS[treatment]
        if descriptor.template then
            layer = CreateFrame("Frame", nil, surface, descriptor.template)
        else
            layer = TBU:CreateBackdropFrame("Frame", surface)
        end
        surface._tbuBorderLayers[treatment] = layer
    end
    return layer
end

function BorderStyles:Create(parent, options)
    assert(parent and parent.CreateTexture, "BorderStyles:Create requires a parent frame")
    options = type(options) == "table" and options or {}

    local treatment = TREATMENTS[options.treatment] and options.treatment or "square"
    local descriptor = TREATMENTS[treatment]
    local edgeSize = math.max(1, tonumber(options.edgeSize) or descriptor.defaultEdgeSize)
    local surface = CreateFrame("Frame", nil, parent)
    surface._tbuBorderLayers = {}
    surface._tbuBorderTreatment = treatment
    surface._tbuBorderEdgeSize = edgeSize
    surface._tbuBorderColor = options.borderColor
    surface._tbuBorderOpacity = options.opacity
    surface._tbuContentInsets = NormalizeInsets(options.contentInsets, edgeSize)
    surface._tbuContentInsetsExplicit = options.contentInsets ~= nil
    surface._tbuCanvasColor = options.canvasColor
    surface._tbuCanvasOpacity = options.canvasOpacity

    -- A canvas is opt-in. Supplying nil leaves the surface transparent.
    if options.canvasColor ~= nil then
        surface.canvas = surface:CreateTexture(nil, "BACKGROUND", nil, -8)
        surface.canvas:SetAllPoints(surface)
    end

    surface.content = CreateFrame("Frame", nil, surface)
    surface.content:SetFrameLevel(surface:GetFrameLevel() + 2)

    local function ApplyContentInsets()
        local inset = surface._tbuContentInsets
        surface.content:ClearAllPoints()
        surface.content:SetPoint("TOPLEFT", surface, "TOPLEFT", inset.left, -inset.top)
        surface.content:SetPoint("BOTTOMRIGHT", surface, "BOTTOMRIGHT", -inset.right, inset.bottom)
    end

    local function ActivateBorderLayer()
        for name, layer in pairs(surface._tbuBorderLayers) do
            if name == surface._tbuBorderTreatment then
                layer:Show()
                surface.border = layer
            else
                layer:Hide()
            end
        end
        local layer = GetBorderLayer(surface, surface._tbuBorderTreatment)
        ConfigureBorderLayer(layer, surface, surface._tbuBorderTreatment, surface._tbuBorderEdgeSize)
        layer:Show()
        surface.border = layer
    end

    function surface:GetContentInsets()
        local inset = self._tbuContentInsets
        return inset.left, inset.right, inset.top, inset.bottom
    end

    function surface:SetContentInsets(insets)
        self._tbuContentInsets = NormalizeInsets(insets, self._tbuBorderEdgeSize)
        self._tbuContentInsetsExplicit = true
        ApplyContentInsets()
        return true
    end

    function surface:SetBorderTreatment(nextTreatment, nextEdgeSize)
        if not TREATMENTS[nextTreatment] then return false end
        local nextDescriptor = TREATMENTS[nextTreatment]
        self._tbuBorderTreatment = nextTreatment
        self._tbuBorderEdgeSize = math.max(1, tonumber(nextEdgeSize) or nextDescriptor.defaultEdgeSize)
        if not self._tbuContentInsetsExplicit then
            self._tbuContentInsets = NormalizeInsets(nil, self._tbuBorderEdgeSize)
            ApplyContentInsets()
        end
        ActivateBorderLayer()
        self:RefreshBorderStyle()
        return true
    end

    function surface:SetBorderColor(color, opacity)
        self._tbuBorderColor = color
        self._tbuBorderOpacity = opacity
        self:RefreshBorderStyle()
        return true
    end

    function surface:SetCanvasColor(color, opacity)
        self._tbuCanvasColor = color
        self._tbuCanvasOpacity = opacity
        if color ~= nil and not self.canvas then
            self.canvas = self:CreateTexture(nil, "BACKGROUND", nil, -8)
            self.canvas:SetAllPoints(self)
        elseif color == nil and self.canvas then
            self.canvas:Hide()
        elseif self.canvas then
            self.canvas:Show()
        end
        self:RefreshBorderStyle()
        return true
    end

    function surface:RefreshBorderStyle()
        local styles = TBU.WindowStyles
        local fallback = styles:GetWindowBorderColor(self)
        local borderColor = self._tbuBorderColor ~= nil
            and styles:ResolveColor(self._tbuBorderColor, self, fallback)
            or fallback
        local alpha = (borderColor[4] or 1) * ClampOpacity(self._tbuBorderOpacity, 100)
        local border = self.border
        if border.SetBackdropBorderColor then
            border:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], alpha)
        end
        if border.NineSlice and border.NineSlice.SetBorderColor then
            border.NineSlice:SetBorderColor(borderColor[1], borderColor[2], borderColor[3], alpha)
        end

        if self.canvas and self._tbuCanvasColor ~= nil then
            local canvas = styles:ResolveColor(self._tbuCanvasColor, self, { 0, 0, 0, 0 })
            local canvasAlpha = (canvas[4] or 1) * ClampOpacity(self._tbuCanvasOpacity, 100)
            self.canvas:SetVertexColor(canvas[1], canvas[2], canvas[3], canvasAlpha)
        end
    end

    ActivateBorderLayer()
    ApplyContentInsets()
    TBU.WindowStyles:RegisterVisual(surface, function(target)
        target:RefreshBorderStyle()
    end)
    surface:RefreshBorderStyle()
    return surface
end
