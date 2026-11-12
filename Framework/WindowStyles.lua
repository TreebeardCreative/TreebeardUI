-- Shared TreebeardUI framework; no knowledge of any consuming addon.
local _, private = ...
if (private.__TBUISkip or private.__TreebeardUISkip) then return end
local TBU = (private.__TBUIRuntime or private.__TreebeardUIRuntime) or private

-- Unclassified rendered parts use a conspicuous fallback so missing style
-- assignments are obvious during consumer testing. Intentional black remains
-- available as a separate ColorFactory token.
local Styles = {}
TBU.WindowStyles = Styles

local WHITE = "Interface\\Buttons\\WHITE8X8"
Styles.DefaultPreset = "Brushfire"
Styles.ActivePreset = "Brushfire"
Styles.ConsumerPresets = {}
Styles.RenderOwner = nil
Styles.Presets = {}

-- Copy helpers keep a consumer's color overrides independent from other
-- presets while preserving the shared geometry defaults below.
local function ClonePreset(base)
    local out = {}
    for k, v in pairs(base) do
        if type(v) == "table" then
            local cloned = {}
            for i, item in pairs(v) do cloned[i] = item end
            out[k] = cloned
        else
            out[k] = v
        end
    end
    return out
end

local defaultAllEverythingTestVariable = {0, 1, 0, 1}

function Styles:RegisterPreset(name, allEverythingTestVariable, geometryPreset)
    if type(name) ~= "string" or name == "" then return nil end
    local geometry = self.Presets[geometryPreset or self.DefaultPreset] or self.GeometryDefaults
    if not geometry then return nil end
    local preset = ClonePreset(geometry)
    local value = type(allEverythingTestVariable) == "table" and allEverythingTestVariable or defaultAllEverythingTestVariable
    preset.allEverythingTestVariable = {value[1], value[2], value[3], value[4] or 1}
    preset.allBordersTestVariable = {value[1], value[2], value[3], value[4] or 1}
    preset.allTextTestVariable = {value[1], value[2], value[3], value[4] or 1}
    -- Navigation color relationships are framework defaults for every style.
    -- Each style resolves these tokens from its own ColorFactory families and
    -- can override a field when it intentionally needs different behavior.
    preset.mainNavigationButtonSelectedBorderColor = preset.mainNavigationButtonSelectedBorderColor or "interactionAccent_4"
    preset.mainNavigationButtonCanvasColor = preset.mainNavigationButtonCanvasColor or "canvas_4"
    preset.mainNavigationButtonInactiveCanvasColor = preset.mainNavigationButtonInactiveCanvasColor or "canvas_2"
    preset.mainNavigationButtonInactiveHoverCanvasColor = preset.mainNavigationButtonInactiveHoverCanvasColor or "canvas_3"
    preset.actionButtonCanvasColor = preset.actionButtonCanvasColor or "canvas_2"
    preset.controlInputCanvasColor = preset.controlInputCanvasColor or "canvas_2"
    preset.sectionSurfaceColor = preset.sectionSurfaceColor or "canvas_2"
    preset.sectionBorderColor = preset.sectionBorderColor or "neutralAccent_4"
    preset.frameHeaderActiveCanvasColor = preset.frameHeaderActiveCanvasColor or "canvas_2"
    preset.recessedInputShadowColor = preset.recessedInputShadowColor or "black"
    preset.controlThumbIdleColor = preset.controlThumbIdleColor or "interactionAccent_1"
    preset.scrollbarThumbIdleColor = preset.scrollbarThumbIdleColor or "interactionAccent_1"
    preset.resizeGripIdleColor = preset.resizeGripIdleColor or "neutralAccent_3"
    preset.actionButtonPressedCanvasColor = preset.actionButtonPressedCanvasColor or "black"
    preset.actionButtonHoverBorderColor = preset.actionButtonHoverBorderColor or "interactionAccent_4"
    preset.textInputFocusBorderColor = preset.textInputFocusBorderColor or "interactionAccent_2"
    preset.subpageUnderlineColor = preset.subpageUnderlineColor or "neutralAccent_4"
    preset.subpageSelectedUnderlineColor = preset.subpageSelectedUnderlineColor or "interactionAccent_4"
    preset.subpageTextColor = preset.subpageTextColor or "neutralAccent_4"
    preset.subpageHoverTextColor = preset.subpageHoverTextColor or "interactionAccent_2"
    self.Presets[name] = preset
    return preset
end

