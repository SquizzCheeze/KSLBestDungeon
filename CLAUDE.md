# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A World of Warcraft retail addon (Lua 5.1 + FrameXML) that ranks Mythic+ dungeons by how many
KeystoneLoot favorites they contain. It has no standalone UI: it injects a **"Best Dungeons" tab**
into KeystoneLoot's existing frame.

Live install path is also the source path: `C:\World of Warcraft\_retail_\Interface\AddOns\KSLBestDungeon`.
The dependency addon sits next door at `../KeystoneLoot` — read it directly when you need to confirm an API.

## Build / test / run

There is no build step, package manager, linter, or test suite. The workflow is:

1. Edit the `.lua`/`.xml`/`.toc` files in place.
2. In-game: `/reload` (or restart WoW if the `.toc` file list changed — `/reload` does not pick up new files).
3. `/kslbd` opens KeystoneLoot and selects the Best Dungeons tab. `/kslbd notes` re-opens the release notes,
   `/kslbd welcome` the first-run greeting.

There is no Lua interpreter on this machine. For a syntax check, `luaparse` (npm) works in `luaVersion: '5.2'`
mode; its 5.1 mode wrongly rejects `break;` followed by `end`, which real Lua 5.1 accepts.

Static analysis is via the VS Code Lua LSP with the `ketho.wow-api` annotations (`.vscode/settings.json`);
`mcp__ide__getDiagnostics` is the closest thing to a lint command. New WoW globals that the annotations
don't cover must be added to `Lua.diagnostics.globals` there or they show as undefined.

Debug slash commands (all in `KSLBestDungeon.lua`):
- `/kslbd debug` — dumps the raw KeystoneLoot favorites table for the selected character.
- `/kslbd debugui` / `/kslbd dropdown` — dumps tab id, frame refs, toolbar visibility, current tab.
- `/kslbd show` — force-shows the frame, our tab, and the toolbar.
- `/kslbd reset` — wipes `KSLBestDungeonDB` and reloads.

## Releasing

Repo: https://github.com/SquizzCheeze/KSLBestDungeon. Releases are tag-driven. Pushing a `v*` tag runs
`.github/workflows/release.yml`, which packages the addon with BigWigsMods/packager, uploads it to
CurseForge (project `1599575`, read from `## X-Curse-Project-ID` in the TOC) and attaches the zip to a
GitHub release. Ordinary pushes to `main` publish nothing. Running the workflow manually from the Actions
tab is a dry run: it builds the zip and uploads nothing.

- Bump `## Version` in the TOC, then `git tag -a v1.X -m "V1.X"` and `git push origin v1.X`.
- Add a `RELEASE_NOTES["<version>"]` entry in `welcome.lua`: a few player-facing highlights, NOT a copy
  of the changelog. It is keyed by the TOC version string. A missing entry is not fatal (the update note
  still appears, without bullets), which is exactly why it is easy to forget.
- `changelog.txt` is uploaded **verbatim** as that release's CurseForge notes, so it must hold only the
  version being released. Older sections move to `CHANGELOG-ARCHIVE.txt`, which `.pkgmeta` ignores so it
  never ships. Leaving history in `changelog.txt` makes every release repost the entire backlog.
- What ships is controlled by the `ignore:` list in `.pkgmeta`, not by `.gitignore`. Dev files
  (`CLAUDE.md`, `README.md`, `.vscode`, `.github`, `.claude`, the changelog archive) are excluded there;
  `LICENSE` and `changelog.txt` deliberately are not.
- The CurseForge token must be saved as repo secret `CF_API_TOKEN` (or `CF_API_KEY`). A missing secret
  does not fail the job; the upload is skipped silently. The dry run prints the secret lengths to check.

SavedVariables (useful for inspecting real data without launching the game):
- `WTF/Account/<ACCOUNT>/SavedVariables/KSLBestDungeon.lua` and `KeystoneLoot.lua`
- `WTF/Account/<ACCOUNT>/<Realm>/<Char>/SavedVariables/KSLBestDungeon.lua`

## Load order (`KSLBestDungeon.toc`)

`ui/main_frame.xml` → `KSLBestDungeon.lua` → `ui/main_frame.lua` → `welcome.lua`.

The XML must load first because it declares `KSLBestDungeonEntryTemplate`. But `ui/main_frame.lua` is
loaded after it, so the mixin tables it defines (`KSLBestDungeonRankingsFrameMixin`,
`KSLBestDungeonEntryMixin`) do not exist while
`KSLBestDungeon.lua` is being parsed. This is safe only because `KSLBestDungeon.lua` reads them lazily
inside `HookIntoKeystoneLoot()`, which runs at `PLAYER_LOGIN`. Don't move mixin access to file scope.

