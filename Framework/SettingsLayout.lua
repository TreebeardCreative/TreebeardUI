-- Shared TreebeardUI framework; no knowledge of any consuming addon.
local _, private = ...
if (private.__TBUISkip or private.__TreebeardUISkip) then return end
local TBU = (private.__TBUIRuntime or private.__TreebeardUIRuntime) or private

TBU.SettingsLayout = TBU.SettingsLayout or {}
local L = TBU.SettingsLayout

local DEFAULT_GAP = TBU.Constants.Layout.SETTINGS_GAP
local DEFAULT_PADDING = TBU.Constants.Layout.SETTINGS_PADDING

-- One shared geometry grid per layout pass. All descendants of a frame use
-- the same physical-pixel size, rather than rounding each border independently.
-- The right/bottom gutter absorbs any remainder of the available dimensions.
local function LayoutPixel(frame)
    local scale = frame and frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    if not scale or scale <= 0 then scale = 1 end
    if type(GetPhysicalScreenSize) == "function" and UIParent and UIParent.GetHeight then
        local ok, _, physicalHeight = pcall(GetPhysicalScreenSize)
        local uiHeight = UIParent:GetHeight()
        local uiScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
        if ok and physicalHeight and physicalHeight > 0 and uiHeight and uiHeight > 0
            and uiScale and uiScale > 0 then
            return (uiHeight * uiScale / physicalHeight) / scale
        end
    end
    return 1 / scale
end

local function FloorGrid(value, pixel)
    return math.floor(math.max(0, value) / pixel + 0.000001) * pixel
end

local function CeilGrid(value, pixel)
    return math.ceil(math.max(0, value) / pixel - 0.000001) * pixel
end

local function SetAnchorsIfChanged(frame, anchors)
    local saved = frame._tbuLayoutAnchorSpec
    local same = saved and #saved == #anchors
    if same then
        for i, anchor in ipairs(anchors) do
            local old = saved[i]
            if old[1] ~= anchor[1] or old[2] ~= anchor[2] or old[3] ~= anchor[3]
                or math.abs(old[4] - anchor[4]) > 0.0001
                or math.abs(old[5] - anchor[5]) > 0.0001 then
                same = false
                break
            end
        end
    end
    if same then return false end
    frame:ClearAllPoints()
    local copy = {}
    for i, anchor in ipairs(anchors) do
        copy[i] = {anchor[1], anchor[2], anchor[3], anchor[4], anchor[5]}
        frame:SetPoint(anchor[1], anchor[2], anchor[3], anchor[4], anchor[5])
    end
    frame._tbuLayoutAnchorSpec = copy
    return true
end

local function SetWidthIfChanged(frame, width)
    if frame and math.abs((frame:GetWidth() or 0) - width) > 0.0001 then frame:SetWidth(width) end
end

local function SetHeightIfChanged(frame, height)
    if frame and math.abs((frame:GetHeight() or 0) - height) > 0.0001 then frame:SetHeight(height) end
end


-- Shared Settings geometry. Ordinary Settings UI must consume these values
-- instead of inventing section-local padding, gaps, or header spacing.
L.Metrics = {
    SECTION_PADDING = 5,
    SECTION_GAP = 2,
    PAGE_SECTION_GAP = 6,
    CONTENT_GAP = 2,
    SECTION_BODY_GAP = 14,
    SECTION_BOTTOM_PADDING = 14,
    ROW_GAP = 2,
    COLUMN_GAP = 4,
    -- Rows grow from their measured content. This is the symmetric default
    -- vertical inset on each Row; layout applies it above and below children.
    ROW_MIN_HEIGHT = 1,
    ROW_VERTICAL_PADDING = 1,
    -- Host-region inset is separate from the internal Row breathing room.
    ROW_REGION_INSET_Y = 2,
    SECTION_HEADER_HEIGHT = 30,
    DESCRIPTION_GAP = 2,
    CONTENT_HEADER_HEIGHT = 20,
    CONTENT_BOTTOM_PADDING = 10,
    -- Shared native-slider geometry; label region matches dropdown Content.
    SLIDER_CONTROL_HEIGHT = 26,
    SLIDER_HIT_HEIGHT = 18,
    SLIDER_TRACK_HEIGHT = 5,
    SLIDER_THUMB_SIZE = 13,
    SLIDER_ENDPOINT_GAP = 9,
    COLOR_CONTROL_GAP = 3,
    COLOR_EDIT_HEIGHT = 24,
    SELECTION_CONTENT_BOTTOM_PADDING = 3,
}

-- Shared vertical-flow primitives. A Section is the page-level vertical
-- container; Rows/Columns can use the same registration contract as the
-- architecture is migrated away from section-local coordinates.
-- Every layout container owns one child registry. Flow is a property of a child,
-- not a second child list. This keeps Section/Box/Row/Column on one contract.
local function RegisterChild(parent, child, opts)
    if not parent or not child then return child end
    opts = opts or {}
    parent.layoutChildren = parent.layoutChildren or {}
    child.layoutParent = parent
    child.layoutRole = opts.role or child.layoutRole or "content"
    child.layoutGapBefore = opts.gapBefore
    child.layoutParticipatesInFlow = opts.flow == true
    table.insert(parent.layoutChildren, child)
    return child
end

function L:RegisterChild(parent, child, opts)
    return RegisterChild(parent, child, opts)
end

function L:RegisterFlowChild(parent, child, role, gapBefore)
    return RegisterChild(parent, child, { role = role, gapBefore = gapBefore, flow = true })
end

-- Promote an already-registered child into the shared flow without inserting it
-- a second time. This is useful while legacy Settings content is migrated a
-- few structural groups at a time.
function L:SetFlowChild(parent, child, role, gapBefore)
    if not parent or not child then return child end
    parent.layoutChildren = parent.layoutChildren or {}
    local found = false
    for _, existing in ipairs(parent.layoutChildren) do
        if existing == child then found = true break end
    end
    if not found then
        table.insert(parent.layoutChildren, child)
    end
    child.layoutParent = parent
    child.layoutRole = role or child.layoutRole or "content"
    child.layoutGapBefore = gapBefore
    child.layoutParticipatesInFlow = true
    return child
end

