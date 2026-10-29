-- Shared TreebeardUI framework; no knowledge of any consuming addon.
local _, private = ...
if (private.__TBUISkip or private.__TreebeardUISkip) then return end
local TBU = (private.__TBUIRuntime or private.__TreebeardUIRuntime) or private

-- Shared Settings page canvas and scroll lifecycle. No navigation routing,
-- semantic content, or Blizzard category registration lives here.
local PageHost = {}
TBU.SettingsPageHost = PageHost

local WHITE = "Interface\\Buttons\\WHITE8X8"

local function CreateScroll(parent, topOffset, bottomInset, withScrollbar, themeMode, leftInset)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll() or 0
        local range = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(range, current - delta * 35)))
    end)
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", leftInset == nil and 8 or leftInset, -topOffset)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -TBU.SettingsControls.ScrollbarGutterWidth, bottomInset)
    local scrollbar
    if withScrollbar then
        scrollbar = TBU.SettingsControls:AttachScrollbar(parent, scroll, themeMode or "gold")
    end
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    return scroll, content, scrollbar
end

function PageHost:CreateCanvas(name, description, pageId, opts)
    opts = opts or {}
    local panel = CreateFrame("Frame")
    panel.name = name

    local background = panel:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(panel)
    background:SetTexture(WHITE)
    background:SetVertexColor(0.055, 0.055, 0.065, 1.0)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(opts.title or name or "Settings")
    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    desc:SetText(description or "")
    if TBU.WindowStyles then
        local function repaintDescription(target)
            target:SetTextColor(unpack(TBU.WindowStyles:GetTextColor("notes", target)))
        end
        TBU.WindowStyles:RegisterVisual(desc, repaintDescription)
        repaintDescription(desc)
    end
    -- Existing helper's styling is unchanged: GameFontHighlightSmall has the
    -- same visual role as the previous ApplyContentText("CONTENT_TEXT").
    if opts.styleDescription then opts.styleDescription(desc) end

    local scroll, content, scrollbar = CreateScroll(panel, 58, 8, true)
    local layout = TBU.SettingsLayout:Page(content, pageId, { padding = 0 })
    local host = { panel=panel, scroll=scroll, content=content,
        scrollbar=scrollbar, layout=layout, pageId=pageId, rows={}, sections={} }
    return host
end