-- Shared geometry defaults are not a selectable color theme.
Styles.GeometryDefaults = {
    edgeSize = 1,
    titleHeight = 29,
    -- Window-title content is independently inset from its outside border.
    -- Consumers can override these in frameHeader.padding/controlGap.
    frameHeaderPadding = { left=13, right=8, top=2, bottom=2 },
    frameHeaderControlGap = 5,
    iconButtonHitWidth = 25,
    iconButtonHitHeight = 24,
    iconButtonVisualSize = 20,
    iconButtonGlyphSize = 18,
    -- Empty pane headers keep only this compact structural minimum; populated
    -- headers measure their text or layout row plus the configured insets.
    paneHeaderMinHeight = 15,
    -- Retained as the explicit fixed-height fallback when auto sizing is off.
    paneHeaderHeight = 62,
    -- Structural outer-width floor for empty or populated panes in content-sized windows.
    paneMinimumWidth = 15,
    paneFooterHeight = 1,
    paneFooterPaddingX = 12,
    paneFooterPaddingY = 6,
    paneGutter = 12,
    paneBorderInset = 0,
    sectionCanvasLeft = 10,
    sectionCanvasRight = 10,
    sectionCanvasTop = 10,
    sectionCanvasBottom = 10,
    pageTitleTop = 8,
    pageDescriptionTop = 32,
    navigationWidth = 155,
    navigationGap = 10,
    navigationItemInset = 8,
    navigationItemGap = 6,
    navigationItemHeight = 28,
    mainNavigationBottomBorderHeight = 3,
    mainNavigationSelectedBottomBorderHeight = 6,
    subpageIndicatorHeight = 2,
    paneHeaderPaddingX = 12,
    paneHeaderPaddingY = 10,
    paneHeaderTextGap = 4,
    contentSectionWidth = 540,
    sectionColumnGap = 6,
    settingsSize = {821, 620, 821, 620},
    debugSize = {710, 395},
    edgeInside = 6,
    edgeOutside = 5,
}

-- Brushfire is the first authored palette. Missing categories use the green
-- diagnostic fallback; assigned components resolve through the named families.
local brushfireStyle = Styles:RegisterPreset("Brushfire", defaultAllEverythingTestVariable)
brushfireStyle.colorFactoryFields = {"canvas", "neutralAccent", "interactionAccent", "baseText"}
brushfireStyle.colorFactoryBases = {
    canvas = "#0d0d0d",
    neutralAccent = "#595959",
    interactionAccent = "#660000",
    baseText = "#ffffff",
}
local factoryColors, factoryFamilies = TBU.ColorFactory.BuildFamilies(brushfireStyle.colorFactoryBases)
brushfireStyle.colorFactoryColors = factoryColors
brushfireStyle.colorFactoryFamilies = factoryFamilies
-- Shared option highlights, separators, and input surfaces resolve through
-- named palette tokens in each authored preset.
brushfireStyle.controlOptionHighlightColor = "white"
brushfireStyle.controlInputCanvasColor = "canvas_2"
brushfireStyle.separatorColor = "neutralAccent_base"

-- Brushfire components map explicitly to generated or base palette tokens.
-- These explicit mappings retain the current Brushfire component treatment.
brushfireStyle.mainCanvasColor = TBU.ColorFactory.ToHex(brushfireStyle.colorFactoryColors.canvas_1)
brushfireStyle.windowBorderColor = "neutralAccent_4"
brushfireStyle.controlBorderColor = "neutralAccent_4"
brushfireStyle.controlContainerColor = "neutralAccent_4"
brushfireStyle.mainNavigationButtonCanvasColor = "canvas_4"
brushfireStyle.mainNavigationButtonInactiveCanvasColor = "canvas_2"
brushfireStyle.mainNavigationButtonInactiveHoverCanvasColor = "canvas_3"
brushfireStyle.mainNavigationButtonBorderColor = "neutralAccent_4"
-- The existing red indicator is lifted two family levels from its old base.
brushfireStyle.controlIndicatorColor = TBU.ColorFactory.ToHex(brushfireStyle.colorFactoryColors.interactionAccent_3)
brushfireStyle.windowHighlightColor = TBU.ColorFactory.ToHex(brushfireStyle.colorFactoryColors.interactionAccent_2)
brushfireStyle.windowInteractionColor = TBU.ColorFactory.ToHex(brushfireStyle.colorFactoryColors.interactionAccent_4)

-- Text slots point directly to generated palette tokens. Text roles select a
-- slot independently, so consumers can recolor a text category without
-- creating another copy of a palette color. The main slot preserves today's
-- primary controls remain white while supporting notes use neutral accent;
-- interaction-accent text remains available for intentionally emphasized text.
local function ConfigureTextPalette(style)
    style.textMainColor = "baseText_1"
    style.textNeutralAccentColor = "neutralAccent_4"
    style.textInteractionAccentColor = "interactionAccent_4"
    style.textColorRoleMap = {
        primary = "textMainColor",
        value = "textMainColor",
        header = "textMainColor",
        notes = "textNeutralAccentColor",
    }
end
ConfigureTextPalette(brushfireStyle)