-- One-pixel inner edges anchored directly to their owner's final geometry.
-- Unlike 1px SetBackdrop edge rendering, these do not rely on the backdrop
-- border's pixel-snapping/rebuild path after a Section is measured or resized.
-- Edges deliberately stay INSIDE the frame, avoiding scroll-parent clipping.
function L:CreateInnerBorder(frame)
    if frame._tbuInnerBorder then return frame._tbuInnerBorder end
    local parts = {}
    -- One physical pixel at the frame's effective scale; fractional WoW UI
    -- coordinates otherwise round differently during scroll and resize.
    local effectiveScale = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    local uiScale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    local pixel = (effectiveScale and effectiveScale > 0) and (uiScale / effectiveScale) or 1
    if type(GetPhysicalScreenSize) == "function" and UIParent and UIParent.GetHeight then
        local ok, _, screenHeight = pcall(GetPhysicalScreenSize)
        local uiHeight = UIParent:GetHeight()
        if ok and screenHeight and screenHeight > 0 and uiHeight and uiHeight > 0 then
            pixel = pixel * uiHeight / screenHeight
        end
    end
    if pixel <= 0 then pixel = 1 end
    for _, side in ipairs({"top", "bottom", "left", "right"}) do
        local edge = frame:CreateTexture(nil, "OVERLAY")
        edge:SetTexture("Interface\\Buttons\\WHITE8X8")
        -- This edge already has a physical-pixel width. Leave texture sampling
        -- unsnapped so the client does not independently sharpen each edge as
        -- a content viewport changes size.
        if type(edge.SetSnapToPixelGrid) == "function" then
            edge:SetSnapToPixelGrid(false)
        end
        if type(edge.SetTexelSnappingBias) == "function" then
            edge:SetTexelSnappingBias(0)
        end
        if side == "top" then
            edge:SetHeight(pixel)
            edge:SetPoint("TOPLEFT", frame, "TOPLEFT", pixel, -pixel)
            edge:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pixel, -pixel)
        elseif side == "bottom" then
            edge:SetHeight(pixel)
            edge:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pixel, pixel)
            edge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pixel, pixel)
        elseif side == "left" then
            edge:SetWidth(pixel)
            edge:SetPoint("TOPLEFT", frame, "TOPLEFT", pixel, -pixel)
            edge:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pixel, pixel)
        else
            edge:SetWidth(pixel)
            edge:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pixel, -pixel)
            edge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pixel, pixel)
        end
        parts[#parts+1] = edge
    end
    frame._tbuInnerBorder = parts
    return parts
end

function L:SetInnerBorderColor(frame, color)
    local parts = self:CreateInnerBorder(frame)
    if type(color) ~= "table" then return end
    for _, edge in ipairs(parts) do edge:SetVertexColor(unpack(color)) end
end

-- Disable the client's texture-edge sharpening under a framework-owned page.
-- This pass also catches backdrop/template textures the library did not create
-- directly. Run it after layout and again when a viewport changes, since a
-- later texture/style update can restore its default sampling flags.
local SHARPENED_REGION_TYPES = {Texture=true, MaskTexture=true, Line=true}
function L:DisableTextureSnapping(root)
    if not root or type(root.GetRegions) ~= "function" then return 0 end
    local pending, visited = {root}, {}
    local changed = 0
    while #pending > 0 do
        local frame = table.remove(pending)
        if not visited[frame] then
            visited[frame] = true
            if type(frame.GetRegions) == "function" then
                for _, region in ipairs({frame:GetRegions()}) do
                    local kind = type(region.GetObjectType) == "function" and region:GetObjectType()
                    if SHARPENED_REGION_TYPES[kind] then
                        local didChange = false
                        if type(region.SetSnapToPixelGrid) == "function" then
                            local snapping = type(region.IsSnappingToPixelGrid) == "function"
                                and region:IsSnappingToPixelGrid()
                            if snapping ~= false then
                                region:SetSnapToPixelGrid(false)
                                didChange = true
                            end
                        end
                        if type(region.SetTexelSnappingBias) == "function" then
                            local bias = type(region.GetTexelSnappingBias) == "function"
                                and region:GetTexelSnappingBias()
                            if bias ~= 0 then
                                region:SetTexelSnappingBias(0)
                                didChange = true
                            end
                        end
                        if didChange then changed = changed + 1 end
                    end
                end
            end
            if type(frame.GetChildren) == "function" then
                for _, child in ipairs({frame:GetChildren()}) do pending[#pending + 1] = child end
            end
        end
    end
    return changed
end

function L:Section(parent, id, opts)
    opts = opts or {}
    local section = TBU.Compatibility:CreateBackdropFrame("Frame", parent)
    section.layoutKind = "section"
    section.layoutId = id
    section.layoutChildren = {}
    section.layoutPadding = opts.padding
    if section.layoutPadding == nil then section.layoutPadding = L.Metrics.SECTION_PADDING end
    section.layoutGap = opts.gap
    if section.layoutGap == nil then section.layoutGap = L.Metrics.SECTION_GAP end

    -- Section is structural. Border/background are presentation choices only.
    if opts.border ~= false then
        -- Controlled Retail comparison: hudcraft v1.0.18's single native
        -- WHITE8X8 backdrop border. Section content/layout are unchanged.
        section:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        local borderStyle = TBU.WindowStyles and TBU.WindowStyles:GetForFrame(section)
        local neutralBorder = borderStyle and borderStyle.border or {0.22, 0.23, 0.26, 0.98}
        local sectionFill = borderStyle and borderStyle.sectionBackground or {0, 0, 0, 0.18}
        if opts.backgroundAlpha ~= nil then
            sectionFill = {sectionFill[1], sectionFill[2], sectionFill[3], opts.backgroundAlpha}
        end
        section:SetBackdropColor(unpack(sectionFill))
        section:SetBackdropBorderColor(unpack(neutralBorder))
        if TBU.WindowStyles and TBU.WindowStyles.RegisterVisual then
            TBU.WindowStyles:RegisterVisual(section, function(target)
                local style = TBU.WindowStyles:GetForFrame(target)
                local fill = style.sectionBackground
                if opts.backgroundAlpha ~= nil then
                    fill = {fill[1], fill[2], fill[3], opts.backgroundAlpha}
                end
                target:SetBackdropColor(unpack(fill))
                target:SetBackdropBorderColor(unpack(style.border))
            end)
        end
    end

    self:PrepareOrdinarySection(section)
    if parent and parent.layoutKind then
        RegisterChild(parent, section, { role = "section", flow = opts.flow ~= false, gapBefore = opts.gapBefore })
    end
    -- A Section created directly under an embedded page's content frame is a
    -- top-level page Section. The page host owns its ordered reflow list; a
    -- nested Section has a different parent and stays in its parent's flow.
    if parent and type(parent._tbuPageSectionCreated) == "function" then
        parent:_tbuPageSectionCreated(section)
    end
    return section
end

function L:MainHeader(section, text, opts)
    opts = opts or {}
    local header = TBU.Compatibility:CreateBackdropFrame("Frame", section)
    local minHeight = tonumber(opts.height) or L.Metrics.SECTION_HEADER_HEIGHT
    local paddingX = math.max(0, tonumber(opts.paddingX) or 8)
    local paddingY = math.max(0, tonumber(opts.paddingY) or 4)
    header:SetHeight(minHeight)
    header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    -- Source the neutral section-title fill from the SAME palette as window
    -- borders. Without an explicit color, WoW draws this as solid white.
    local style = TBU.WindowStyles and TBU.WindowStyles:GetForFrame(header)
    local border = style and style.border or {0.22, 0.23, 0.26, 0.98}
    header:SetBackdropColor(unpack((style and style.sectionHeaderFill) or border))
    if TBU.WindowStyles and TBU.WindowStyles.RegisterVisual then
        TBU.WindowStyles:RegisterVisual(header, function(target)
            local style = TBU.WindowStyles:GetForFrame(target)
            target:SetBackdropColor(unpack(style.sectionHeaderFill or style.border))
            if target.label then target.label:SetTextColor(unpack(style.sectionHeaderText or style.interactionGold)) end
        end)
    end

    local label = header:CreateFontString(nil, "ARTWORK", opts.fontObject or "GameFontNormal")
    label:SetPoint("TOPLEFT", header, "TOPLEFT", paddingX, -paddingY)
    label:SetPoint("TOPRIGHT", header, "TOPRIGHT", -paddingX, -paddingY)
    label:SetJustifyH("CENTER")
    label:SetJustifyV("TOP")
    label:SetWordWrap(opts.wrap ~= false)
    if label.SetNonSpaceWrap then label:SetNonSpaceWrap(opts.wrap ~= false) end
    label:SetText(text or "")
    label:SetTextColor(unpack((style and style.sectionHeaderText) or (style and style.text) or {1, 1, 1, 1}))
    header.label = label

    local function FitHeader()
        local width = tonumber(header:GetWidth()) or 0
        if width <= paddingX * 2 then return end
        SetWidthIfChanged(label, width - (paddingX * 2))
        local textHeight = math.ceil(label:GetStringHeight() or 0)
        local targetHeight = math.max(minHeight, textHeight + (paddingY * 2))
        if math.abs((header:GetHeight() or 0) - targetHeight) > 0.5 then
            header:SetHeight(targetHeight)
        end
    end
    header:HookScript("OnSizeChanged", FitHeader)
    FitHeader()

    RegisterChild(section, header, { role = "main-header", gapBefore = 0, flow = true })
    return header, label
end

function L:Note(section, text, opts)
    opts = opts or {}
    local note = section:CreateFontString(nil, "ARTWORK", opts.fontObject or "GameFontDisableSmall")
    -- Notes placed directly in Columns should fill the Column and wrap by
    -- default. Consumers can pass wrap=false for intentionally fixed-width text.
    note.layoutWrap = opts.wrap ~= false
    note:SetJustifyH(opts.justifyH or "CENTER")
    note:SetJustifyV("TOP")
    note:SetWordWrap(opts.wrap ~= false)
    if note.SetNonSpaceWrap then note:SetNonSpaceWrap(opts.wrap ~= false) end
    note:SetText(text or "")
    if TBU.WindowStyles then
        local function repaintNote(target)
            target:SetTextColor(unpack(TBU.WindowStyles:GetTextColor("notes", target)))
        end
        TBU.WindowStyles:RegisterVisual(note, repaintNote)
        repaintNote(note)
    end
    local gapBefore = opts.gapBefore
    if gapBefore == nil then gapBefore = L.Metrics.CONTENT_GAP end
    RegisterChild(section, note, { role = "note", gapBefore = gapBefore, flow = true })
    return note
end

function L:ReflowSection(section)
    if not section or not section.layoutChildren then return 1 end
    local pad = section.layoutPadding or L.Metrics.SECTION_PADDING
    local sectionGap = section.layoutGap or L.Metrics.SECTION_GAP
    local previous
    local firstFlowChild
    for _, child in ipairs(section.layoutChildren) do
        if child.layoutParticipatesInFlow and child:IsShown() then
            firstFlowChild = child
            break
        end
    end
    -- Main headers are anchored to the Section's top edge. Do not count the
    -- Section's top inset as blank space before that header; place that inset
    -- after the header, before the first body item, and retain one bottom inset.
    local total = firstFlowChild and firstFlowChild.layoutRole == "main-header" and 0 or pad

    for _, child in ipairs(section.layoutChildren) do
        if child.layoutParticipatesInFlow and child:IsShown() then
            if child.layoutKind == "section" then
                SetWidthIfChanged(child, math.max(1, section:GetWidth() - (pad * 2)))
                self:ReflowSection(child)
            elseif child.layoutKind == "row" then
                self:LayoutRow(child, math.max(1, section:GetWidth() - (pad * 2)))
            end
            local gap = previous and (child.layoutGapBefore or sectionGap) or 0
            if previous and previous.layoutRole == "main-header" then
                gap = math.max(gap, pad)
            end
            local anchors
            if previous then
                local xInset = (previous.layoutRole == "main-header") and (pad - 1) or 0
                anchors = {
                    {"TOPLEFT", previous, "BOTTOMLEFT", xInset, -gap},
                    {"RIGHT", section, "RIGHT", -pad, 0},
                }
                total = total + gap
            else
                -- Main headers span the section border; ordinary flow content
                -- uses the shared section inset.
                if child.layoutRole == "main-header" then
                    anchors = {
                        {"TOPLEFT", section, "TOPLEFT", 1, -1},
                        {"RIGHT", section, "RIGHT", -1, 0},
                    }
                else
                    anchors = {
                        {"TOPLEFT", section, "TOPLEFT", pad, -pad},
                        {"RIGHT", section, "RIGHT", -pad, 0},
                    }
                end
            end

            SetAnchorsIfChanged(child, anchors)

            local h = (child.GetHeight and child:GetHeight()) or 0
            if child.GetObjectType and child:GetObjectType() == "FontString" then
                h = math.max(h or 0, child:GetStringHeight() or 0)
            end
            h = math.max(1, h or 0)
            total = total + h
            previous = child
        end
    end

    -- Round the measured outer rectangle upward on the physical-pixel grid.
    -- Each child height and gap above uses that same grid, so dynamic growth
    -- cannot leave the section's bottom edge between screen pixels.
    SetHeightIfChanged(section, math.max(1, total + pad))
    return section:GetHeight()
end

function L:PrepareOrdinarySection(section)
    -- Section frames deliberately start geometry-free. StackSections owns width
    -- and placement; the section's content flow must eventually own height.
    section:ClearAllPoints()
    section:SetHeight(1)
    section._tbuOrdinarySection = true
end

local function Node(parent, kind, id, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent)
    f.layoutKind = kind
    f.layoutId = id
    f.layoutGap = opts.gap or DEFAULT_GAP
    f.layoutPadding = opts.padding
    if f.layoutPadding == nil then f.layoutPadding = (kind == "box") and DEFAULT_PADDING or 0 end
    f.layoutChildren = {}
    if parent and parent.layoutKind then
        RegisterChild(parent, f, { role = kind, flow = opts.flow == true, gapBefore = opts.gapBefore })
    end
    return f
end

function L:Box(parent, id, opts)
    opts = opts or {}
    local box = Node(parent, "box", id, opts)
    box.layoutBorder = opts.border == true
    return box
end

local function NormalizeHorizontalAlign(value)
    value = type(value) == "string" and string.upper(value) or "LEFT"
    if value ~= "LEFT" and value ~= "CENTER" and value ~= "RIGHT" then
        return "LEFT"
    end
    return value
end

local function NormalizeVerticalAlign(value)
    value = type(value) == "string" and string.upper(value) or "TOP"
    if value ~= "TOP" and value ~= "CENTER" and value ~= "BOTTOM" then
        return "TOP"
    end
    return value
end

local function NormalizeLayoutPadding(value, default)
    value = value == nil and default or value
    if type(value) == "number" then
        local amount = math.max(0, value)
        return { left=amount, right=amount, top=amount, bottom=amount }
    end
    value = type(value) == "table" and value or {}
    local horizontal = math.max(0, tonumber(value.horizontal or value.x) or 0)
    local vertical = math.max(0, tonumber(value.vertical or value.y) or 0)
    return {
        left=math.max(0, tonumber(value.left) or horizontal),
        right=math.max(0, tonumber(value.right) or horizontal),
        top=math.max(0, tonumber(value.top) or vertical),
        bottom=math.max(0, tonumber(value.bottom) or vertical),
    }
end

function L:Row(parent, id, opts)
    opts = opts or {}
    local rowOptions = {}
    for key, value in pairs(opts) do rowOptions[key] = value end
    if rowOptions.gap == nil then rowOptions.gap = L.Metrics.ROW_GAP end
    local row = Node(parent, "row", id, rowOptions)
    row.layoutPadding = NormalizeLayoutPadding(opts.padding,
        { horizontal=0, vertical=L.Metrics.ROW_VERTICAL_PADDING })
    -- Rows fill their parent Column. Children default to top-left inside the
    -- Row's padded content area; alignment does not move the padding itself.
    row.layoutVerticalAlign = NormalizeVerticalAlign(opts.verticalAlign or opts.align)
    row.layoutAlign = row.layoutVerticalAlign -- legacy consumer-facing field
    row.layoutHorizontalAlign = NormalizeHorizontalAlign(opts.horizontalAlign)
    -- Control rows keep the established shared height unless a consumer opts
    -- into a smaller slot for text-only or button-only content.
    local minHeight = tonumber(opts.minHeight)
    if minHeight then
        row.layoutMinHeight = math.max(1, minHeight)
    end
    return row
end

function L:Columns(row, count, ids, opts)
    opts = opts or {}
    count = math.max(1, tonumber(count) or 1)
    -- `gap` remains a compatibility shorthand for callers that historically
    -- used one value for both directions. New callers can tune the horizontal
    -- column gap and vertical content gap independently.
    local legacyGap = opts.gap
    local contentGap = opts.contentGap
    if contentGap == nil then contentGap = legacyGap end
    if contentGap == nil then contentGap = L.Metrics.CONTENT_GAP end
    local columnGap = opts.columnGap
    if columnGap == nil then columnGap = legacyGap end
    if columnGap == nil then columnGap = row.layoutColumnGap end
    if columnGap == nil then columnGap = L.Metrics.COLUMN_GAP end
    local cols = {}
    for i=1,count do
        local id = ids and ids[i] or ("column"..i)
        local columnHorizontalAlign = opts.horizontalAlign or opts.align
        if type(opts.horizontalAlignments) == "table" and opts.horizontalAlignments[i] then
            columnHorizontalAlign = opts.horizontalAlignments[i]
        elseif type(opts.alignments) == "table" and opts.alignments[i] then
            columnHorizontalAlign = opts.alignments[i]
        end
        cols[i] = Node(row, "column", id, { gap=contentGap, padding=0 })
        local columnPadding = opts.padding
        if type(opts.paddings) == "table" and opts.paddings[i] ~= nil then
            columnPadding = opts.paddings[i]
        end
        -- Numeric padding is applied equally on all four sides. A table may
        -- use x/y or explicit left/right/top/bottom values.
        cols[i].layoutPadding = NormalizeLayoutPadding(columnPadding, 0)
        cols[i].layoutHorizontalAlign = NormalizeHorizontalAlign(columnHorizontalAlign)
        cols[i].layoutAlign = cols[i].layoutHorizontalAlign -- legacy consumer-facing field
        local columnVerticalAlign = opts.verticalAlign
        if type(opts.verticalAlignments) == "table" and opts.verticalAlignments[i] then
            columnVerticalAlign = opts.verticalAlignments[i]
        end
        cols[i].layoutVerticalAlign = NormalizeVerticalAlign(columnVerticalAlign)
        local minHeight = type(opts.minHeights) == "table" and tonumber(opts.minHeights[i]) or nil
        cols[i].layoutMinHeight = minHeight and math.max(1, minHeight) or nil
        local fixedWidth = type(opts.widths) == "table" and tonumber(opts.widths[i]) or nil
        cols[i].layoutFixedWidth = fixedWidth and fixedWidth > 0 and fixedWidth or nil
    end
    row.layoutColumns = cols
    row.layoutColumnCount = count
    row.layoutColumnGap = columnGap

    -- Optional per-row column weights. Equal flexible columns remain the
    -- default. A positive `widths[i]` fixes that Column's width; all other
    -- Columns divide the remaining width by weight.
    local weights = {}
    for i = 1, count do
        local weight = type(opts.weights) == "table" and tonumber(opts.weights[i]) or 1
        if not weight or weight <= 0 then weight = 1 end
        weights[i] = weight
    end
    row.layoutColumnWeights = weights

    function row:LayoutColumns(width)
        width = tonumber(width) or self:GetWidth() or 1
        local pixel = LayoutPixel(self)
        local snappedGap = CeilGrid(columnGap, pixel)
        local rowPadding = NormalizeLayoutPadding(self.layoutPadding, 0)
        local innerWidth = math.max(pixel, width - rowPadding.left - rowPadding.right)
        local usable = FloorGrid(math.max(pixel, innerWidth - snappedGap * (count - 1)), pixel)
        local fixedTotal, flexibleWeight = 0, 0
        for i, col in ipairs(cols) do
            if col.layoutFixedWidth then
                fixedTotal = fixedTotal + FloorGrid(col.layoutFixedWidth, pixel)
            else
                flexibleWeight = flexibleWeight + weights[i]
            end
        end
        local flexUsable = math.max(0, usable - fixedTotal)
        local allocated, flexUsed = {}, 0
        for i, col in ipairs(cols) do
            if col.layoutFixedWidth then
                allocated[i] = math.max(pixel, FloorGrid(col.layoutFixedWidth, pixel))
            else
                local nextUsed = flexUsed + weights[i]
                allocated[i] = flexibleWeight > 0
                    and math.max(pixel, FloorGrid(flexUsable * nextUsed / flexibleWeight, pixel)
                        - FloorGrid(flexUsable * flexUsed / flexibleWeight, pixel))
                    or pixel
                flexUsed = nextUsed
            end
        end
        local totalWidth = snappedGap * (count - 1)
        for i = 1, count do totalWidth = totalWidth + allocated[i] end
        local remaining = math.max(0, innerWidth - totalWidth)
        local rowAlign = NormalizeHorizontalAlign(self.layoutHorizontalAlign)
        local x = rowPadding.left + (rowAlign == "RIGHT" and remaining
            or (rowAlign == "CENTER" and remaining / 2 or 0))
        for i, col in ipairs(cols) do
            local columnWidth = allocated[i]
            SetWidthIfChanged(col, columnWidth)
            SetHeightIfChanged(col, math.max(1, col:GetHeight() or 1))
            SetAnchorsIfChanged(col, {{"TOPLEFT", self, "TOPLEFT", x, -rowPadding.top}})
            x = x + columnWidth + snappedGap
        end
    end

    function row:GetColumnWidth(index)
        local pixel = LayoutPixel(self)
        local width = self:GetWidth() or 1
        index = math.max(1, math.min(count, tonumber(index) or 1))
        if (cols[index]:GetWidth() or 0) > 0 then return cols[index]:GetWidth() end
        if cols[index].layoutFixedWidth then
            return math.max(pixel, FloorGrid(cols[index].layoutFixedWidth, pixel))
        end
        local rowPadding = NormalizeLayoutPadding(self.layoutPadding, 0)
        local usable = FloorGrid(math.max(pixel, width - rowPadding.left - rowPadding.right
            - CeilGrid(columnGap, pixel) * (count - 1)), pixel)
        local before = 0
        local fixed, flexibleWeight = 0, 0
        for i = 1, count do
            if cols[i].layoutFixedWidth then
                fixed = fixed + cols[i].layoutFixedWidth
            else
                flexibleWeight = flexibleWeight + weights[i]
                if i < index then before = before + weights[i] end
            end
        end
        local flexUsable = math.max(0, usable - fixed)
        return math.max(pixel, FloorGrid(flexUsable * (before + weights[index]) / math.max(1, flexibleWeight), pixel)
            - FloorGrid(flexUsable * before / math.max(1, flexibleWeight), pixel))
    end
    return cols
end


-- Reusable two-column Section structure. The same Row / Column / Section
-- reflow handles every host; no independent pixel anchoring or frame copies.
-- Sections are borderless presentation by default, but remain fully measured.
function L:SectionPair(parent, id, leftId, rightId, opts)
    opts = opts or {}
    local columnGap = opts.columnGap
    if columnGap == nil then columnGap = L.Metrics.COLUMN_GAP end
    local contentGap = opts.contentGap
    if contentGap == nil then contentGap = opts.columnGap or L.Metrics.CONTENT_GAP end
    local rowGap = opts.rowGap
    if rowGap == nil then rowGap = opts.columnGap or L.Metrics.ROW_GAP end
    local row = self:Row(parent, id, { flow=true, gap=rowGap })
    self:SetFlowChild(parent, row, "row")
    local columns = self:Columns(row, 2, {leftId .. "-host", rightId .. "-host"},
        { columnGap=columnGap, contentGap=contentGap })
    local sectionOpts = {
        flow=true, border=opts.border == true,
        padding=opts.padding == nil and L.Metrics.SECTION_PADDING or opts.padding,
        gap=opts.gap == nil and L.Metrics.SECTION_GAP or opts.gap,
    }
    local left = self:Section(columns[1], leftId, sectionOpts)
    local right = self:Section(columns[2], rightId, sectionOpts)
    left._tbuContentAlign = opts.align
    right._tbuContentAlign = opts.align
    return left, right
end

function L:GetRowVerticalAnchor(row)
    local align = NormalizeVerticalAlign(row and row.layoutVerticalAlign)
    if align == "TOP" then return "TOP" end
    if align == "BOTTOM" then return "BOTTOM" end
    return "CENTER"
end

function L:GetColumnHorizontalAnchor(column)
    local align = NormalizeHorizontalAlign(column and column.layoutHorizontalAlign)
    if align == "LEFT" then return "LEFT" end
    if align == "RIGHT" then return "RIGHT" end
    return "CENTER"
end

function L:AdoptContent(column, content, opts)
    if not column or not content then return content end
    opts = opts or {}
    content.layoutKind = content.layoutKind or "content"
    content.layoutFillWidth = opts.fillWidth == true
    content.layoutMaxWidth = tonumber(opts.maxWidth) or nil
    content.layoutWrap = opts.wrap == true
    content.layoutMeasureHeight = opts.measureHeight or content.layoutMeasureHeight
    return self:SetFlowChild(column, content, opts.role or content.layoutRole or "content", opts.gapBefore)
end

function L:MeasureContent(content)
    if not content then return 1 end
    local measured
    if content.layoutMeasureHeight then
        measured = math.max(1, tonumber(content.layoutMeasureHeight(content)) or 1)
    elseif content.GetObjectType and content:GetObjectType() == "FontString" then
        measured = math.max(1, content:GetStringHeight() or content:GetHeight() or 1)
    else
        measured = math.max(1, (content.GetHeight and content:GetHeight()) or 1)
    end
    return measured + (content.layoutBottomPadding or 0)
end

function L:LayoutRow(row, width)
    if not row then return end
    if not row.layoutColumns or not row.LayoutColumns then
        -- Explicit empty Rows still participate in flow at the same minimum
        -- height as populated Rows; otherwise alignment guides cannot rely
        -- on reserved empty slots.
        row.layoutColumns = row.layoutColumns or {}
        return self:MeasureRow(row)
    end

    width = math.max(1, tonumber(width) or row:GetWidth() or 1)
    local pixel = LayoutPixel(row)
    width = math.max(pixel, FloorGrid(width, pixel))
    SetWidthIfChanged(row, width)
    local rowPadding = NormalizeLayoutPadding(row.layoutPadding, 0)
    row:LayoutColumns(width)

    -- Recursive layout contract:
    -- Section -> Row -> Column -> Content OR Section.
    -- A nested Section receives the width of its Column, reflows its own Rows,
    -- and returns its measured height to that Column. The Row then measures the
    -- tallest Column. No presentation concept (box/header/subsection) participates
    -- in this geometry contract.
    for _, col in ipairs(row.layoutColumns) do
        local outerColumnWidth = math.max(1, col:GetWidth() or 1)
        local columnPadding = NormalizeLayoutPadding(col.layoutPadding, 0)
        local columnWidth = math.max(1, outerColumnWidth - columnPadding.left - columnPadding.right)
        local previous
        local totalHeight = 0
        local placements = {}

        for _, child in ipairs(col.layoutChildren or {}) do
            if child:IsShown() and (child.layoutParticipatesInFlow or child.layoutKind == "section" or child.layoutKind == "row") then
                -- Measure the gap BEFORE placement. Applying it later would
                -- replace CENTER/RIGHT anchors with TOPLEFT for the second
                -- Content in a Column and silently break standard alignment.
                local gap = previous and (child.layoutGapBefore or col.layoutGap or L.Metrics.ROW_GAP) or 0
                totalHeight = totalHeight + math.max(0, gap)
                local anchors
                local childTop = columnPadding.top + totalHeight
                if child.layoutKind == "section" then
                    SetWidthIfChanged(child, columnWidth)
                    anchors = {
                        {"TOPLEFT", col, "TOPLEFT", columnPadding.left, -childTop},
                        {"TOPRIGHT", col, "TOPRIGHT", -columnPadding.right, -childTop},
                    }
                    SetAnchorsIfChanged(child, anchors)
                    placements[#placements + 1] = { child=child, anchors=anchors }
                    self:ReflowSection(child)
                elseif child.layoutKind == "row" then
                    SetWidthIfChanged(child, columnWidth)
                    anchors = {{"TOPLEFT", col, "TOPLEFT", columnPadding.left, -childTop}}
                    SetAnchorsIfChanged(child, anchors)
                    placements[#placements + 1] = { child=child, anchors=anchors }
                    self:LayoutRow(child, columnWidth)
                else
                    if child.layoutWrap and child.GetObjectType and child:GetObjectType() == "FontString" then
                        SetWidthIfChanged(child, columnWidth)
                        child:SetWordWrap(true)
                        child:SetNonSpaceWrap(true)
                    elseif child.layoutFillWidth then
                        local fillWidth = math.min(columnWidth, child.layoutMaxWidth or columnWidth)
                        SetWidthIfChanged(child, fillWidth)
                    elseif child.SetWidth and child.GetWidth then
                        SetWidthIfChanged(child, child:GetWidth() or columnWidth)
                    end
                    local anchor = self:GetColumnHorizontalAnchor(col)
                    if child.layoutFillWidth or anchor == "LEFT" then
                        anchors = {{"TOPLEFT", col, "TOPLEFT", columnPadding.left, -childTop}}
                    elseif anchor == "RIGHT" then
                        anchors = {{"TOPRIGHT", col, "TOPRIGHT", -columnPadding.right, -childTop}}
                    else
                        anchors = {{"TOP", col, "TOP", (columnPadding.left - columnPadding.right) / 2, -childTop}}
                    end
                    SetAnchorsIfChanged(child, anchors)
                    placements[#placements + 1] = { child=child, anchors=anchors }
                end

                local childHeight = self:MeasureContent(child)
                totalHeight = totalHeight + childHeight
                previous = child
            end
        end

        -- Every layout pass owns the current measurement, including an empty
        -- Column. Never retain a previous Content height after its children stop
        -- participating in flow; the structural Column remains, but measures empty.
        col.layoutContentHeight = math.max(1,
            columnPadding.top + totalHeight + columnPadding.bottom)
        col.layoutAllocatedHeight = math.max(col.layoutContentHeight, col.layoutMinHeight or 0)
        SetHeightIfChanged(col, col.layoutAllocatedHeight)
        local freeHeight = math.max(0, col.layoutAllocatedHeight - col.layoutContentHeight)
        local vertical = NormalizeVerticalAlign(col.layoutVerticalAlign)
        local contentOffset = vertical == "BOTTOM" and freeHeight
            or (vertical == "CENTER" and freeHeight / 2 or 0)
        if contentOffset > 0 then
            for _, placement in ipairs(placements) do
                local shifted = {}
                for i, anchorSpec in ipairs(placement.anchors) do
                    shifted[i] = {anchorSpec[1], anchorSpec[2], anchorSpec[3], anchorSpec[4], anchorSpec[5] - contentOffset}
                end
                SetAnchorsIfChanged(placement.child, shifted)
            end
        end
    end

    self:MeasureRow(row)
    -- Rows keep their own order and use their selected vertical alignment only
    -- to place shorter Columns within the measured Row height.
    local anchor = self:GetRowVerticalAnchor(row)
    local rowHeight = row:GetHeight()
    local innerHeight = math.max(0, rowHeight - rowPadding.top - rowPadding.bottom)
    for _, col in ipairs(row.layoutColumns) do
        local contentHeight = col.layoutAllocatedHeight or col.layoutContentHeight or 0
        local remaining = math.max(0, innerHeight - contentHeight)
        local offsetY = anchor == "BOTTOM" and remaining or (anchor == "CENTER" and remaining / 2 or 0)
        local columnX = col._tbuLayoutAnchorSpec and col._tbuLayoutAnchorSpec[1][4] or 0
        SetAnchorsIfChanged(col, {{"TOPLEFT", row, "TOPLEFT", columnX, -(rowPadding.top + offsetY)}})
    end
    return rowHeight
end


-- Arrange complete page Sections into responsive rows. Sections are never
-- split or internally resized beyond their normal reflow; the page chooses how
-- many full Section columns can fit at the preferred width and wraps to a new
-- row when necessary. This keeps Section -> Row -> Column -> Content intact
-- while removing the previous hard two-column ceiling.
function L:FlowPageSections(page, sections, opts)
    opts = opts or {}
    local width = math.max(1, tonumber(opts.width) or page:GetWidth() or 1)
    -- Optional content-width packing. Each Section still reflows through the
    -- standard Section -> Row -> Column -> Content measurement contract; the
    -- page only positions complete, measured Sections in available rows.
    -- Content-width packing remains a separate opt-in arrangement.
    if opts.fitContentWidths then
        local left = math.max(0, tonumber(opts.left) or 0)
        local right = math.max(0, tonumber(opts.right) or 0)
        local top = math.max(0, tonumber(opts.top) or 0)
        local columnGap = math.max(0, tonumber(opts.columnGap) or L.Metrics.PAGE_SECTION_GAP)
        local rowGap = math.max(0, tonumber(opts.rowGap) or L.Metrics.PAGE_SECTION_GAP)
        local available = math.max(1, width - left - right)
        local x, y, rowHeight = 0, top, 0
        for _, section in ipairs(sections or {}) do
            if section:IsShown() then
                local naturalWidth = math.max(1, tonumber(section.layoutPreferredWidth) or available)
                local sectionWidth = math.min(naturalWidth, available)
                SetWidthIfChanged(section, sectionWidth)
                self:ReflowSection(section)
                local sectionHeight = math.max(1, section:GetHeight() or 1)
                if x > 0 and x + sectionWidth > available then
                    x, y, rowHeight = 0, y + rowHeight + rowGap, 0
                end
                SetAnchorsIfChanged(section, {{"TOPLEFT", page, "TOPLEFT", left + x, -y}})
                x = x + sectionWidth + columnGap
                rowHeight = math.max(rowHeight, sectionHeight)
            else
                if section:GetNumPoints() > 0 then section:ClearAllPoints() end
                section._tbuLayoutAnchorSpec = nil
            end
        end
        local totalHeight = y + rowHeight
        SetHeightIfChanged(page, math.max(1, totalHeight))
        return totalHeight
    end
    local pixel = LayoutPixel(page)
    local preferred = math.max(pixel, FloorGrid(math.max(100, tonumber(opts.sectionWidth) or 590), pixel))
    local columnGap = CeilGrid(math.max(0, tonumber(opts.columnGap) or L.Metrics.PAGE_SECTION_GAP), pixel)
    local rowGap = CeilGrid(math.max(0, tonumber(opts.rowGap) or L.Metrics.PAGE_SECTION_GAP), pixel)
    local left = CeilGrid(math.max(0, tonumber(opts.left) or 0), pixel)
    local right = CeilGrid(math.max(0, tonumber(opts.right) or 0), pixel)
    local top = CeilGrid(math.max(0, tonumber(opts.top) or 0), pixel)
    local available = math.max(pixel, FloorGrid(width - left - right, pixel))
    local maxColumns = tonumber(opts.maxColumns)
    if maxColumns and maxColumns > 0 then
        maxColumns = math.max(1, math.floor(maxColumns))
    else
        maxColumns = nil
    end

    local columnsPerRow = math.max(1, math.floor((available + columnGap) / (preferred + columnGap)))
    if maxColumns then columnsPerRow = math.min(columnsPerRow, maxColumns) end
    local sectionWidth = FloorGrid(math.min(preferred, available), pixel)

    -- Ordered, height-aware bands. The first Section determines the initial
    -- band height. Subsequent Sections stack downward, then move to the next
    -- column if they would exceed the current band boundary. A taller Section
    -- placed at the top of an available column may extend that band height.
    -- Once all columns are used, the following Section starts a new band.
    local bandTop = top
    local bandHeight = 0
    local column = 1
    local columnUsed = 0
    local hasBand = false

    local function NextBand()
        bandTop = bandTop + bandHeight + rowGap
        bandHeight, column, columnUsed = 0, 1, 0
    end

    for _, section in ipairs(sections or {}) do
        if section:IsShown() then
            SetWidthIfChanged(section, sectionWidth)
            self:ReflowSection(section)
            local height = math.max(pixel, CeilGrid(tonumber(section:GetHeight()) or 1, pixel))
            SetHeightIfChanged(section, height)
            if not hasBand then
                hasBand = true
                bandHeight = height
            elseif columnUsed > 0 and columnUsed + rowGap + height > bandHeight then
                if column < columnsPerRow then
                    column = column + 1
                    columnUsed = 0
                else
                    NextBand()
                    bandHeight = height
                end
            end
            if columnUsed == 0 then
                bandHeight = math.max(bandHeight, height)
            end
            local x = left + (column - 1) * (sectionWidth + columnGap)
            local y = bandTop + (columnUsed > 0 and columnUsed + rowGap or 0)
            SetAnchorsIfChanged(section, {{"TOPLEFT", page, "TOPLEFT", x, -y}})
            columnUsed = (columnUsed > 0 and columnUsed + rowGap or 0) + height
        else
            if section:GetNumPoints() > 0 then section:ClearAllPoints() end
            section._tbuLayoutAnchorSpec = nil
        end
    end

    local contentHeight = hasBand and (bandTop + bandHeight) or top
    SetHeightIfChanged(page, math.max(1, contentHeight))
    return contentHeight
end

-- A page uses the same Row -> Column -> Child relationship as the inside of a
-- section. Major sections are therefore not a separate positioning system:
-- each one is simply the child of a one-column page row.
function L:Page(parent, id, opts)
    local page = Node(parent, "page", id, opts or {})
    page.layoutPadding = (opts and opts.padding) or 0
    return page
end

function L:AdoptChild(parent, child, opts)
    if not parent or not child then return child end
    opts = opts or {}
    if child.layoutParent and child.layoutParent.layoutChildren then
        for i = #child.layoutParent.layoutChildren, 1, -1 do
            if child.layoutParent.layoutChildren[i] == child then
                table.remove(child.layoutParent.layoutChildren, i)
                break
            end
        end
    end
    return RegisterChild(parent, child, {
        role = opts.role or child.layoutRole or child.layoutKind or "content",
        gapBefore = opts.gapBefore,
        flow = opts.flow == true,
    })
end

function L:PageSectionRow(page, id, section)
    local row = self:Row(page, id, { gap = 0, padding = 0 })
    local columns = self:Columns(row, 1, { id .. "-column" }, { gap = 0, padding = 0 })
    local column = columns[1]
    self:AdoptChild(column, section, { role = "section" })
    row.layoutSection = section
    row.layoutSectionColumn = column
    return row
end

function L:ReflowPage(page, rows, opts)
    opts = opts or {}
    local width = math.max(1, tonumber(opts.width) or page:GetWidth() or 1)
    SetWidthIfChanged(page, width)

    for _, row in ipairs(rows or {}) do
        SetWidthIfChanged(row, width)
        row:LayoutColumns(width)
        local section = row.layoutSection
        local column = row.layoutSectionColumn
        -- Conditional page Sections control their wrapper Row visibility.
        -- This keeps hidden Sections out of stacking and scroll measurements.
        if section then row:SetShown(section:IsShown()) end
        if section and column and row:IsShown() then
            SetWidthIfChanged(column, width)
            local sectionAnchors = {
                {"TOPLEFT", column, "TOPLEFT", 0, 0},
                {"RIGHT", column, "RIGHT", 0, 0},
            }
            SetAnchorsIfChanged(section, sectionAnchors)
            self:ReflowSection(section)
            local height = math.max(1, section:GetHeight() or 1)
            SetHeightIfChanged(column, height)
            SetHeightIfChanged(row, height)
        end
    end

    return self:StackRows(page, rows, {
        padding = opts.padding or 0,
        gap = opts.gap or L.Metrics.SECTION_GAP,
    })
end

function L:SetContentHeight(node, height)
    node.layoutContentHeight = math.max(0, tonumber(height) or 0)
    SetHeightIfChanged(node, math.max(1, node.layoutContentHeight))
end

function L:MeasureRow(row, bottomPadding)
    local tallest = 0
    for _,col in ipairs(row.layoutColumns or {}) do
        if col:IsShown() then
            tallest = math.max(tallest, col.layoutAllocatedHeight or col.layoutContentHeight or col:GetHeight() or 0)
        end
    end
    -- Symmetric Row padding is included in its measured outer height. Rows
    -- otherwise grow from measured content instead of reserving a tall slot.
    local rowPadding = NormalizeLayoutPadding(row.layoutPadding, 0)
    local natural = tallest + rowPadding.top + rowPadding.bottom + (bottomPadding or 0)
    SetHeightIfChanged(row, math.max(row.layoutMinHeight or L.Metrics.ROW_MIN_HEIGHT, natural))
    return row:GetHeight()
end

-- Reusable placement for persistent footer/other host regions. The region
-- sizes to its measured Row and the Row stays positioned by structural layout,
-- without any control-specific geometry. Host styles may still define a minimum.
function L:LayoutRowInRegion(row, region, opts)
    if not row or not region then return end
    opts = opts or {}
    local insetX = math.max(0, tonumber(opts.insetX) or 0)
    local insetY = opts.insetY
    if insetY == nil then insetY = L.Metrics.ROW_REGION_INSET_Y end
    insetY = math.max(0, tonumber(insetY) or 0)
    local width = math.max(1, region:GetWidth() - (2 * insetX))
    self:LayoutRow(row, width)
    local height = math.max(tonumber(opts.minHeight) or 1, row:GetHeight() + (2 * insetY))
    -- OnSizeChanged may trigger the sizing pass again. Only write changed height.
    SetHeightIfChanged(region, height)
    SetAnchorsIfChanged(row, {{"TOPLEFT", region, "TOPLEFT", insetX, -insetY}})
    return height
end

function L:StackRows(box, rows, opts)
    opts = opts or {}
    local gap = opts.gap or box.layoutGap or DEFAULT_GAP
    local pad = opts.padding
    if pad == nil then pad = box.layoutPadding or 0 end
    local previous
    local total = pad
    for _,row in ipairs(rows) do
      if row:IsShown() then
        if previous then
            SetAnchorsIfChanged(row, {
                {"TOPLEFT", previous, "BOTTOMLEFT", 0, -gap},
                {"RIGHT", box, "RIGHT", -pad, 0},
            })
            total = total + gap
        else
            SetAnchorsIfChanged(row, {
                {"TOPLEFT", box, "TOPLEFT", pad, -pad},
                {"RIGHT", box, "RIGHT", -pad, 0},
            })
        end
        total = total + (row:GetHeight() or 0)
        previous = row
      end
    end
    SetHeightIfChanged(box, math.max(1, total + pad))
    return box:GetHeight()
end


-- Development normalization pass: ordinary sections surrender their direct-child
-- placement to one shared flow. This intentionally exposes legacy nested layout
-- assumptions so they can be replaced by named shared element primitives.
function L:NormalizeOrdinarySection(section)
    -- During the architecture rebuild, normalization now means one thing:
    -- reflow the children explicitly registered with the shared Section.
    -- Unregistered legacy controls are intentionally NOT guessed from frame
    -- enumeration; they remain visibly broken until assigned a Row/Column role.
    return self:ReflowSection(section)
end

function L:Describe(node)
    if not node then return nil end
    return { kind=node.layoutKind, id=node.layoutId, columns=node.layoutColumnCount }
end


-- Stack a major settings section after another section. The child section only
-- needs to know its immediate predecessor, not the page's absolute Y position.
function L:PlaceSectionAfter(section, previous, gap, leftOffset)
    gap = gap or DEFAULT_GAP
    leftOffset = leftOffset or 0
    SetAnchorsIfChanged(section, {{"TOPLEFT", previous, "BOTTOMLEFT", leftOffset, -gap}})
end

-- A named structure can be inspected/addressed without relying on coordinates.
function L:FindChild(parent, id)
    for _, child in ipairs((parent and parent.layoutChildren) or {}) do
        if child.layoutId == id then return child end
    end
    return nil
end


function L:StackSections(parent, sections, opts)
    opts = opts or {}
    local left, right = opts.left or 8, opts.right or 8
    local top, gap = opts.top or 8, opts.gap or L.Metrics.SECTION_GAP
    local bottom = opts.bottom or 0
    local previous
    local total = top
    local count = 0
    for _, section in ipairs(sections or {}) do
        local anchors = {
            {"LEFT", parent, "LEFT", left, 0},
            {"RIGHT", parent, "RIGHT", -right, 0},
        }
        if previous then
            anchors[#anchors + 1] = {"TOP", previous, "BOTTOM", 0, -gap}
            total = total + gap
        else
            anchors[#anchors + 1] = {"TOP", parent, "TOP", 0, -top}
        end
        SetAnchorsIfChanged(section, anchors)
        total = total + (section:GetHeight() or 0)
        count = count + 1
        previous = section
    end
    return math.max(1, total + bottom)
end

function L:PlaceInColumn(frame, column, x, y)
    SetAnchorsIfChanged(frame, {{"TOPLEFT", column, "TOPLEFT", x or 0, -(y or 0)}})
end
