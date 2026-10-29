-- TreebeardUI v0.3.1: reusable library, no SavedVariables or slash commands.
local addonName, private = ...
local registryNames = { "TBUIRegistry", "TreebeardUIRegistry", "TumbleManeUIRegistry" }
local registry
for _, name in ipairs(registryNames) do
    local candidate = _G[name]
    if candidate ~= nil then
        if registry and registry ~= candidate then
            error("TreebeardUI: conflicting runtime registries are already loaded")
        end
        registry = candidate
    end
end
-- One active runtime for each exact library build/API pair. Embedded copies
-- share this table while older consumers keep their established registry names.
if type(registry) ~= "table" or registry.PROTOCOL ~= 1 then
    if registry ~= nil then
        error("TreebeardUI: unsupported shared loader registry; refusing to overwrite it")
    end
    registry = { PROTOCOL = 1, runtimes = {} }
end
for _, name in ipairs(registryNames) do _G[name] = registry end
local VERSION, API = "0.3.1", 1
local runtimeKey = tostring(API) .. ":" .. VERSION
local previous = registry.runtimes[runtimeKey]
local standalone = addonName == "TreebeardUI" or addonName == "TumbleManeUI"
if previous then
    -- WoW still executes TOC-listed Lua files for the second embedded copy;
    -- every framework module returns immediately without rebuilding anything.
    private.__TBUIRuntime = previous
    private.__TreebeardUIRuntime = previous
    private.__TBUISkip = true
    private.__TreebeardUISkip = true
    if standalone then
        _G.TreebeardUI = previous
        _G.TumbleManeUI = _G.TumbleManeUI or previous
    end
    return
end
-- Keep embedded framework state apart from the consuming addon's namespace.
-- The standalone addon has its own namespace already.
local TBU = standalone and private or {}
private.__TBUIRuntime = TBU
private.__TreebeardUIRuntime = TBU
private.__TBUISkip = false
private.__TreebeardUISkip = false
TBU.VERSION = VERSION
TBU.API_VERSION = API
TBU.LoadedFromAddon = addonName
registry.runtimes[runtimeKey] = TBU
local legacyAPI1Versions = { ["0.2.28"] = true, ["0.2.29"] = true }
function registry:Acquire(owner, requiredAPI, requiredVersion)
    if type(owner) ~= "string" or owner == "" then return nil end
    if type(requiredAPI) ~= "number" or type(requiredVersion) ~= "string" then return nil end
    local candidate = self.runtimes[tostring(requiredAPI) .. ":" .. requiredVersion]
    if not candidate and requiredAPI == API and legacyAPI1Versions[requiredVersion] then
        candidate = self.runtimes[runtimeKey]
    end
    if candidate and candidate:CheckCompatibility(owner, requiredAPI, requiredVersion) then
        return candidate
    end
    return nil
end
TBU.Constants = { Layout = { SETTINGS_GAP=12, SETTINGS_PADDING=14, DROPDOWN_CLOSE_DELAY=7 } }
-- The standalone library lives at its addon root. Embedded copies default to
-- Libs\\TreebeardUI and may supply __TreebeardUIAssetSubdir before bootstrap.
local subdir = standalone and "" or (private.__TBUIAssetSubdir or private.__TreebeardUIAssetSubdir or "Libs\\TreebeardUI\\")
assert(type(subdir) == "string", "TreebeardUI embedded asset subdir must be a string")
if subdir ~= "" and subdir:sub(-1) ~= "\\" then subdir = subdir .. "\\" end
TBU.AssetRoot = "Interface\\AddOns\\" .. addonName .. "\\" .. subdir .. "Textures\\"
function TBU:GetAssetPath(file) return self.AssetRoot .. tostring(file) end
-- Theme lookup remains library-owned and has no consumer or Retail dependencies.
function TBU:GetThemeColor(key)
    local styles = self.WindowStyles
    local style = styles and styles:Get()
    local value = style and (key == "secondary" and style.interactionGold or style[key])
    if type(value) == "table" then return unpack(value) end
    return 0.85, 0.67, 0.33, 1
end
local providers = {}
function TBU:RegisterConsumer(owner, opts)
    assert(type(owner)=="string" and owner~="", "consumer owner ID required")
    assert(type(opts)=="table" and type(opts.windowState)=="function", "windowState provider required")
    providers[owner] = { state=opts.windowState, logger=opts.logger }
end
function TBU:GetWindowState(owner)
    local provider = providers[owner]
    if not provider then return nil end
    local ok, value = pcall(provider.state)
    return ok and type(value)=="table" and value or nil
end
function TBU:Log(owner, message)
    local provider = providers[owner]
    if provider and type(provider.logger)=="function" then
        pcall(provider.logger, tostring(message))
    end
end
-- Exact build compatibility is deliberately checked by each consuming addon.
-- The public API contract number changes only on incompatible API changes;
 -- the build version detects even same-contract library/consumer mismatches.
local warnedConsumers = {}
function TBU:CheckCompatibility(owner, requiredAPI, requiredVersion)
    if type(owner) ~= "string" or owner == "" then return false end
    local apiOK = type(requiredAPI) == "number" and self.API_VERSION == requiredAPI
    local versionOK = type(requiredVersion) == "string"
        and (self.VERSION == requiredVersion
            or (apiOK and legacyAPI1Versions[requiredVersion] == true))
    if apiOK and versionOK then return true end
    if not warnedConsumers[owner] then
        warnedConsumers[owner] = true
        local message = string.format(
            "%s requires TreebeardUI API %s / build %s; installed API %s / build %s. Addon UI disabled.",
            owner, tostring(requiredAPI), tostring(requiredVersion),
            tostring(self.API_VERSION), tostring(self.VERSION))
        if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4444" .. message .. "|r")
        elseif print then
            print(message)
        end
    end
    return false
end

-- Weak control references keep UI refresh independent of consuming addon state.
-- Each control reads its own consumer-supplied getter when refreshed.
local refreshControls = setmetatable({}, {__mode="k"})
function TBU:RegisterRefreshControl(control, refresh)
    if control and type(refresh) == "function" then refreshControls[control] = refresh end
end
function TBU:RefreshAll()
    for control, refresh in pairs(refreshControls) do
        local ok, err = pcall(refresh, control)
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end
end

-- Legacy/global entrypoint is reserved for the standalone addon; bundled
-- copies are accessed through the exact-version registry or addon namespace.
if standalone then
    _G.TreebeardUI = TBU
    -- Temporary global alias for installed consumers still using the former product name.
    _G.TumbleManeUI = _G.TumbleManeUI or TBU
end