-- Embersteel uses the same component-to-token relationships as Brushfire,
-- with its own independently generated palette families.
local embersteelStyle = Styles:RegisterPreset("Embersteel", defaultAllEverythingTestVariable, "Brushfire")
embersteelStyle.colorFactoryFields = {"canvas", "neutralAccent", "interactionAccent", "baseText"}
embersteelStyle.colorFactoryBases = {
    canvas = "#0d0d0d",
    neutralAccent = "#1e3b62",
    interactionAccent = "#995c00",
    baseText = "#cccccc",
}
local embersteelColors, embersteelFamilies = TBU.ColorFactory.BuildFamilies(embersteelStyle.colorFactoryBases)
embersteelStyle.colorFactoryColors = embersteelColors
embersteelStyle.colorFactoryFamilies = embersteelFamilies
embersteelStyle.mainCanvasColor = TBU.ColorFactory.ToHex(embersteelColors.canvas_1)
embersteelStyle.windowBorderColor = "neutralAccent_4"
embersteelStyle.controlBorderColor = "neutralAccent_4"
embersteelStyle.controlContainerColor = "neutralAccent_4"
embersteelStyle.mainNavigationButtonBorderColor = "neutralAccent_4"
embersteelStyle.subpageUnderlineColor = "neutralAccent_4"
embersteelStyle.controlIndicatorColor = "interactionAccent_3"
embersteelStyle.windowHighlightColor = "interactionAccent_2"
embersteelStyle.windowInteractionColor = "interactionAccent_4"
embersteelStyle.controlOptionHighlightColor = "white"
embersteelStyle.controlInputCanvasColor = "canvas_2"
embersteelStyle.separatorColor = "neutralAccent_base"
ConfigureTextPalette(embersteelStyle)

-- Warm Warcraft is an independent palette using the same component links as
-- Brushfire and Embersteel. Its dark warm surfaces, bronze neutral family,
-- deep red interaction family, and warm white text are an editable starting
-- point inspired by WoW's interface palette, not copied UI artwork/colors.
local warmWarcraftStyle = Styles:RegisterPreset("Warm Warcraft", defaultAllEverythingTestVariable, "Brushfire")
warmWarcraftStyle.colorFactoryFields = {"canvas", "neutralAccent", "interactionAccent", "baseText"}
warmWarcraftStyle.colorFactoryBases = {
    canvas = "#191511",
    neutralAccent = "#806443",
    interactionAccent = "#660000",
    baseText = "#fff2cc",
}
local warmWarcraftColors, warmWarcraftFamilies = TBU.ColorFactory.BuildFamilies(warmWarcraftStyle.colorFactoryBases)
warmWarcraftStyle.colorFactoryColors = warmWarcraftColors
warmWarcraftStyle.colorFactoryFamilies = warmWarcraftFamilies
warmWarcraftStyle.mainCanvasColor = TBU.ColorFactory.ToHex(warmWarcraftColors.canvas_1)
warmWarcraftStyle.windowBorderColor = "neutralAccent_4"
warmWarcraftStyle.controlBorderColor = "neutralAccent_4"
warmWarcraftStyle.controlContainerColor = "neutralAccent_4"
warmWarcraftStyle.mainNavigationButtonBorderColor = "neutralAccent_4"
warmWarcraftStyle.subpageUnderlineColor = "neutralAccent_4"
warmWarcraftStyle.controlIndicatorColor = "interactionAccent_3"
warmWarcraftStyle.windowHighlightColor = "interactionAccent_2"
warmWarcraftStyle.windowInteractionColor = "interactionAccent_4"
warmWarcraftStyle.controlOptionHighlightColor = "white"
warmWarcraftStyle.controlInputCanvasColor = "canvas_2"
warmWarcraftStyle.separatorColor = "neutralAccent_base"
ConfigureTextPalette(warmWarcraftStyle)

local function CopyRGBAColor(value)
    if type(value) ~= "table" then return nil end
    local red, green, blue = tonumber(value[1]), tonumber(value[2]), tonumber(value[3])
    if not red or not green or not blue then return nil end
    return {red, green, blue, tonumber(value[4]) or 1}
end

local function ParseHexColor(value, fallback)
    if type(value) == "string" then
        local hex = value:gsub("^#", "")
        if #hex == 6 and hex:match("^%x+$") then
            return {
                tonumber(hex:sub(1, 2), 16) / 255,
                tonumber(hex:sub(3, 4), 16) / 255,
                tonumber(hex:sub(5, 6), 16) / 255,
                1,
            }
        end
    end
    return CopyRGBAColor(fallback) or fallback
end

local TEXT_COLOR_SLOTS = {
    textMainColor = true,
    textNeutralAccentColor = true,
    textInteractionAccentColor = true,
}

local function ResolveStyleColor(style, value, fallback)
    local normalizedFallback = CopyRGBAColor(fallback) or fallback
    if type(value) == "table" then
        return CopyRGBAColor(value) or normalizedFallback
    end
    if type(value) == "string" then
        local token = style.colorFactoryColors and style.colorFactoryColors[value]
        if token ~= nil then
            if type(token) == "table" then
                return CopyRGBAColor(token) or normalizedFallback
            end
            return ParseHexColor(token, normalizedFallback)
        end
    end
    return ParseHexColor(value, normalizedFallback)
end

