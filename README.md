# TreebeardUI
Treebeard UI is a shared settings framework built for TreebeardCreative’s World of Warcraft addons. Other addon authors are welcome to use and adapt it under the MIT License.

## Version and compatibility

Latest tested Forever pair: TreebeardUI `0.2.14` / API `1` with TreebeardSandbox `0.2.36`, on WoW Forever `1.60.1`, build `70888`, interface `16001`. Treebeard reports the focused navigation/load, controls, scroll/resize, rounded-border rendering, and rounded-border content-flow checks passed. These are scoped in-game checks, not full release certification; API 1 is still in pre-release development, and testing with a second independent consumer remains outstanding.

Latest tested Retail pair: TreebeardUI `0.1.75` / API `1` with TreebeardSandbox `0.1.145`, on Retail `12.1.5`, build `70783`, interface `120105`. Treebeard reports the focused minimized-body test passed: the Consumer Options Frame title bar draws its shared seam edge only while the body is minimized. The preceding `.141/.75` checks covered startup after removing `Compatibility/`, Settings and Style Library, Custom Border Tests, and showing/moving/resizing the test frame. These are scoped Retail checks and do not establish current-build Retail compatibility.

The Retail TOC targets interface `120105`; `TreebeardUI_Forever.toc` targets `16001`. Both load the same framework implementation and shared `BackdropTemplate` frame factory from `Bootstrap.lua`; client-specific behavior should be added only when a verified difference requires it.

`WindowFrame:Create` accepts `frameHeader={position="top", visibility="always", width={mode="percent", value=100}}`; omitted position, visibility, and width use those defaults when a frame header is requested. Consumers change placement through `frame:SetFrameHeaderPosition(position, anchor)`, width through `frame:SetFrameHeaderWidth(width, anchor)`, and visibility through `frame:SetFrameHeaderVisibility(mode)`. A bare frame has no frame header. `SettingsLayout:EnableFrameLayout(frame, options)` lets an existing frame body flow registered content directly in creation order; add content with `SettingsLayout:AddContent(frame, content, options)` or create layout nodes under the frame. New content and frame resizing schedule reflow; call `frame:RequestContentLayout()` after changing content that affects its measured size. `SettingsLayout:Container(parent, id, options)` remains available as a nested layout root, and pages remain the host's selected views.

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
