# TreebeardUI
Treebeard UI is a shared settings framework built for TreebeardCreative’s World of Warcraft addons. Other addon authors are welcome to use and adapt it under the MIT License.

## Version and compatibility

Current Retail test candidate: TreebeardUI `0.1.64` / API `1`, paired with TreebeardSandbox `0.1.125`. Treebeard reports the title-bar visuals as "visual really good" and confirms all title positions/width variants, Settings/Debug regressions, and scrollbar behavior passed. Always-visible and hover-revealed title bars use the same anchors and border geometry; visibility timing is their distinction. The candidate also includes per-window surface color/opacity options and scrollbar visibility coalescing with Debug scroll-position preservation. WoW Forever and a second independent consumer remain untested; Retail results do not establish API 1 release readiness.

The title bar hides the edge facing the attached frame: top hides bottom, right hides left, bottom hides top, and left hides right; the main frame supplies the shared edge. Hover title bars do not reserve content space, including when attached at the bottom. Collapsing the right-side title tab anchored at the bottom keeps its controls at that lower attachment point. Treebeard reports the all-position/width, Settings/Debug, and scrollbar regression groups passed in Retail.

Earlier accepted working build: `0.1.25` / API `1`, tested with TreebeardSandbox `0.1.74` in Retail `12.1.5`, build `70688`, interface `120105`. The targeted resize and wrapping checks passed. Section headers wrap within their constrained width and grow to fit; the Recurring Tests page confirmed a one-line title and a deliberately long three-line title without changing neighboring section headers. Navigation, window, and selected-page titles also passed targeted wrapping checks. Notes wrap by default, with `wrap=false` opt-outs; pane headers support `headerWrap=false` / `headerNoteWrap=false`, and page canvas titles/descriptions support `titleWrap=false` / `descriptionWrap=false`. Version `0.1.24` defers footer row reflow until after the current resize/layout pass; the paired resize checks passed. WoW Forever remains unverified.

Earlier accepted Retail checkpoint: TreebeardUI `0.1.20` / API `1`, tested with TreebeardSandbox `0.1.44`. That pair was reported as very clean; the acceptance message did not include a fresh game build string. WoW Forever compatibility remains unverified.

TreebeardUI build versions identify framework updates. `API_VERSION` is reserved for an intentional incompatible change to the consumer-facing contract. API `1` is still in pre-release development; establish a sufficiently complete and stable base before its first public release, then treat it as a very firm compatibility boundary.

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