-- A semantic text role maps to one of the style's named text slots. The slot
-- then resolves its ColorFactory token at use time. Unmapped roles retain the
-- all-text test fallback for newly added or uncategorized text.
function Styles:GetTextColor(role, frame)
    local style = frame and self:GetForFrame(frame) or self:Get()
    local slot = TEXT_COLOR_SLOTS[role] and role
        or (style.textColorRoleMap and style.textColorRoleMap[role])
    if slot and TEXT_COLOR_SLOTS[slot] then
        local color = ResolveStyleColor(style, style[slot])
        if color then return color end
    end
    return ResolveStyleColor(style, style.allTextTestVariable, style.allEverythingTestVariable)
end

-- Each consumer opts into its own preset. No consumer state is stored here;
-- callers supply the owner ID and persist the choice in their SavedVariables.
-- Unregistered consumers see the framework default. Consumers can offer any
-- built-in preset and register their own in Presets.
local function FindOwner(frame)
    local current = frame
    for _ = 1, 48 do
        if not current then return nil end
        if current.storageOwner then return current.storageOwner end
        if not current.GetParent then return nil end
        current = current:GetParent()
    end
end
local visualRefresh = setmetatable({}, {__mode="k"})
function Styles:RegisterVisual(frame, refresh)
    if frame and type(refresh) == "function" then visualRefresh[frame] = refresh end
end
function Styles:GetConsumerPreset(owner)
    return self.ConsumerPresets[owner] or self.DefaultPreset
end
function Styles:Get(name)
    local active = name or (self.RenderOwner and self:GetConsumerPreset(self.RenderOwner)) or self.ActivePreset
    return self.Presets[active] or self.Presets[self.DefaultPreset]
end
function Styles:GetForFrame(frame)
    local owner = FindOwner(frame)
    if owner then return self:Get(self:GetConsumerPreset(owner)) end
    return self:Get()
end
function Styles:GetBorderColor(frameOrStyle, fallback)
    local style = type(frameOrStyle) == "table" and frameOrStyle.allEverythingTestVariable
        and frameOrStyle or self:GetForFrame(frameOrStyle)
    if not style then style = self:Get() end
    return ResolveStyleColor(style, style.allBordersTestVariable, fallback or style.allEverythingTestVariable)
end
local function GetNamedBorderColor(styles, frameOrStyle, field, fallback)
    local style = type(frameOrStyle) == "table" and frameOrStyle.allEverythingTestVariable
        and frameOrStyle or styles:GetForFrame(frameOrStyle)
    if not style then style = styles:Get() end
    return ResolveStyleColor(style, style[field], fallback) or styles:GetBorderColor(style)
end
function Styles:GetWindowBorderColor(frameOrStyle, fallback)
    return GetNamedBorderColor(self, frameOrStyle, "windowBorderColor", fallback)
end
function Styles:GetWindowHighlightColor(frameOrStyle, fallback)
    return GetNamedBorderColor(self, frameOrStyle, "windowHighlightColor", fallback)
        or self:GetWindowBorderColor(frameOrStyle, fallback)
end
function Styles:GetWindowInteractionColor(frameOrStyle, fallback)
    return GetNamedBorderColor(self, frameOrStyle, "windowInteractionColor", fallback)
        or self:GetWindowBorderColor(frameOrStyle, fallback)
end
function Styles:GetControlBorderColor(frameOrStyle, fallback)
    return GetNamedBorderColor(self, frameOrStyle, "controlBorderColor", fallback)
end
function Styles:GetTextInputFocusBorderColor(frameOrStyle, fallback)
    local style = type(frameOrStyle) == "table" and frameOrStyle.allEverythingTestVariable
        and frameOrStyle or self:GetForFrame(frameOrStyle)
    if not style then style = self:Get() end
    return ResolveStyleColor(style, style.textInputFocusBorderColor, fallback)
        or self:GetControlBorderColor(style, fallback)
end
function Styles:GetMainNavigationBorderColor(frameOrStyle, fallback)
    return self:GetMainNavigationButtonBorderColor(frameOrStyle, fallback)
end
function Styles:GetMainNavigationButtonBorderColor(frameOrStyle, fallback)
    local style = type(frameOrStyle) == "table" and frameOrStyle.allEverythingTestVariable
        and frameOrStyle or self:GetForFrame(frameOrStyle)
    if not style then style = self:Get() end
    -- Accept the previous field name as a fallback for existing consumer styles.
    return ResolveStyleColor(style, style.mainNavigationButtonBorderColor or style.mainNavigationBorderColor, fallback)
        or self:GetBorderColor(style)
end
function Styles:GetMainNavigationButtonSelectedBorderColor(frameOrStyle, fallback)
    local style = type(frameOrStyle) == "table" and frameOrStyle.allEverythingTestVariable
        and frameOrStyle or self:GetForFrame(frameOrStyle)
    if not style then style = self:Get() end
    return ResolveStyleColor(style, style.mainNavigationButtonSelectedBorderColor, fallback)
        or self:GetMainNavigationButtonBorderColor(style, fallback)