-- Only dropdown Content elements participate in popup overflow reservation;
-- Sections/Rows/Columns retain their ordinary measured heights. Read the
-- shared layout registry once instead of traversing arbitrary WoW child frames.
local function GatherDropdowns(node, found)
    if not node then return end
    if node.layoutRole == "dropdown" and node.Control
        and node.Control.GetExpandedMenuHeight then
        found[#found + 1] = node.Control
    end
    for _, child in ipairs(node.layoutChildren or {}) do
        GatherDropdowns(child, found)
    end
end

local function PopupAwareContentHeight(host, dropdowns, naturalHeight, bottomPad)
    local height = naturalHeight + bottomPad
    local canvasTop = host.content:GetTop()
    if not canvasTop then return height end
    for _, dropdown in ipairs(dropdowns) do
        if dropdown:IsShown() then
            local bottom = dropdown:GetBottom()
            if bottom then
                local menuHeight = math.max(0, tonumber(dropdown:GetExpandedMenuHeight()) or 0)
                local menuOffset = dropdown.GetPopupDownwardOffset
                    and dropdown:GetPopupDownwardOffset() or 0
                -- Compare each absolute expanded bottom against the natural
                -- content bottom. Only the furthest edge reserves scroll room:
                -- never add popup heights to one another.
                local expandedBottom = canvasTop - bottom + menuOffset + menuHeight
                height = math.max(height, expandedBottom + bottomPad)
            end
        end
    end
    return math.max(1, height)
end

function PageHost:BindSections(host, definitions, opts)
    opts = opts or {}
    local sections, rows = {}, {}
    local wrapSections = opts.wrapSections == true
    for index, definition in ipairs(definitions or {}) do
        local section = (type(definition) == "table" and rawget(definition, "section")) or definition
        local id = definition.id or tostring(index)
        if section:GetParent() ~= host.content then section:SetParent(host.content) end
        sections[#sections + 1] = section
        if not wrapSections then
            rows[#rows + 1] = TBU.SettingsLayout:PageSectionRow(
                host.layout, (opts.rowPrefix or host.pageId .. "-row-") .. index .. (opts.useIds and "-" .. id or ""), section)
        end
    end
    host.sections, host.rows = sections, rows
    local dropdowns = {}
    for _, section in ipairs(sections) do GatherDropdowns(section, dropdowns) end
    local function Measure()
        -- Blizzard canvas width can be unresolved before first OnShow.
        if opts.legacyMain then
            for _, section in ipairs(sections) do TBU.SettingsLayout:ReflowSection(section) end
        end
        local width = tonumber(host.scroll:GetWidth()) or 0
        if width <= 1 then
            width = tonumber((opts.legacyMain and host.layout or host.panel):GetWidth()) or 0
        end
        if width <= 1 then return end
        host.content:SetWidth(width)
        host.layout:ClearAllPoints()
        host.layout:SetPoint("TOPLEFT", host.content, "TOPLEFT", 0, 0)
        host.layout:SetWidth(width)
        if wrapSections then
            -- Page-level adaptive placement; entire Sections stay intact.
            -- The native Blizzard host continues through ReflowPage below.
            local height = TBU.SettingsLayout:FlowPageSections(host.layout, sections, {
                width=width,
                sectionWidth=opts.sectionWidth,
                columnGap=opts.columnGap,
                rowGap=opts.rowGap,
                left=opts.contentLeftPadding,
                right=opts.contentRightPadding,
                top=opts.contentTopPadding,
            })
            local bottomPad = math.max(0, tonumber(opts.contentBottomPadding) or 18)
            host.content:SetHeight(PopupAwareContentHeight(host, dropdowns, height, bottomPad))
            host.scrollbar:RefreshVisibility()
            TBU.SettingsLayout:DisableTextureSnapping(host.panel)
            return
        end
        if not opts.legacyMain then
            for _, section in ipairs(sections) do
                section:SetWidth(width)
                TBU.SettingsLayout:ReflowSection(section)
            end
        end
        local height = TBU.SettingsLayout:ReflowPage(host.layout, rows, {
            width=width, padding=0, gap=TBU.SettingsLayout.Metrics.SECTION_GAP,
        })
        host.content:SetHeight(PopupAwareContentHeight(host, dropdowns, height or 1, 18))
        host.scrollbar:RefreshVisibility()
        TBU.SettingsLayout:DisableTextureSnapping(host.panel)
    end
    host.Measure = Measure
    host.ScheduleMeasure = TBU.SettingsPageMeasure:Create(host.panel, Measure, {passes=wrapSections and 1 or 4})
    if wrapSections then
        -- Window resizing changes the viewport mid-frame. Do not reflow
        -- sections against an intermediate width before the root finishes its
        -- combined size update. Coalesce viewport changes into the next tick;
        -- explicit page refreshes still run immediately through ScheduleMeasure.
        host.ScheduleViewportMeasure = TBU.SettingsPageMeasure:Create(host.panel, Measure, {
            passes=1, defer=true,
        })
        host.scroll:HookScript("OnSizeChanged", host.ScheduleViewportMeasure)
    else
        host.scroll:HookScript("OnSizeChanged", host.ScheduleMeasure)
    end
    host.scroll:HookScript("OnSizeChanged", function()
        TBU.SettingsLayout:DisableTextureSnapping(host.panel)
    end)
    -- Preserve each page builder's OnShow refresh hooks when adding shared
    -- measurement. SetScript here would silently replace color/control refresh.
    host.panel:HookScript("OnShow", host.ScheduleMeasure)
    host.panel:HookScript("OnShow", function()
        TBU.SettingsLayout:DisableTextureSnapping(host.panel)
    end)
    -- Scroll range is computed by the client after child size/anchors settle.
    -- Refresh the chrome on the next two visible frames even if no new
    -- OnSizeChanged fires. This fixes a hidden bar on initial/reload visits.
    local visibilityFrame = CreateFrame("Frame", nil, host.panel)
    visibilityFrame:Hide()
    local remainingVisibility = 0
    visibilityFrame:SetScript("OnUpdate", function(self)
        if host.scrollbar and host.scroll:IsVisible() then
            host.scrollbar:RefreshVisibility()
        end
        remainingVisibility = remainingVisibility - 1
        if remainingVisibility <= 0 then self:Hide() end
    end)
    local function ScheduleVisibility()
        remainingVisibility = 3
        visibilityFrame:Show()
    end
    host.scroll:HookScript("OnShow", ScheduleVisibility)
    host.panel:HookScript("OnShow", ScheduleVisibility)
    host.scroll:HookScript("OnSizeChanged", ScheduleVisibility)
    return host.ScheduleMeasure
end

-- Live host for pages embedded inside a framework-owned settings window.
-- Shares the same ScrollFrame, content Page, and BindSections lifecycle as
-- Blizzard Settings; only the containing panel/scroll insets differ.
function PageHost:CreateEmbedded(parent, pageId)
    -- The scroll viewport itself is flush with its shared header/footer.
    -- Section placement padding is measured separately in BindSections.
    local scroll, content, scrollbar = CreateScroll(parent, 0, 0, true, "graphite", 0)
    local layout = TBU.SettingsLayout:Page(content, pageId, {padding=0})
    return {panel=parent, scroll=scroll, content=content,
        scrollbar=scrollbar, layout=layout, pageId=pageId, rows={}, sections={}}
end

-- Placeholder pages use the same scroll infrastructure as the live
-- embedded host, without allocating real controls for those pages yet.
function PageHost:CreatePreviewViewport(parent)
    local scroll, content, scrollbar = CreateScroll(parent, 0, 0, true, "graphite", 0)
    local function Update()
        local width = tonumber(scroll:GetWidth()) or 0
        if width <= 1 then return end
        content:SetWidth(width)
        if content.previewText then content.previewText:SetWidth(math.max(100, width - 20)) end
        local textHeight = content.previewText and content.previewText:GetStringHeight() or 0
        content:SetHeight(math.max(1, textHeight + 50))
        scrollbar:RefreshVisibility()
    end
    scroll:HookScript("OnSizeChanged", Update)
    return {scroll=scroll, content=content, Refresh=Update}
end