`KSLBestDungeonEntryTemplate` is the only template in the XML. The rankings frame, its inset, and its
scrollframe are built programmatically in `HookIntoKeystoneLoot()` rather than from a template.

## Architecture

Three layers, split by file:

**`KSLBestDungeon.lua` — data + integration.** Reads KeystoneLoot's SavedVariables directly
(`KeystoneLootDB.favorites`, `KeystoneLootCharDB.ui/.filters`), scores dungeons, and owns settings in
`KSLBestDungeonDB.settings`. Everything is hung off the `Addon` table, which is also published as the
`_G.KSLBestDungeon` global.

**`ui/main_frame.lua` — all UI mixins.** Share/chat export (with the whisper StaticPopup), the toolbar,
the rankings list, and per-dungeon entry rows.

**`welcome.lua` — first-run greeting and per-update release notes.** Ported from Avatar Continued. It
shares `_G.SquizzNotesQueue` with SquizzFrames, Squizzumables, SquizzTalents and Avatar so that notes
from several addons updated at the same login queue instead of drawing on top of each other. **The
`NotesQueue`/`PresentNotes`/`OnNotesHidden` block must stay byte-identical to the other addons'** — the
table's shape is an interface between them. New install vs upgrade is decided by whether
`KSLBestDungeonDB` existed at our `ADDON_LOADED`; any later and `GetSettings()` has already created it.
`lastSeenVersion` lives on the `KSLBestDungeonDB` root, beside `settings`.

**`ui/main_frame.xml`** — only `KSLBestDungeonEntryTemplate` matters.

### How the tab gets injected

`HookIntoKeystoneLoot()` in `KSLBestDungeon.lua` is the crux of the addon. It is retried every 0.5s via
`TryHook()` until KeystoneLoot's tab system exists, because KSL's own init is asynchronous — it checks
both `KSLFrame.TabSystem` (XML-declared) *and* `KSLFrame.tabSystem` (set by `SetTabSystem()`), since the
former exists before the latter. Idempotency is guarded by `KSLFrame.kslBestDungeonTabId`.

It then:
- Creates a plain `Frame` child of `KeystoneLootFrame`, copies `KSLBestDungeonRankingsFrameMixin` onto
  it key by key (not a real template mixin), and builds Inset/ScrollFrame/Container by hand.
