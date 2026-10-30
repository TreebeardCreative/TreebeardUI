# TreebeardUI
Treebeard UI is a shared settings framework built for TreebeardCreative’s World of Warcraft addons. Other addon authors are welcome to use and adapt it under the MIT License.

## Version and compatibility

Current candidate build: `0.1.8` / API `1`; it raises the default settings window width/minimum from 801 to 821 UI units so sections retain room beside the scrollbar gutter. The 30-unit scrollbar/content gutter remains unchanged. It includes the pending `0.1.7` Graphite removal and Warm Warcraft default/fallback. TreebeardUI ships Warm Warcraft, Brushfire, and Midnight Flux; consumers choose which built-in presets to offer and may add their own. The `0.1.8` candidate awaits in-client confirmation. The previously accepted test build is `0.1.6` / API `1`. The addon icon has transparent outer corners.

Previously accepted build: TreebeardUI `0.1.1`, with `API_VERSION` still set to `1`. The build version identifies framework updates. The API version is reserved for a deliberate incompatible change to the consumer-facing contract; once API 1 is publicly released, keep it stable unless a breaking change is intended and clearly announced. During pre-release development, potentially breaking changes may remain within API 1 while the contract is still being shaped and tested.

## Theme ownership

TreebeardUI ships Warm Warcraft, Brushfire, and Midnight Flux, with Warm Warcraft as the default fallback. Each consumer owns its theme picker and saved selection: it may expose any subset of the shipped presets and add consumer-specific presets. Consumers should not remove entries from the shared `WindowStyles.Presets` registry, because other addons may use them at the same time.

`SettingsLayout:Row(parent, id, options)` keeps its standard minimum height by default. Consumers may pass `minHeight` for compact text-only or button-only rows; it never lowers the row below its measured content height. Existing callers that omit this option retain the existing layout.

The opt-in compact-row behavior was tested with TreebeardSandbox `0.1.13` in Retail `12.1.5`, build `70575`, interface `120105`. The in-client review passed for the Sandbox command rows and Style Library button-only rows while ordinary control rows retained the standard minimum. The supplied screenshots show the Style Library in Midnight Flux; other theme palettes were not shown in this evidence set. WoW Forever compatibility remains unverified.

## Displaying the TreebeardUI version

TreebeardUI exposes its current build as `UI.VERSION` to a consumer addon. The consumer decides whether and where to display it; TreebeardUI does not force it into window titles or layouts. For example, a consumer can compose a title or passive label like this:

```lua
local versionText = "TreebeardUI v" .. tostring(UI.VERSION)
title:SetText("My Addon Settings (" .. versionText .. ")")
versionLabel:SetText(versionText)
```

Use the same value in a title, navigation pane, debug output, or another consumer-owned location. `UI.VERSION` is also available when using an embedded copy of TreebeardUI.