end
function Styles:GetMainNavigationButtonCanvasColor(frameOrStyle)
    local style = type(frameOrStyle) == "table" and frameOrStyle.allEverythingTestVariable
        and frameOrStyle or self:GetForFrame(frameOrStyle)
    if not style then style = self:Get() end
    return ResolveStyleColor(style, style.mainNavigationButtonCanvasColor, style.allEverythingTestVariable)
end
function Styles:GetMainNavigationButtonInactiveCanvasColor(frameOrStyle)
    local style = type(frameOrStyle) == "table" and frameOrStyle.allEverythingTestVariable
        and frameOrStyle or self:GetForFrame(frameOrStyle)
    if not style then style = self:Get() end
    -- The inactive shade is intentionally unset until Treebeard chooses it.
    -- Until then, preserve the existing main-navigation canvas appearance.
    return ResolveStyleColor(style, style.mainNavigationButtonInactiveCanvasColor,
        self:GetMainNavigationButtonCanvasColor(style))
end
function Styles:GetMainNavigationButtonInactiveHoverCanvasColor(frameOrStyle)
    local style = type(frameOrStyle) == "table" and frameOrStyle.allEverythingTestVariable
        and frameOrStyle or self:GetForFrame(frameOrStyle)
    if not style then style = self:Get() end
    return ResolveStyleColor(style, style.mainNavigationButtonInactiveHoverCanvasColor,
        self:GetMainNavigationButtonInactiveCanvasColor(style))
end
function Styles:GetActionButtonCanvasColor(frameOrStyle)
    local style = type(frameOrStyle) == "table" and frameOrStyle.allEverythingTestVariable
        and frameOrStyle or self:GetForFrame(frameOrStyle)
    if not style then style = self:Get() end
    return ResolveStyleColor(style, style.actionButtonCanvasColor, style.allEverythingTestVariable)
end
function Styles:GetControlThumbIdleColor(frameOrStyle)
    local style = type(frameOrStyle) == "table" and frameOrStyle.allEverythingTestVariable
        and frameOrStyle or self:GetForFrame(frameOrStyle)
    if not style then style = self:Get() end
    return ResolveStyleColor(style, style.controlThumbIdleColor,
        self:GetActionButtonCanvasColor(style))
end
local function GetControlColor(styles, frameOrStyle, field)
    local style = type(frameOrStyle) == "table" and frameOrStyle.allEverythingTestVariable
        and frameOrStyle or styles:GetForFrame(frameOrStyle)
    if not style then style = styles:Get() end
    return ResolveStyleColor(style, style[field], style.allEverythingTestVariable)
end
function Styles:GetScrollbarTrackColor(frameOrStyle)
    local style = type(frameOrStyle) == "table" and frameOrStyle.allEverythingTestVariable
        and frameOrStyle or self:GetForFrame(frameOrStyle)
    if not style then style = self:Get() end
    return ResolveStyleColor(style, style.scrollbarTrackColor,
        self:GetWindowBorderColor(style))
end
function Styles:GetScrollbarThumbIdleColor(frameOrStyle)
    return GetControlColor(self, frameOrStyle, "scrollbarThumbIdleColor")
end
function Styles:GetResizeGripIdleColor(frameOrStyle)
    local style = type(frameOrStyle) == "table" and frameOrStyle.allEverythingTestVariable
        and frameOrStyle or self:GetForFrame(frameOrStyle)
    if not style then style = self:Get() end
    return ResolveStyleColor(style, style.resizeGripIdleColor,
        self:GetWindowBorderColor(style))
end
function Styles:GetActionButtonPressedCanvasColor(frameOrStyle)
    local style = type(frameOrStyle) == "table" and frameOrStyle.allEverythingTestVariable
        and frameOrStyle or self:GetForFrame(frameOrStyle)
    if not style then style = self:Get() end
    return ResolveStyleColor(style, style.actionButtonPressedCanvasColor, style.allEverythingTestVariable)
end
function Styles:GetActionButtonHoverBorderColor(frameOrStyle)
    local style = type(frameOrStyle) == "table" and frameOrStyle.allEverythingTestVariable
        and frameOrStyle or self:GetForFrame(frameOrStyle)
    if not style then style = self:Get() end
    return ResolveStyleColor(style, style.actionButtonHoverBorderColor,
        self:GetControlBorderColor(style))
end
function Styles:GetSubpageUnderlineColor(frameOrStyle, fallback)
    return GetNamedBorderColor(self, frameOrStyle, "subpageUnderlineColor", fallback)
end
function Styles:GetSubpageSelectedUnderlineColor(frameOrStyle, fallback)
    local style = type(frameOrStyle) == "table" and frameOrStyle.allEverythingTestVariable
        and frameOrStyle or self:GetForFrame(frameOrStyle)
    if not style then style = self:Get() end
    return ResolveStyleColor(style, style.subpageSelectedUnderlineColor)
        or self:GetSubpageUnderlineColor(style, fallback)
end
function Styles:GetSubpageTextColor(frame)
    local style = self:GetForFrame(frame)
    return ResolveStyleColor(style, style.subpageTextColor)
        or self:GetTextColor("primary", frame)
