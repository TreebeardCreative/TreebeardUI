-- Shared TreebeardUI framework; no knowledge of any consuming addon.
local _, private = ...
if (private.__TBUISkip or private.__TreebeardUISkip) then return end
local TBU = (private.__TBUIRuntime or private.__TreebeardUIRuntime) or private

-- Window appearance is deliberately independent of Group appearance. The
-- registry is the future seam for applying presets to windows, Groups, or both.
-- The development framework uses ONE neutral window preset; live Main controls
-- retain their original Blizzard-compatible skin for parity testing. No selector yet.
local Styles = {}
TBU.WindowStyles = Styles

local WHITE = "Interface\\Buttons\\WHITE8X8"
Styles.DefaultPreset = "graphite"
Styles.ActivePreset = "graphite"
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
        resizeGripIdle = { 0.69020, 0.71373, 0.75294, 1.00 }, -- #B0B6C0
        interactionGold = { 0.81176, 0.83529, 0.87451, 1.00 }, -- #CFD5DF, neutral accent
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

-- Style-color policy: keep semantic tokens where their behavior differs, but
-- alias values that are intentionally the same. This prevents palette edits from
-- silently desynchronizing matching borders, headings and interaction accents.
-- A consumer can still override any semantic token explicitly in a custom preset.
-- Experimental v1.0 theme tokens. The geometry stays identical between
-- presets; consumers choose the name, the library owns the appearance.
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
-- Graphite uses the same semantic appearance roles as the colorful presets.
-- The values are aliases to established roles rather than extra color inputs.
local graphite = Styles.Presets.graphite
graphite.sectionHeaderFill = graphite.title
graphite.sectionHeaderText = graphite.text
graphite.dropdownFieldBorder = graphite.borderHover
graphite.dropdownActiveBorder = graphite.interactionGold
graphite.dropdownPopupBorder = graphite.interactionGold

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
-- Unregistered consumers always see Graphite.
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
function Styles:ApplyButton(button, hovered, presetName)
    local style = self:Get(presetName or (FindOwner(button) and self:GetConsumerPreset(FindOwner(button))))
    local enabled = not button.IsEnabled or button:IsEnabled()
    local pressed = enabled and button.tbuPressed == true
    local fill = pressed and style.background or (enabled and hovered and style.buttonHover or style.button)
    local border = pressed and style.borderDrag or (enabled and hovered and style.borderHover or style.border)
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
        local rgb = enabled and (pressed and style.muted or style.text) or style.muted
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
    self:ApplyButton(button, false, presetName)
    self:RegisterVisual(button, function(b)
        Styles:ApplyButton(b, b:IsMouseOver(), presetName)
    end)
    local function Repaint(b)
        Styles:ApplyButton(b, b:IsMouseOver(), presetName)
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
