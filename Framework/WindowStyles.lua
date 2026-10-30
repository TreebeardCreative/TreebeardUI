-- Shared TreebeardUI framework; no knowledge of any consuming addon.
local _, private = ...
if (private.__TBUISkip or private.__TreebeardUISkip) then return end
local TBU = (private.__TBUIRuntime or private.__TreebeardUIRuntime) or private

-- Warm Warcraft is the complete default palette and fallback. TreebeardUI
-- ships its built-in presets; consumers choose which ones to offer, and may
-- add their own presets. Consumers choose which shipped presets to expose in
-- their own UI; do not remove presets from the shared library registry.
local Styles = {}
TBU.WindowStyles = Styles

local WHITE = "Interface\\Buttons\\WHITE8X8"
Styles.DefaultPreset = "warm_warcraft"
Styles.ActivePreset = "warm_warcraft"
Styles.ConsumerPresets = {}
Styles.RenderOwner = nil
Styles.Presets = {
    graphite = {
        -- Graphite: intentionally neutral charcoal, with a clearer hierarchy
        -- between the shell, section headings, fields and active controls.
        background = { 0.05098, 0.05490, 0.06275, 0.98 }, -- #0D0E10
        border = { 0.27843, 0.29412, 0.32549, 1.00 }, -- #474B53
        borderHover = { 0.60000, 0.63529, 0.69020, 1.00 }, -- #99A2B0
        borderDrag = { 0.78431, 0.81176, 0.85098, 1.00 }, -- #C8CFD9
        title = { 0.17255, 0.18824, 0.21176, 1.00 }, -- #2C3036
        titleHover = { 0.23529, 0.25490, 0.29020, 1.00 }, -- #3C414A
        panel = { 0.07843, 0.08627, 0.10196, 0.96 }, -- #14161A
        button = { 0.14118, 0.15686, 0.18039, 1.00 }, -- #24282E
        buttonHover = { 0.20784, 0.22745, 0.25882, 1.00 }, -- #353A42
        text = { 0.93333, 0.94118, 0.95294, 1.00 }, -- #EEF0F3
        muted = { 0.68627, 0.71373, 0.75294, 1.00 }, -- #AFB6C0
        edgeSize = 1,
        titleHeight = 29,
        paneHeaderHeight = 62,
        paneFooterHeight = 36,
        paneGutter = 18,
        paneBorderInset = 0,
        sectionCanvasLeft = 12,
        sectionCanvasRight = 12,
        sectionCanvasTop = 15,
        sectionCanvasBottom = 15,
        pageTitleTop = 8,
        pageDescriptionTop = 32,
        -- Graphite owns defaults for every visible color role. Other presets
        -- inherit these unless they deliberately choose a different color.
        resizeGripIdle = { 0.69020, 0.71373, 0.75294, 1.00 }, -- #B0B6C0
        interactionGold = { 0.81176, 0.83529, 0.87451, 1.00 }, -- #CFD5DF, neutral accent
        sectionHeaderFill = { 0.17255, 0.18824, 0.21176, 1.00 }, -- #2C3036; same as title, independent role
        sectionHeaderText = { 0.93333, 0.94118, 0.95294, 1.00 }, -- #EEF0F3; same as text, independent role
        dropdownFieldBorder = { 0.60000, 0.63529, 0.69020, 1.00 }, -- #99A2B0; same as borderHover, independent role
        dropdownActiveBorder = { 0.81176, 0.83529, 0.87451, 1.00 }, -- #CFD5DF; same as interactionGold, independent role
        dropdownPopupBorder = { 0.81176, 0.83529, 0.87451, 1.00 }, -- #CFD5DF; same as interactionGold, independent role
        dropdownDivider = { 0.35, 0.35, 0.35, 0.90 },
        canvasBackground = { 0.055, 0.055, 0.065, 1.0 }, -- #0E0E11
        sectionBackground = { 0, 0, 0, 0.18 },
        inputShadow = { 0, 0, 0, 0.55 },
        scrollTrack = { 0.15, 0.15, 0.15, 0.90 },
        sliderTrack = { 0.15, 0.15, 0.15, 0.90 }, -- same current value as scrollTrack; independent role
        orderedRowBackground = { 0.07, 0.07, 0.07, 0.45 },
        orderedRowBorder = { 0.30, 0.30, 0.30, 0.8 },
        orderedRowHover = { 0.65, 0.75, 0.95, 0.14 },
        resizeHighlight = { 0.50, 0.51, 0.55, 0.20 },
        navigationWidth = 155,
        navigationGap = 12,
        contentSectionWidth = 540,
        sectionColumnGap = 12,
        settingsSize = { 801, 620, 801, 620 },
        debugSize = { 710, 395, 530, 290 },
        edgeInside = 6,
        edgeOutside = 5,
    },
}