end
function Styles:GetSubpageHoverTextColor(frame)
    local style = self:GetForFrame(frame)
    return ResolveStyleColor(style, style.subpageHoverTextColor)
        or self:GetTextColor("primary", frame)
end
function Styles:GetMainCanvasColor(frameOrStyle)
    local style = type(frameOrStyle) == "table" and frameOrStyle.allEverythingTestVariable
        and frameOrStyle or self:GetForFrame(frameOrStyle)
    if not style then style = self:Get() end
    return ResolveStyleColor(style, style.mainCanvasColor, style.allEverythingTestVariable)
end
function Styles:ResolveColor(value, frameOrStyle, fallback)
    local style = type(frameOrStyle) == "table" and frameOrStyle.allEverythingTestVariable
        and frameOrStyle or self:GetForFrame(frameOrStyle)
    if not style then style = self:Get() end
    return ResolveStyleColor(style, value, fallback)
end
function Styles:GetFrameHeaderActiveCanvasColor(frameOrStyle)
    local style = type(frameOrStyle) == "table" and frameOrStyle.allEverythingTestVariable
        and frameOrStyle or self:GetForFrame(frameOrStyle)
    if not style then style = self:Get() end
    return ResolveStyleColor(style, style.frameHeaderActiveCanvasColor, style.allEverythingTestVariable)
        or self:GetMainCanvasColor(style)
end
function Styles:GetControlContainerColor(frameOrStyle)
    return GetControlColor(self, frameOrStyle, "controlContainerColor")
end
function Styles:GetControlIndicatorColor(frameOrStyle)
    return GetControlColor(self, frameOrStyle, "controlIndicatorColor")
end
function Styles:GetControlOptionHighlightColor(frameOrStyle)
    local style = type(frameOrStyle) == "table" and frameOrStyle.allEverythingTestVariable
        and frameOrStyle or self:GetForFrame(frameOrStyle)
    if not style then style = self:Get() end
    local fallback = ResolveStyleColor(style, style.allEverythingTestVariable, {0, 0, 0, 1})
    return ResolveStyleColor(style, style.controlOptionHighlightColor, fallback)
end
function Styles:GetControlInputCanvasColor(frameOrStyle)
    local style = type(frameOrStyle) == "table" and frameOrStyle.allEverythingTestVariable
        and frameOrStyle or self:GetForFrame(frameOrStyle)
    if not style then style = self:Get() end
    return ResolveStyleColor(style, style.controlInputCanvasColor, style.allEverythingTestVariable)
end
function Styles:GetSectionSurfaceColor(frameOrStyle)
    return GetControlColor(self, frameOrStyle, "sectionSurfaceColor")
end
function Styles:GetSectionBorderColor(frameOrStyle)
    return GetControlColor(self, frameOrStyle, "sectionBorderColor")
end
function Styles:GetRecessedInputShadowColor(frameOrStyle)
    return GetControlColor(self, frameOrStyle, "recessedInputShadowColor")
end
function Styles:GetSeparatorColor(frameOrStyle)
    local style = type(frameOrStyle) == "table" and frameOrStyle.allEverythingTestVariable
        and frameOrStyle or self:GetForFrame(frameOrStyle)
    if not style then style = self:Get() end
    local fallback = ResolveStyleColor(style, style.allEverythingTestVariable, {0, 0, 0, 1})
    return ResolveStyleColor(style, style.separatorColor, fallback)
end
function Styles:GetActivePreset(owner)
    return owner and self:GetConsumerPreset(owner) or self.ActivePreset
end
function Styles:WithConsumer(owner, callback)
    local previous = self.RenderOwner
    self.RenderOwner = owner
    local ok, result = pcall(callback)
    self.RenderOwner = previous
    if not ok then error(result, 0) end
    return result
end
local function Repaint(self, owner)
    for frame, refresh in pairs(visualRefresh) do
        local targetOwner = FindOwner(frame)
        if owner == nil or targetOwner == owner then
            local previous = self.RenderOwner
            self.RenderOwner = targetOwner
            local ok, err = pcall(refresh, frame)
            self.RenderOwner = previous
            if not ok and type(geterrorhandler) == "function" then geterrorhandler()(err) end
        end
    end
end
function Styles:SetConsumerPreset(owner, name)
    if type(owner) ~= "string" or owner == "" or not self.Presets[name] then return false end
    self.ConsumerPresets[owner] = name
    Repaint(self, owner)
    return true
end
-- Legacy global selector retained for consumers not yet using owner-scoped styles.
function Styles:SetActivePreset(name)
    if type(name) ~= "string" or not self.Presets[name] then return false end
    self.ActivePreset = name
    Repaint(self)
    return true
end