- Registers via `KSLFrame:AddNamedTab("Best Dungeons", rankingsFrame)` (Blizzard's `TabSystemOwnerMixin`).
  **TabSystem shows/hides our frame and its children automatically** — never manually `Show()`/`Hide()`
  the rankings frame or the toolbar, or the tab switching breaks.
- Wraps `KSLFrame`'s `OnShow` script and `hooksecurefunc`s `KSLFrame:SetTab` to call `Refresh()` when our
  tab becomes active.

Two consequences of borrowing KSL's frame that are easy to trip on:
- KSL's `SetTab` calls `GetTabName(tabId)`, which doesn't know our tab and falls back to `"dungeons"`.
  That's load-bearing: it means `Upgrade:GetCurrentTrack()` still resolves the dungeon upgrade track
  while our tab is open, so item links scale to the right ilvl.
- KSL's `RefreshSize(tabId)` resizes the whole KSL frame to our frame's size when our tab is selected.
  So the rankings frame must **cover the whole window with an explicit size**, like KSL's own tab frames
  (TOPLEFT anchor only; content from -60 down to +24 above KSL's footer text). It was once anchored at
  `-60` and `BOTTOMRIGHT`, so its size derived from the window, and every tab selection shrank the window
  by 60px. `SyncSizeToKSL()` copies `KSLFrame.DungeonsFrame`'s size on every show (so tab switches do
  not jump and wide mode carries over) and sizes the window to match. Never give it a second anchor.
- The scroll frame stops 26px short of the inset's right edge: `UIPanelScrollFrameTemplate` hangs its
  scrollbar off the scroll frame's right side, which is outside the window if the scroll frame fills
  the inset. The container's width follows the scroll frame (`OnSizeChanged`), which triggers a
  `Refresh()` because icon wrapping depends on it.

### Toolbar

`RankingsFrameMixin:CreateToolbar()` (called from `Init()`) builds two rows in the 58px below KSL's
60px header; `HookIntoKeystoneLoot()` starts the Inset below that. Row 1 is the context line (whose
favorites, which specs), **Defaults** (`Addon:ResetSettings()`, no reload) and **Share**; row 2 is Sort,
All specs, Weight by tier, Min items. Every control has a tooltip — keep it that way, the point of the
toolbar is that nothing is unexplained. `UpdateToolbar()` runs on every `Refresh()` and re-syncs the
checkboxes and dropdown texts from settings, so anything that changes settings only needs to call
`Refresh()`. Width is tight at KSL's default 500px frame: check any new control fits before adding it.

### Data flow

```
KeystoneLootDB.favorites[characterKey][sourceId][specId][itemId] = { tier, bonusIds, gems, enchant }
  → GetAllFavorites()      groups by challengeModeId, resolves names via C_ChallengeMode.GetMapUIInfo
                           and de-duplicates by itemId: an item favorited on several specs counts
                           ONCE, at its highest TIER_RANK (BiS > Catalyst > Must > Nice > Transmog);
                           and drops items outside KSL's Slot filter (GetSlotFilter, below)
  → CalculateDungeonScore() sums TIER_WEIGHT (BiS 100 / Catalyst 100 / Must 50 / Nice 10 / Transmog 1)
  → Addon:GetRankedDungeons() filters by minFavorites, sorts by settings.sortBy
  → RankingsFrameMixin:Refresh() rebuilds the list
```

**KSL's Slot filter.** The ranking follows the Slot dropdown in KSL's header. `GetSlotFilter()` in the core
mirrors KSL's `Query:GetDungeonItems` (`modules/query.lua`): Favorites (-1) = everything; All slots (-2) =
everything minus slot 14 (Other) when `settings.hideOtherItems`; otherwise one `filters.slotId`, or
any ticked `filters.slotIds` when `settings.multiSlotFilter`; `filters.weaponTypes` narrows main-hand
(slot 10) weapons only. Each item's slot comes from `KeystoneLootAPI:GetItemInfo(itemId).slotId`, KSL's own
data. KSL's filter state is **read only** -- never write `KeystoneLootCharDB.filters`: that bypasses KSL's DB
observers and leaves its dropdown out of step, which is why the empty-list message for it has no button.
If KSL changes its filter semantics, update `GetSlotFilter`/`ItemPassesSlotFilter` to match.

`sourceId` keys are filtered with `type(sourceId) == "number" and sourceId > 0 and sourceId < 1000` —
that heuristic is how dungeon `challengeModeId`s are separated from raid/other source keys. Dungeon
names come from the live WoW API, never from a hardcoded list, so the addon follows the current season
automatically.

Tier constants (`TIER_NICE=1, TIER_MUST=2, TIER_BIS=3, TIER_TRANSMOG=4, TIER_CATALYST=5`) mirror
KeystoneLoot's (`../KeystoneLoot/modules/favorites.lua`) and are **duplicated** in both
`KSLBestDungeon.lua` and `ui/main_frame.lua`. Change both together. The weights are NOT duplicated: the UI
reads them through `Addon:GetTierWeight(tier, weighted)`, so `TIER_WEIGHT` in the core is the only copy. KSL adds tiers between releases,
so the counter in `GetAllFavorites()` and the scoring chain in `CalculateDungeonScore()` both fall
back gracefully on an unrecognised tier rather than indexing a nil.

### Refresh strategy

`RankingsFrameMixin:Init()` subscribes to `KeystoneLootAPI`'s `FAVORITES_CHANGED` event, which covers
favorites being added/removed/retiered/imported but *not* the character or spec filter changing. So
there is also a **1-second `C_Timer.NewTicker` polling fallback** that diffs `GetFavoritesHash()` and
refreshes on change. That hash is `Addon:GetFilterStateKey()` (selected character + resolved
class/spec + `showAllSpecs` + KSL's Slot filter state) followed by a sorted concat of `sourceId:specId:itemId:tier`. **Both
halves matter**: changing spec never touches the favorites tables, so without the state key the list
silently stays on the previous spec. If you change the favorites schema or add another input to the
ranking, update `GetFavoritesHash()` too or live updates stop.

`Refresh()` records the hash it rendered for (on every path, including the early "no character" /
"no favorites" returns) so the ticker does not immediately re-fire.

An empty list always says **why**, via `ShowEmptyReason(candidates)`, most specific cause first:
Min items hid every dungeon (`GetRankedDungeons()`'s second return counts dungeons before that filter),
then this spec has none but others do (`Addon:HasAnyDungeonFavorites()`), then nothing favorited yet.
Each offers its fix as a button. The message frame is parented to the rankings frame, not the scroll
container, because `Refresh()` detaches every container child.

The mixin is copied key-by-key onto a plain `CreateFrame()` frame, so **script handlers are not
wired up automatically the way an XML template mixin's would be** — `Init()` calls `SetScript` for
`OnShow`/`OnHide` explicitly. `OnHide` cancels the ticker and `OnShow` recreates it via
`StartPolling()`; if you add a handler to the mixin, register it there too or it will never fire.

`Refresh()` fully tears down and rebuilds every row (`child:Hide(); child:SetParent(nil)`) — there is no
frame pool. Rows are `KSLBestDungeonEntryTemplate` frames anchored to both sides of the container, so
they are as wide as the list (the XML's 580px is overridden). A fixed 140px text column truncates with
"..."; icons fill the rest and wrap onto more lines, growing the row from its 70px minimum. There is no
icon cap. `Init()` takes the row width explicitly because the anchors may not have resolved yet.

### What is reachable in KeystoneLoot — and what is not

**`_G.KeystoneLoot` does not exist.** KSL keeps `DB`, `Upgrade`, `Favorites`, `Query`, `Character` and
`UpgradeTracks` on the addon-private table from `local AddonName, KeystoneLoot = ...`, and the only
global it publishes is `_G.KeystoneLootAPI` (`modules/api.lua`). Any `local KL = _G.KeystoneLoot` is
silently `nil` and every guarded block behind it dead — this already caused one shipped bug where all
items rendered at base ilvl. Verify with `grep -rn "_G\." ../KeystoneLoot --include="*.lua"` before
assuming a module is reachable.

What that leaves:

- **Item levels.** `KeystoneLootAPI` has no link builder and no upgrade-track accessor, so we cannot
  compute the selected ilvl ourselves without duplicating KSL's season-specific `UpgradeTracks` plus its
  900-entry `ITEM_LEVEL_BONUS_IDS` table. Instead, item icons are created from KSL's **global virtual
  template** `KeystoneLootLootIconButtonTemplate` and initialised with `btn:Init({ itemId = id })`. Its
  `OnEnter`/`OnClick` close over KSL's private `Upgrade` module, so the tooltip, quality colour, chat
  link, and the right-click set-tier menu are all produced inside KSL and track its dropdown
  automatically. Reuse that template rather than hand-rolling item buttons or links.
  Two adjustments are applied after `Init()`: undo KSL's stat-highlight desaturation/alpha (everything
  in our list is already a favorite), and replace `UpdateFavoriteIcon` on the button instance
  with `ShowFavoritedTier`, because KSL's corner tier icon otherwise shows the tier for the spec
  currently filtered in KSL (and KSL redraws it on every OnEnter/OnLeave), while our list can span
  specs. KSL's quality border (`Content.IconBorder`) is left alone. An earlier version hid it for
  tier-coloured `loottoast-itemborder-*` atlas borders, which do not draw on 12.x -- icons showed no
  border at all.
- **Tiers are shown only with KSL's tier icons** (`assets/tier_*.blp`, paths in `TIER_TEXTURE`):
  item corners, row summary, score key, tooltips. Don't reintroduce per-tier text colours; a second
  scheme is what made the old UI unexplainable.
- **Favorites events.** Use `KeystoneLootAPI:RegisterCallback(API.Event.FAVORITES_CHANGED, cb, owner)`.
  `KeystoneLoot.DB:AddObserver` is not reachable.
- **Read-only state.** `KeystoneLootDB` / `KeystoneLootCharDB` are ordinary SavedVariables globals and
  can be read directly (that is how favorites and the selected character are obtained).
- **Character keys are `Realm-Name-ClassId`** (e.g. `Illidan-Squizz-3`, KSL's `Character:GetKey()`), NOT
  `Name-Realm`. Parse from the right, `^(.*)%-(.-)%-(%d+)$`, because realms can contain hyphens
  (Azjol-Nerub). The trailing number is the selected character's numeric class ID.

`Addon:GetItemInfo`/`GetItemInfoFromLink` in the core file are thin `C_Item.GetItemInfo` wrappers that
return `nil` until the client has cached the item.

## Conventions

Match the existing style: semicolon line terminators, parenthesised conditions (`if (x) then`),
4-space indent, `|cffRRGGBB...|r` colour escapes inline in strings, addon prefix `|cff9d5db8KSLBestDungeon|r`
on every `print`. `Addon.L` is a passthrough metatable stub — localisation is scaffolded but unused.