-- Keep semantic roles as independent palette entries even when two Graphite
-- roles currently share a color. Other presets may distinguish those roles.
-- Other styles clone Graphite first, then override only intentionally distinct
-- values. Geometry stays shared between presets.
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
local graphite = Styles.Presets.graphite

-- Warm Warcraft is an experiment based on Forever's dark, bronze-and-gold UI.
-- Keep every color role explicit here so this palette can later become the
-- default without silently inheriting missing values from Graphite.
Styles.Presets.warm_warcraft = {
    -- Main surfaces
    background = {0.10980, 0.09804, 0.09020, 0.98}, -- #1C1917; lifted, less yellow
    panel = {0.16078, 0.13725, 0.11765, 0.96}, -- #29231E; lifted neutral brown
    canvasBackground = {0.06667, 0.05882, 0.05490, 1.00}, -- #110F0E
    sectionBackground = {0.16078, 0.13725, 0.11765, 0.42}, -- #29231E at restrained opacity

    -- Window, section, and control borders
    border = {0.42353, 0.32941, 0.21961, 1.00}, -- #6C5438
    borderHover = {0.66275, 0.49020, 0.27059, 1.00}, -- #A97D45
    borderDrag = {0.88235, 0.72157, 0.24706, 1.00}, -- #E1B83F
    dropdownFieldBorder = {0.42353, 0.32941, 0.21961, 1.00}, -- #6C5438; same as border, independent role
    dropdownActiveBorder = {0.88235, 0.72157, 0.24706, 1.00}, -- #E1B83F
    dropdownPopupBorder = {0.66275, 0.49020, 0.27059, 1.00}, -- #A97D45
    dropdownDivider = {0.36, 0.27, 0.16, 0.90},
    orderedRowBorder = {0.42353, 0.32941, 0.21961, 0.80}, -- #6C5438

    -- Window and section headings
    title = {0.22353, 0.18431, 0.15294, 1.00}, -- #392F27
    titleHover = {0.30980, 0.24706, 0.18824, 1.00}, -- #4F3F30
    sectionHeaderFill = {0.25882, 0.20000, 0.14510, 1.00}, -- #423324
    sectionHeaderText = {0.88235, 0.72157, 0.24706, 1.00}, -- #E1B83F

    -- Text
    text = {0.94118, 0.90588, 0.84314, 1.00}, -- #F0E7D7
    muted = {0.72549, 0.66667, 0.56863, 1.00}, -- #B9AA91

    -- Interaction and selection
    interactionGold = {0.88235, 0.72157, 0.24706, 1.00}, -- #E1B83F
    buttonSelectedBackground = {0.21961, 0.16471, 0.09412, 1.00}, -- #382A18
    buttonSelectedBorder = {0.76863, 0.60392, 0.27059, 1.00}, -- #C49A45
    buttonSelectedText = {0.94118, 0.90588, 0.84314, 1.00}, -- #F0E7D7; same as text, independent role
    resizeGripIdle = {0.72549, 0.66667, 0.56863, 1.00}, -- #B9AA91; same as muted, independent role
    resizeHighlight = {0.88235, 0.72157, 0.24706, 0.20}, -- #E1B83F

    -- Buttons, fields, and scrolling controls
    button = {0.18824, 0.15686, 0.12941, 1.00}, -- #302820
    buttonHover = {0.25098, 0.20000, 0.12941, 1.00}, -- #403321; keep approved hover color
    inputShadow = {0, 0, 0, 0.55},
    scrollTrack = {0.13, 0.11, 0.10, 0.90},
    sliderTrack = {0.13, 0.11, 0.10, 0.90}, -- same current value as scrollTrack, independent role

    -- Reorderable list rows
    orderedRowBackground = {0.07, 0.05, 0.03, 0.58},
    orderedRowHover = {0.88, 0.72, 0.25, 0.14},

    -- Shared geometry; each value is explicit for future standalone use
    edgeSize = 1,
    titleHeight = 29,
    paneHeaderHeight = 62,
    paneFooterHeight = 36,
    paneGutter = 18,
    paneBorderInset = 0,
    sectionCanvasLeft = 12,
    sectionCanvasRight = 12,
    sectionCanvasTop = 15,
    sectionCanvasBottom = 15,
    pageTitleTop = 8,
    pageDescriptionTop = 32,
    navigationWidth = 155,
    navigationGap = 12,
    contentSectionWidth = 540,
    sectionColumnGap = 12,
    settingsSize = {801, 620, 801, 620},
    debugSize = {710, 395, 530, 290},
    edgeInside = 6,
    edgeOutside = 5,
}