local function SetBackdrop(target, fill, border, thickness)
    target:SetBackdrop({
        bgFile = WHITE,
        edgeFile = WHITE,
        edgeSize = thickness or 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    target:SetBackdropColor(unpack(fill))
    target:SetBackdropBorderColor(unpack(border))
end

function Styles:ApplyWindow(frame, state, presetName)
    local style = self:Get(presetName or (FindOwner(frame) and self:GetConsumerPreset(FindOwner(frame))))
    local border = self:GetWindowBorderColor(style)
    SetBackdrop(frame, self:GetMainCanvasColor(style), border, style.edgeSize)
    if frame._tbuSplitTitleAndBodyBorder or frame._tbuHideWindowBorder then
        frame:SetBackdropBorderColor(0, 0, 0, 0)
    end
    if frame._tbuSplitTitleAndBodyBorder then
        -- The outer backdrop remains the body fill, while independent body
        -- edges begin beneath the title bar's three-sided outline.
        for _, edge in ipairs((frame.windowBodyBorder and frame.windowBodyBorder.borderEdges) or {}) do
            edge:SetVertexColor(unpack(border))
        end
    end
    if frame.frameHeader and frame.frameHeader.bg then
        local headerFill = (state == "hover" or state == "drag")
            and self:GetFrameHeaderActiveCanvasColor(style)
            or self:GetMainCanvasColor(style)
        frame.frameHeader.bg:SetVertexColor(unpack(headerFill))
        for _, edge in ipairs(frame.frameHeader.borderEdges or {}) do
            edge:SetVertexColor(unpack(border))
        end
    end
end

function Styles:ApplyPanel(frame, presetName)
    -- Dynamic panes must not capture their initial preset: when the consumer
    -- switches style, resolve the current owner on every repaint.
    local owner = FindOwner(frame)
    local style = self:Get(presetName or (owner and self:GetConsumerPreset(owner)))
    SetBackdrop(frame, self:GetMainCanvasColor(style), self:GetWindowBorderColor(style), style.edgeSize)
    self:RegisterVisual(frame, function(target)
        local currentOwner = FindOwner(target)
        local current = Styles:Get(presetName or (currentOwner and Styles:GetConsumerPreset(currentOwner)))
        SetBackdrop(target, Styles:GetMainCanvasColor(current), Styles:GetWindowBorderColor(current), current.edgeSize)
    end)
end

function Styles:CreateSeparator(parent, anchor, presetName)
    local style = self:Get(presetName)
    local line = self:CreateFlatTexture(parent, "BORDER", self:GetSeparatorColor(style))
    line:SetHeight(1)
    self:RegisterVisual(line, function(texture)
        local owner = FindOwner(texture)
        local currentStyle = Styles:Get(presetName or (owner and Styles:GetConsumerPreset(owner)))
        texture:SetVertexColor(unpack(Styles:GetSeparatorColor(currentStyle)))
    end)
    if anchor == "bottom" then
        line:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
        line:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    else
        line:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    end
    return line
end

-- Shared action button states. Press feedback is transient; persistent selected
-- state belongs to the consuming control, not every action button.
function Styles:ApplyButton(button, hovered, presetName, selected)
    local style = self:Get(presetName or (FindOwner(button) and self:GetConsumerPreset(FindOwner(button))))
    local enabled = not button.IsEnabled or button:IsEnabled()
    local pressed = enabled and button.tbuPressed == true
    local isSelected = selected == nil and button.tbuSelected == true or selected == true
    local fill = pressed
        and self:GetActionButtonPressedCanvasColor(style)
        or self:GetActionButtonCanvasColor(style)
    local border = hovered
        and self:GetActionButtonHoverBorderColor(style)
        or self:GetControlBorderColor(style)
    -- Controlled hudcraft v1.0.18 border comparison: keep the normal
    -- interaction colors but use a single native WHITE8X8 backdrop edge.
    -- Avoid creating independent overlay textures on real action buttons.
    local visual = button.visualFrame or button
    visual:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    visual:SetBackdropColor(unpack(fill))
    visual:SetBackdropBorderColor(unpack(border))
    -- Older builds may have four-edge textures on a reused button.
    if button._tbuInnerBorder then
        for _, edge in ipairs(button._tbuInnerBorder) do edge:Hide() end
    end
    if button.label then
        button.label:SetTextColor(unpack(self:GetTextColor("primary", button.label)))
        button.label:SetAlpha(enabled and 1 or 0.60)
    end
end

function Styles:CreateFlatTexture(parent, layer, color)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetTexture(WHITE)
    texture:SetVertexColor(unpack(color))
    return texture
end

function Styles:CreateButton(parent, label, width, onClick, presetName, labelOptions)
    local button = TBU:CreateBackdropFrame("Button", parent)
    button:SetSize(math.max(1, tonumber(width) or 170), 23)
    local style = self:Get(presetName)
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER", 0, 0)
    text:SetText(label)
    text:SetTextColor(unpack(self:GetTextColor("primary", text)))
    button.label = text
    button.labelOptions = type(labelOptions) == "table" and labelOptions or {}
    button.labelOptions.wrap = button.labelOptions.wrap == true
    button.labelOptions.autoHeight = button.labelOptions.autoHeight == true
    button.labelOptions.horizontalPadding = math.max(0,
        tonumber(button.labelOptions.horizontalPadding) or 8)
    button.labelOptions.verticalPadding = math.max(0,
        tonumber(button.labelOptions.verticalPadding) or 4)
    button.labelOptions.minHeight = math.max(1,
        tonumber(button.labelOptions.minHeight) or button:GetHeight())
    if button.labelOptions.wrap then
        text:ClearAllPoints()
        text:SetPoint("TOPLEFT", button, "TOPLEFT",
            button.labelOptions.horizontalPadding, -button.labelOptions.verticalPadding)
        text:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT",
            -button.labelOptions.horizontalPadding, button.labelOptions.verticalPadding)
        text:SetJustifyH("CENTER")
        text:SetJustifyV("MIDDLE")
        text:SetWordWrap(true)
        if text.SetNonSpaceWrap then text:SetNonSpaceWrap(true) end
    end
    function button:UpdateLabelGeometry()
        local opts = self.labelOptions
        if not opts or not opts.autoHeight or not self.label then return end
        local buttonWidth = self:GetWidth() or 0
        if buttonWidth <= 1 then return end
        local width = math.max(1, buttonWidth - 2 * opts.horizontalPadding)
        self.label:SetWidth(width)
        local textHeight = math.max(1, math.ceil(self.label:GetStringHeight() or 1))
        local height = math.max(opts.minHeight, textHeight + 2 * opts.verticalPadding)
        if math.abs((self:GetHeight() or 0) - height) > 0.0001 then
            self:SetHeight(height)
        end
    end
    if button.labelOptions.wrap or button.labelOptions.autoHeight then
        button:HookScript("OnSizeChanged", function(self)
            self:UpdateLabelGeometry()
        end)
        button:UpdateLabelGeometry()
    end
    button.tbuPressed = false
    button.tbuSelected = false
    self:ApplyButton(button, false, presetName)
    self:RegisterVisual(button, function(b)
        Styles:ApplyButton(b, b:IsMouseOver(), presetName, b.tbuSelected)
    end)
    local function Repaint(b)
        Styles:ApplyButton(b, b:IsMouseOver(), presetName, b.tbuSelected)
    end
    button:SetScript("OnEnter", Repaint)
    button:SetScript("OnLeave", Repaint)
    button:SetScript("OnMouseDown", function(b)
        b.tbuPressed = true
        Repaint(b)
    end)
    button:SetScript("OnMouseUp", function(b)
        b.tbuPressed = false
        Repaint(b)
    end)
    button:HookScript("OnHide", function(b) b.tbuPressed = false end)
    button:HookScript("OnEnable", Repaint)
    button:HookScript("OnDisable", Repaint)
    button:SetScript("OnClick", function(b, ...)
        b.tbuPressed = false
        Repaint(b)
        if onClick then onClick(b, ...) end
    end)
    return button
end

-- Icon buttons keep a generous mouse target while drawing a compact, styleable
-- button outline independently from the icon artwork.
function Styles:CreateIconButton(parent, assetName, onClick, presetName, options)
    options = type(options) == "table" and options or {}
    local style = self:Get(presetName)
    local hitWidth = math.max(1, tonumber(options.hitWidth) or style.iconButtonHitWidth or 25)
    local hitHeight = math.max(1, tonumber(options.hitHeight) or style.iconButtonHitHeight or 24)
    local visualSize = math.max(1, tonumber(options.visualSize) or style.iconButtonVisualSize or 20)
    local glyphSize = math.max(1, tonumber(options.glyphSize) or style.iconButtonGlyphSize or 18)
    local button = self:CreateButton(parent, "", hitWidth, onClick, presetName)
    button:SetSize(hitWidth, hitHeight)
    button.label:Hide()

    local visual = TBU:CreateBackdropFrame("Frame", button)
    visual:SetSize(visualSize, visualSize)
    visual:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.visualFrame = visual
    -- The larger Button is only the mouse target; all visible chrome belongs
    -- to the smaller centered visual frame.
    button:SetBackdropColor(0, 0, 0, 0)
    button:SetBackdropBorderColor(0, 0, 0, 0)

    local glyph = visual:CreateTexture(nil, "OVERLAY")
    glyph:SetTexture(TBU:GetAssetPath(assetName .. ".png"))
    glyph:SetSize(glyphSize, glyphSize)
    glyph:SetPoint("CENTER", visual, "CENTER", 0, 0)
    button.icon = glyph
    local function RepaintGlyph()
        glyph:SetVertexColor(unpack(Styles:GetControlIndicatorColor(button)))
    end
    self:RegisterVisual(glyph, RepaintGlyph)
    button:HookScript("OnEnter", RepaintGlyph)
    button:HookScript("OnLeave", RepaintGlyph)
    button:HookScript("OnMouseDown", RepaintGlyph)
    button:HookScript("OnMouseUp", RepaintGlyph)
    RepaintGlyph()
    self:ApplyButton(button, false, presetName)
    return button
end