-- Midnight Flux: navy/purple surfaces and restrained sunset-orange accents.
Styles.Presets.midnight_flux = ClonePreset(Styles.Presets.graphite)
local flux = Styles.Presets.midnight_flux
flux.background = {0.0510, 0.0706, 0.1569, 0.98} -- #0D1228
flux.title = {0.1255, 0.1255, 0.2784, 1} -- #202047
flux.titleHover = {0.1882, 0.1451, 0.3137, 1} -- #302550
flux.panel = {0.0902, 0.1020, 0.2078, 0.95} -- #171A35
flux.button = {0.1490, 0.1333, 0.2667, 1} -- #262244
flux.buttonHover = {0.2235, 0.1725, 0.3608, 1} -- #392C5C
flux.border = {0.2824, 0.2000, 0.3725, 1} -- #48335F
flux.borderHover = {0.5961, 0.3843, 0.5176, 1} -- #986284
flux.text = {0.9490, 0.9176, 0.9725, 1} -- #F2EAF8
flux.muted = {0.7255, 0.7137, 0.8235, 1} -- #B9B6D2
flux.interactionGold = {0.8980, 0.6314, 0.4000, 1} -- #E5A166
flux.borderDrag = flux.interactionGold -- shared active accent (#E5A166)
-- Dropdown-specific palette tokens. Other presets retain the previous behavior.
flux.dropdownFieldBorder = flux.borderHover -- lighter purple resting dropdown border (#986284)
flux.dropdownActiveBorder = flux.interactionGold -- same soft amber active accent
flux.dropdownPopupBorder = flux.interactionGold -- same soft amber active accent
flux.sectionHeaderFill = flux.border -- restore pre-Graphite-refresh purple header (#48335F)
flux.sectionHeaderText = flux.interactionGold -- restored soft amber heading text
flux.resizeGripIdle = {0.6549, 0.6588, 0.7529, 1} -- #A7A8C0
-- Brushfire: TreebeardCreative-inspired near-black surfaces with true-red accents.
Styles.Presets.brushfire = ClonePreset(Styles.Presets.graphite)
local brushfire = Styles.Presets.brushfire
brushfire.background = {0.0431, 0.0510, 0.0627, 0.98} -- #0B0D10
brushfire.title = {0.3412, 0.0314, 0.0314, 1.00} -- #570808
brushfire.titleHover = {0.5922, 0.0588, 0.0706, 1.00} -- #970F12
brushfire.panel = {0.0667, 0.0784, 0.0902, 0.95} -- #111417
brushfire.button = {0.1255, 0.1294, 0.1451, 1.00} -- #202125
brushfire.buttonHover = {0.2039, 0.1882, 0.2078, 1.00} -- #343035
brushfire.border = {0.5569, 0.0784, 0.0784, 1.00} -- #8E1414
brushfire.borderHover = {0.7569, 0.0706, 0.1216, 1.00} -- #C1121F
brushfire.borderDrag = {0.8196, 0.1686, 0.1686, 1.00} -- #D12B2B
brushfire.text = {0.9490, 0.9412, 0.9255, 1.00} -- #F2F0EC
brushfire.muted = {0.7882, 0.7608, 0.7373, 1.00} -- #C9C2BC
brushfire.sectionHeaderFill = brushfire.title -- same deep-red header background (#570808)
brushfire.sectionHeaderText = brushfire.text -- same warm off-white text (#F2F0EC)
brushfire.interactionGold = brushfire.borderHover -- same active red accent (#C1121F)
brushfire.resizeGripIdle = brushfire.muted -- same subdued warm-grey accent (#C9C2BC)
brushfire.dropdownFieldBorder = brushfire.border -- same resting control border (#8E1414)
brushfire.dropdownActiveBorder = brushfire.interactionGold -- same active red accent (#C1121F)
brushfire.dropdownPopupBorder = brushfire.interactionGold -- same active red accent (#C1121F)

-- Semantic typography contract (shared by all consumers):
--   primary: control labels, entered values, buttons, page titles
--   notes: section descriptions, guidance and low-emphasis information
--   header: titles in section header bands
--   disabled: currently same as notes; a separate token can be added only if needed
-- These are aliases, not additional independent color values.
function Styles:GetTextColor(role, frame)
    local style = frame and self:GetForFrame(frame) or self:Get()
    if role == "notes" or role == "value" or role == "disabled" then return style.muted or style.text end
    if role == "header" then return style.sectionHeaderText or style.text end
    return style.text
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
    local border = state == "drag" and style.borderDrag
        or state == "hover" and style.borderHover or style.border
    SetBackdrop(frame, style.background, border, style.edgeSize)
    if frame.windowHeader and frame.windowHeader.bg then
        local titleColor = state == "normal" and style.title or style.titleHover
        frame.windowHeader.bg:SetVertexColor(unpack(titleColor))
    end
end

function Styles:ApplyPanel(frame, presetName)
    -- Dynamic panes must not capture their initial preset: when the consumer
    -- switches style, resolve the current owner on every repaint.
    local owner = FindOwner(frame)
    local style = self:Get(presetName or (owner and self:GetConsumerPreset(owner)))
    SetBackdrop(frame, style.panel, style.border, style.edgeSize)
    self:RegisterVisual(frame, function(target)
        local currentOwner = FindOwner(target)
        local current = Styles:Get(presetName or (currentOwner and Styles:GetConsumerPreset(currentOwner)))
        SetBackdrop(target, current.panel, current.border, current.edgeSize)
    end)
end

function Styles:CreateSeparator(parent, anchor, presetName)
    local style = self:Get(presetName)
    local line = self:CreateFlatTexture(parent, "BORDER", style.border)
    line:SetHeight(1)
    self:RegisterVisual(line, function(texture)
        texture:SetVertexColor(unpack(Styles:Get(presetName or (FindOwner(texture) and Styles:GetConsumerPreset(FindOwner(texture)))).border))
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
    local selectedFill = isSelected and (style.buttonSelectedBackground or style.buttonHover)
    local selectedBorder = isSelected and (style.buttonSelectedBorder or style.borderHover)
    local fill = pressed and style.background
        or selectedFill
        or (enabled and hovered and style.buttonHover or style.button)
    local border = pressed and style.borderDrag
        or selectedBorder
        or (isSelected and style.borderHover)
        or (enabled and hovered and style.borderHover or style.border)
    -- Controlled hudcraft v1.0.18 border comparison: keep the normal
    -- interaction colors but use a single native WHITE8X8 backdrop edge.
    -- Avoid creating independent overlay textures on real action buttons.
    button:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    button:SetBackdropColor(unpack(fill))
    button:SetBackdropBorderColor(unpack(border))
    -- Older builds may have four-edge textures on a reused button.
    if button._tbuInnerBorder then
        for _, edge in ipairs(button._tbuInnerBorder) do edge:Hide() end
    end
    if button.label then
        local selectedText = isSelected and style.buttonSelectedText
        local rgb = enabled and (pressed and style.muted or selectedText or style.text) or style.muted
        button.label:SetTextColor(unpack(rgb))
        button.label:SetAlpha(enabled and 1 or 0.60)
    end
end

function Styles:CreateFlatTexture(parent, layer, color)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetTexture(WHITE)
    texture:SetVertexColor(unpack(color))
    return texture
end

function Styles:CreateButton(parent, label, width, onClick, presetName)
    local button = TBU.Compatibility:CreateBackdropFrame("Button", parent)
    button:SetSize(math.max(1, tonumber(width) or 170), 23)
    local style = self:Get(presetName)
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER", 0, 0)
    text:SetText(label)
    text:SetTextColor(unpack(style.text))
    button.label = text
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
