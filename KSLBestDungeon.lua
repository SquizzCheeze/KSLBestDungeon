local AddonName, KSLBestDungeon = ...;

KSLBestDungeon = KSLBestDungeon or {};
local Addon = KSLBestDungeon;

Addon.L = setmetatable({}, {
    __index = function(t, k)
        return k;
    end,
    __newindex = function(t, k, v)
        rawset(t, k, v);
    end
});

-- Tier constants (matching KeystoneLoot)
local TIER_NICE = 1;
local TIER_MUST = 2;
local TIER_BIS = 3;
local TIER_TRANSMOG = 4;
local TIER_CATALYST = 5;

local TIER_WEIGHT = {
    [TIER_BIS] = 100,
    [TIER_MUST] = 50,
    [TIER_NICE] = 10,
    -- KSL only allows Catalyst on the five tier-set slots, so a Catalyst favorite is
    -- a drop you mean to turn into a set piece -- effectively Best in Slot.
    [TIER_CATALYST] = 100,
    [TIER_TRANSMOG] = 1,
};

-- Which tier wins when one item is favorited on several specs at different tiers:
-- the higher rank. Independent of the "Weight by tier" setting, so switching it never
-- changes which tier an item is shown and counted at. BiS beats Catalyst although they
-- weigh the same, since a straight BiS drop needs no catalyst charge. Unknown tiers
-- from a newer KeystoneLoot rank 0 and lose to every known one.
local TIER_RANK = {
    [TIER_BIS] = 5,
    [TIER_CATALYST] = 4,
    [TIER_MUST] = 3,
    [TIER_NICE] = 2,
    [TIER_TRANSMOG] = 1,
};

-- What one favorite of this tier adds to a dungeon's score under the current
-- settings. The UI's score key and tooltips read weights from here, so this table
-- stays the only copy of them.
function Addon:GetTierWeight(tier, weighted)
    if (not weighted) then return 1; end
    return TIER_WEIGHT[tier] or 1;
end

-- Default settings
local DEFAULT_SETTINGS = {
    minFavorites = 1,
    weightByTier = true,
    sortBy = "score", -- "score", "count", "bis", "name"
    showAllSpecs = true,
};

local function GetSettings()
    if (not KSLBestDungeonDB) then
        KSLBestDungeonDB = {};
    end
    if (not KSLBestDungeonDB.settings) then
        KSLBestDungeonDB.settings = CopyTable(DEFAULT_SETTINGS);
    end
    return KSLBestDungeonDB.settings;
end

local function GetSetting(key)
    return GetSettings()[key];
end

local function SetSetting(key, value)
    local settings = GetSettings();
    settings[key] = value;
end

-- Expose settings functions
function Addon:GetSettings()
    return GetSettings();
end

function Addon:GetSetting(key)
    return GetSetting(key);
end

function Addon:SetSetting(key, value)
    SetSetting(key, value);
end

-- Put the ranking options back to their defaults in place. Unlike /kslbd reset this
-- keeps the rest of KSLBestDungeonDB and needs no reload.
function Addon:ResetSettings()
    if (not KSLBestDungeonDB) then
        KSLBestDungeonDB = {};
    end
    KSLBestDungeonDB.settings = CopyTable(DEFAULT_SETTINGS);
end

-- The class and spec the ranking is for: the character selected in KSL (which may
-- be an alt, not the one logged in), and the spec picked in KSL's class menu.
--
-- Mirrors KSL's own GetFavoritesListSpecId (modules/query.lua): the class menu's spec
-- only counts when that menu is showing the selected character's class; otherwise
-- the spec is 0, meaning all specs. KSL's character picker sets exactly that when you
-- switch to an alt (filters.classId = alt's class, filters.specId = 0).
--
-- This used to treat spec 0 as "unknown" and fall back to the LOGGED-IN character's
-- class and spec, so selecting a Paladin alt from a Hunter ranked "Beast Mastery
-- only" and found nothing with All specs off.
--
-- Returns classId, specId; specId 0 = all specs. nil, nil with no character selected.
local function GetCurrentCharacterInfo()
    local characterKey = KeystoneLootCharDB and KeystoneLootCharDB.ui and KeystoneLootCharDB.ui.selectedCharacterKey;
    if (not characterKey) then
        return nil, nil;
    end

    -- Key is "Realm-Name-ClassId"; parsed from the right since realms can contain hyphens.
    local classId = tonumber(characterKey:match("%-(%d+)$"));

    local filters = KeystoneLootCharDB.filters;
    local filterClassId = filters and filters.classId;
    local filterSpecId = filters and filters.specId;

    if (classId and filterClassId == classId and filterSpecId and filterSpecId ~= 0) then
        return classId, filterSpecId;
    end

    return classId, 0;
end

-- ============================================================
-- KeystoneLoot's Slot filter
--
-- The ranking follows the Slot dropdown in KSL's header, mirroring KSL's own
-- Query:GetDungeonItems (modules/query.lua) so both tabs agree on what is included:
--   Favorites (-1)       everything
--   All slots (-2)       everything, minus the Other slot if KSL's hideOtherItems is on
--   one slot / several   items in that slot, or any ticked slot (multiSlotFilter)
--   weapon types         narrow main-hand weapons only, when any are ticked
-- An item's slot is KSL's own, from KeystoneLootAPI:GetItemInfo(). Items KSL does not
-- know (custom items) have no slot and so only pass Favorites / All slots, as in KSL.
--
-- KSL's filter state is read, never written: writing KeystoneLootCharDB directly
-- would bypass KSL's DB observers and leave its dropdown out of step.
-- ============================================================
local SLOT_FAVORITES = -1;
local SLOT_ALL = -2;
local SLOT_OTHER = 14;     -- Enum.ItemSlotFilterType.Other
local SLOT_MAIN_HAND = 10; -- Enum.ItemSlotFilterType.MainHand, KSL's WEAPON_SLOT

-- Slot names by KSL slotId + 1, in the order of KSL's Slot dropdown.
local SLOT_NAMES = {
    INVTYPE_HEAD, INVTYPE_NECK, INVTYPE_SHOULDER, INVTYPE_CLOAK, INVTYPE_CHEST,
    INVTYPE_WRIST, INVTYPE_HAND, INVTYPE_WAIST, INVTYPE_LEGS, INVTYPE_FEET,
    INVTYPE_WEAPONMAINHAND, INVTYPE_WEAPONOFFHAND, INVTYPE_FINGER, INVTYPE_TRINKET,
    EJ_LOOT_SLOT_FILTER_OTHER,
};

-- As KSL's RANGED_WEAPON_SUBCLASSES: ranged weapons count as two-handed.
local RANGED_WEAPON_SUBCLASSES = {
    [Enum.ItemWeaponSubclass.Bows] = true,
    [Enum.ItemWeaponSubclass.Guns] = true,
    [Enum.ItemWeaponSubclass.Crossbow] = true,
};

-- As KSL's Query:GetWeaponType.
local function GetWeaponType(itemId)
    local _, _, _, equipLoc, _, _, subclassId = C_Item.GetItemInfoInstant(itemId);
    if (subclassId == Enum.ItemWeaponSubclass.Dagger) then
        return "dagger";
    end
    if (equipLoc == "INVTYPE_2HWEAPON" or RANGED_WEAPON_SUBCLASSES[subclassId]) then
        return "twoHand";
    end
    return "oneHand";
end

-- The active Slot filter, or nil when everything is included.
-- { slotId = n } | { slotIds = { [n] = true } } | { hideOther = true }, plus weaponTypes.
local function GetSlotFilter()
    local filters = KeystoneLootCharDB and KeystoneLootCharDB.filters;
    local settings = KeystoneLootDB and KeystoneLootDB.settings or {};
    local slotId = filters and filters.slotId;

    if (slotId == nil or slotId == SLOT_FAVORITES) then
        return nil;
    end

    local weaponTypes = filters.weaponTypes;
    if (type(weaponTypes) ~= "table" or not next(weaponTypes)) then
        weaponTypes = nil;
    end

    if (slotId == SLOT_ALL) then
        if (settings.hideOtherItems) then
            return { hideOther = true, weaponTypes = weaponTypes };
        end
        return weaponTypes and { weaponTypes = weaponTypes } or nil;
    end

    if (settings.multiSlotFilter and type(filters.slotIds) == "table") then
        for _, selected in pairs(filters.slotIds) do
            if (selected) then
                return { slotIds = filters.slotIds, weaponTypes = weaponTypes };
            end
        end
    end

    return { slotId = slotId, weaponTypes = weaponTypes };
end

local function ItemPassesSlotFilter(itemId, filter)
    if (not filter) then return true; end

    local API = _G.KeystoneLootAPI;
    local info = API and API.GetItemInfo and API:GetItemInfo(itemId);
    local itemSlot = info and info.slotId;

    local slotMatches;
    if (filter.slotIds) then
        slotMatches = itemSlot ~= nil and filter.slotIds[itemSlot] == true;
    elseif (filter.slotId) then
        slotMatches = itemSlot == filter.slotId;
    else
        slotMatches = not (filter.hideOther and itemSlot == SLOT_OTHER);
    end
    if (not slotMatches) then return false; end

    if (filter.weaponTypes and itemSlot == SLOT_MAIN_HAND) then
        return filter.weaponTypes[GetWeaponType(itemId)] == true;
    end
    return true;
end

function Addon:IsSlotFilterActive()
    return GetSlotFilter() ~= nil;
end

-- Short description of the active Slot filter for the context line ("Trinket",
-- "Head + 2"), or nil when every slot is included.
function Addon:GetSlotFilterLabel()
    local filter = GetSlotFilter();
    if (not filter) then return nil; end

    if (filter.slotId) then
        return SLOT_NAMES[filter.slotId + 1] or "one slot";
    end

    if (filter.slotIds) then
        local first, count;
        count = 0;
        for slot = 0, #SLOT_NAMES - 1 do
            if (filter.slotIds[slot]) then
                count = count + 1;
                first = first or SLOT_NAMES[slot + 1];
            end
        end
        if (count <= 1) then return first; end
        return string.format("%s + %d", first or "?", count - 1);
    end

    -- All slots, narrowed only by Other items being hidden and/or weapon types.
    return nil;
end

-- For the poll hash: the Slot filter changes in KSL's header without touching the
-- favorites tables, so it has to be part of the state key like the spec is.
local function GetSlotFilterStateKey()
    local filters = KeystoneLootCharDB and KeystoneLootCharDB.filters or {};
    local settings = KeystoneLootDB and KeystoneLootDB.settings or {};
    local parts = { tostring(filters.slotId), tostring(settings.multiSlotFilter), tostring(settings.hideOtherItems) };
    for _, list in ipairs({ filters.slotIds, filters.weaponTypes }) do
        local keys = {};
        if (type(list) == "table") then
            for k, v in pairs(list) do
                if (v) then table.insert(keys, tostring(k)); end
            end
        end
        table.sort(keys);
        table.insert(parts, table.concat(keys, "+"));
    end
    return table.concat(parts, "/");
end

-- Who and what the ranking is for, for the toolbar's context line.
function Addon:GetRankingContext()
    local characterKey = KeystoneLootCharDB and KeystoneLootCharDB.ui and KeystoneLootCharDB.ui.selectedCharacterKey;
    local classId, specId = GetCurrentCharacterInfo();
    return characterKey, classId, specId;
end

-- Identity of the filter the rankings are computed for. Changing character or spec in
-- KeystoneLoot (or changing spec in-game, when KSL has no spec filter set) never touches
-- the favorites tables, so the poll hash in ui/main_frame.lua has to fold this in or the
-- list stays on the previous spec until a /reload.
function Addon:GetFilterStateKey()
    local characterKey = KeystoneLootCharDB and KeystoneLootCharDB.ui and KeystoneLootCharDB.ui.selectedCharacterKey;
    local classId, specId = GetCurrentCharacterInfo();
    return string.format("%s:%s:%s:%s:%s", tostring(characterKey), tostring(classId), tostring(specId),
        tostring(GetSetting("showAllSpecs")), GetSlotFilterStateKey());
end

-- Get all favorites for the current character/spec across all dungeons
local function GetAllFavorites()
    local classId, specId = GetCurrentCharacterInfo();
    if (not classId or not specId) then
        return {};
    end

    local characterKey = KeystoneLootCharDB.ui and KeystoneLootCharDB.ui.selectedCharacterKey;
    if (not characterKey) then
        return {};
    end

    local favorites = KeystoneLootDB and KeystoneLootDB.favorites;
    if (not favorites or not favorites[characterKey]) then
        return {};
    end

    local result = {};
    local slotFilter = GetSlotFilter();

    for sourceId, sourceData in pairs(favorites[characterKey]) do
        -- Only process dungeon sources (challengeModeId numbers)
        if (type(sourceId) == "number" and sourceId > 0 and sourceId < 1000) then
            local challengeModeId = sourceId;

            -- Get dungeon name from WoW API (dynamic, current season)
            local name = C_ChallengeMode.GetMapUIInfo(challengeModeId);
            local dungeonName = name or ("Dungeon " .. challengeModeId);

            for currentSpecId, specData in pairs(sourceData) do
                -- If showAllSpecs is false, only include the spec picked in KSL -- unless
                -- KSL itself is on all specs (0), e.g. just after switching to an alt.
                if (GetSetting("showAllSpecs") or specId == 0 or currentSpecId == specId) then
                    for itemId, itemInfo in pairs(specData) do
                        local tier = itemInfo.tier or TIER_MUST;

                        -- KSL's Slot filter; see GetSlotFilter(). Checked before the
                        -- dungeon entry is created, so a dungeon with no favorite in the
                        -- filtered slots does not appear at all.
                        if (ItemPassesSlotFilter(itemId, slotFilter)) then
                            if (not result[challengeModeId]) then
                                result[challengeModeId] = {
                                    dungeon = {
                                        challengeModeId = challengeModeId,
                                        name = dungeonName,
                                    },
                                    items = {},
                                    itemsById = {},
                                    tiers = { [TIER_BIS] = 0, [TIER_MUST] = 0, [TIER_NICE] = 0, [TIER_CATALYST] = 0, [TIER_TRANSMOG] = 0 },
                                };
                            end

                            local dungeon = result[challengeModeId];
                            -- Tolerate tiers KeystoneLoot adds that we do not know about yet
                            local tiers = dungeon.tiers;
                            local existing = dungeon.itemsById[itemId];

                            if (not existing) then
                                local item = {
                                    itemId = itemId,
                                    tier = tier,
                                    specId = currentSpecId,
                                    -- Keep original bonusIds for reference
                                    bonusIds = itemInfo.bonusIds,
                                    gems = itemInfo.gems,
                                    enchant = itemInfo.enchant,
                                };
                                table.insert(dungeon.items, item);
                                dungeon.itemsById[itemId] = item;
                                tiers[tier] = (tiers[tier] or 0) + 1;
                            elseif ((TIER_RANK[tier] or 0) > (TIER_RANK[existing.tier] or 0)) then
                                -- The same item favorited on another spec (All specs): it counts
                                -- ONCE, at the best tier any spec gave it.
                                tiers[existing.tier] = tiers[existing.tier] - 1;
                                tiers[tier] = (tiers[tier] or 0) + 1;
                                existing.tier = tier;
                                existing.specId = currentSpecId;
                                existing.bonusIds = itemInfo.bonusIds;
                                existing.gems = itemInfo.gems;
                                existing.enchant = itemInfo.enchant;
                            end
                        end
                    end
                end
            end
        end
    end

    return result;
end

-- Calculate score for a dungeon based on favorites
local function CalculateDungeonScore(dungeonData)
    local score = 0;
    local totalItems = 0;
    local bisCount = 0;
    local mustCount = 0;
    local niceCount = 0;
    local catalystCount = 0;
    local transmogCount = 0;

    for _, item in ipairs(dungeonData.items) do
        totalItems = totalItems + 1;
        if (item.tier == TIER_BIS) then
            bisCount = bisCount + 1;
            score = score + (GetSetting("weightByTier") and TIER_WEIGHT[TIER_BIS] or 1);
        elseif (item.tier == TIER_MUST) then
            mustCount = mustCount + 1;
            score = score + (GetSetting("weightByTier") and TIER_WEIGHT[TIER_MUST] or 1);
        elseif (item.tier == TIER_NICE) then
            niceCount = niceCount + 1;
            score = score + (GetSetting("weightByTier") and TIER_WEIGHT[TIER_NICE] or 1);
        elseif (item.tier == TIER_CATALYST) then
            catalystCount = catalystCount + 1;
            score = score + (GetSetting("weightByTier") and TIER_WEIGHT[TIER_CATALYST] or 1);
        elseif (item.tier == TIER_TRANSMOG) then
            transmogCount = transmogCount + 1;
            score = score + (GetSetting("weightByTier") and TIER_WEIGHT[TIER_TRANSMOG] or 1);
        else
            -- Unknown tier from a newer KeystoneLoot: still count it, weight it lowest
            score = score + 1;
        end
    end

    return {
        score = score,
        totalItems = totalItems,
        bisCount = bisCount,
        mustCount = mustCount,
        niceCount = niceCount,
        catalystCount = catalystCount,
        transmogCount = transmogCount,
    };
end

-- Get ranked dungeon list.
-- Second return: how many dungeons had favorites BEFORE the Min items filter, so an
-- empty list can say whether that filter emptied it.
function Addon:GetRankedDungeons()
    if (not KeystoneLootDB or not KeystoneLootCharDB) then
        return {}, 0;
    end

    local favoritesByDungeon = GetAllFavorites();
    local ranked = {};
    local candidates = 0;

    for challengeModeId, data in pairs(favoritesByDungeon) do
        local stats = CalculateDungeonScore(data);
        candidates = candidates + 1;

        -- Filter by minimum favorites
        if (stats.totalItems >= GetSetting("minFavorites")) then
            table.insert(ranked, {
                challengeModeId = challengeModeId,
                dungeon = data.dungeon,
                items = data.items,
                tiers = data.tiers,
                stats = stats,
            });
        end
    end

    -- Sort based on setting
    local sortBy = GetSetting("sortBy");
    table.sort(ranked, function(a, b)
        if (sortBy == "score") then
            if (a.stats.score ~= b.stats.score) then
                return a.stats.score > b.stats.score;
            end
            return a.dungeon.name < b.dungeon.name;
        elseif (sortBy == "count") then
            if (a.stats.totalItems ~= b.stats.totalItems) then
                return a.stats.totalItems > b.stats.totalItems;
            end
            return a.dungeon.name < b.dungeon.name;
        elseif (sortBy == "bis") then
            if (a.stats.bisCount ~= b.stats.bisCount) then
                return a.stats.bisCount > b.stats.bisCount;
            end
            return a.stats.score > b.stats.score;
        else -- name
            return a.dungeon.name < b.dungeon.name;
        end
    end);

    return ranked, candidates;
end

-- Whether the selected character has any dungeon favorite at all, on any spec. Tells
-- "this spec has none" (offer All specs) apart from "nothing favorited yet".
function Addon:HasAnyDungeonFavorites()
    local characterKey = KeystoneLootCharDB and KeystoneLootCharDB.ui and KeystoneLootCharDB.ui.selectedCharacterKey;
    local favorites = characterKey and KeystoneLootDB and KeystoneLootDB.favorites
        and KeystoneLootDB.favorites[characterKey];
    if (not favorites) then return false; end

    for sourceId, sourceData in pairs(favorites) do
        if (type(sourceId) == "number" and sourceId > 0 and sourceId < 1000) then
            for _, specData in pairs(sourceData) do
                if (next(specData)) then return true; end
            end
        end
    end
    return false;
end

_G.KSLBestDungeon = Addon;

-- ============================================================
-- Frame Initialization - Hook into KeystoneLoot's frame
-- ============================================================
local function HookIntoKeystoneLoot()
    local KSLFrame = _G.KeystoneLootFrame;
    if (not KSLFrame) then
        return false;
    end

    -- Check if we've already added our tab
    if (KSLFrame.kslBestDungeonTabId) then
        return true;
    end

    -- Check if KSL's tab system is initialized (XML uses TabSystem with capital T)
    -- Also check internal tabSystem field (lowercase) which is set by SetTabSystem()
    if (not KSLFrame.TabSystem or not KSLFrame.tabSystem) then
        -- KSL hasn't initialized tabs yet, wait for it
        return false;
    end

    -- Create the rankings frame as a child of KSL's frame.
    --
    -- It covers the WHOLE window, like KSL's own tab frames: anchored at TOPLEFT
    -- only, with an explicit size, and its content laid out from 60px down (below
    -- KSL's header dropdowns) to 24px up (above KSL's footer text). KSL's SetTab
    -- resizes the window to the selected tab frame's size, so a frame whose size
    -- is derived from the window -- as this one used to be, anchored at -60 and
    -- BOTTOMRIGHT -- makes the window 60px shorter every time the tab is selected.
    -- SyncSizeToKSL() (on every show) copies the Dungeons tab's size, so switching
    -- tabs does not jump and KSL's wide mode carries over.
    local rankingsFrame = CreateFrame("Frame", nil, KSLFrame);
    rankingsFrame:SetPoint("TOPLEFT");
    rankingsFrame:Hide(); -- Hide initially, tab system will show when our tab is selected

    -- Mix in the RankingsFrame methods
    for k, v in pairs(KSLBestDungeonRankingsFrameMixin) do
        rankingsFrame[k] = v;
    end

    rankingsFrame:SyncSizeToKSL();

    -- Create inset. Between KSL's header (60px) and the inset sit the toolbar's
    -- 58px, which Init() builds; the bottom 24px are KSL's footer text.
    rankingsFrame.Inset = CreateFrame("Frame", nil, rankingsFrame, "InsetFrameTemplate3");
    rankingsFrame.Inset:SetPoint("TOPLEFT", 4, -118);
    rankingsFrame.Inset:SetPoint("BOTTOMRIGHT", -4, 24);

    -- Create scroll frame. UIPanelScrollFrameTemplate hangs its scrollbar off the
    -- scroll frame's right edge, so leave 26px for it inside the inset -- filling
    -- the inset put the bar outside the window. The bottom 26px of the inset are the
    -- score key, which Init() builds.
    rankingsFrame.ScrollFrame = CreateFrame("ScrollFrame", nil, rankingsFrame, "UIPanelScrollFrameTemplate");
    rankingsFrame.ScrollFrame:SetPoint("TOPLEFT", rankingsFrame.Inset, "TOPLEFT", 4, -4);
    rankingsFrame.ScrollFrame:SetPoint("BOTTOMRIGHT", rankingsFrame.Inset, "BOTTOMRIGHT", -26, 26);

    -- Create container. Its width follows the scroll frame, and rows are anchored
    -- to both of its sides, so rows always fit the list whatever the window width.
    rankingsFrame.ScrollFrame.Container = CreateFrame("Frame", nil, rankingsFrame.ScrollFrame);
    rankingsFrame.ScrollFrame.Container:SetSize(rankingsFrame.ScrollFrame:GetWidth(), 1);
    rankingsFrame.ScrollFrame.Container:SetPoint("TOPLEFT");
    rankingsFrame.ScrollFrame:SetScrollChild(rankingsFrame.ScrollFrame.Container);
    rankingsFrame.ScrollFrame:HookScript("OnSizeChanged", function(scrollFrame, width)
        scrollFrame.Container:SetWidth(width);
        -- Icons wrap to the row width, so a new width (wide mode) needs a relayout.
        if (rankingsFrame:IsShown()) then
            rankingsFrame:Refresh();
        end
    end);

    -- Initialize the rankings frame
    rankingsFrame:Init();

    -- Add our tab to KSL's tab system FIRST so we get the tabId
    local tabId = KSLFrame:AddNamedTab("Best Dungeons", rankingsFrame);
    --print("|cff9d5db8KSLBestDungeon|r: Added tab with id=" .. tostring(tabId));
    KSLFrame.kslBestDungeonTabId = tabId;
    KSLFrame.kslBestDungeonRankingsFrame = rankingsFrame;

    -- Store reference
    Addon.KSLFrame = KSLFrame;
    Addon.RankingsFrame = rankingsFrame;

    -- No hooks on KSL's frame are needed to keep the list fresh: the rankings frame's
    -- own OnShow (wired in Init) fires both when our tab is selected and when KSL's
    -- window opens with our tab already selected, and it refreshes. This used to also
    -- wrap KSLFrame's OnShow script and hooksecurefunc its SetTab, which rebuilt the
    -- list three times on every open.

    return true;
end

local function TryHook()
    if (HookIntoKeystoneLoot()) then
        return true;
    end
    -- Retry after a short delay
    C_Timer.After(0.5, TryHook);
    return false;
end

-- Start hooking at login, unconditionally. TryHook retries until KSL's tab system
-- exists, which KSL only builds after its own DB:Init at PLAYER_ENTERING_WORLD.
--
-- This used to start only if KeystoneLootDB already existed at PLAYER_LOGIN. On
-- someone's first ever session with KeystoneLoot it does not (KSL creates it later),
-- so the tab never appeared until a /reload. KeystoneLoot is a hard dependency in the
-- TOC, so it is always loaded before this file and there is nothing else to wait for.
local initFrame = CreateFrame("Frame");
initFrame:RegisterEvent("PLAYER_LOGIN");
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN");
    TryHook();
end);

-- Slash command to open KSL and select our tab
-- /rl -> ReloadUI, claimed only if nothing else answers it.
--
-- Blizzard ships /reload, never /rl; the short form is an addon convention.
-- Taking it from an addon that already provides it would be rude and might
-- replace a richer version, so this checks first and skips quietly. Deferred
-- to PLAYER_LOGIN so addons loading after this file are visible to the check.
--
-- Both registries are consulted: hash_SlashCmdList (uppercased, slash
-- included) holds what has been imported, SlashCmdList holds what has been
-- registered since -- the import wipes the latter as it moves entries over.
do
	local function TakenAlready()
		local hash = _G.hash_SlashCmdList;
		if hash and hash["/RL"] then return true; end
		for name in pairs(SlashCmdList) do
			local i = 1;
			local cmd = _G["SLASH_" .. name .. i];
			while cmd do
				if strupper(cmd) == "/RL" then return true; end
				i = i + 1;
				cmd = _G["SLASH_" .. name .. i];
			end
		end
		return false;
	end

	local f = CreateFrame("Frame");
	f:RegisterEvent("PLAYER_LOGIN");
	f:SetScript("OnEvent", function(self)
		self:UnregisterEvent("PLAYER_LOGIN");
		if TakenAlready() then return; end
		SLASH_KSLBESTDUNGEONRELOAD1 = "/rl";
		SlashCmdList["KSLBESTDUNGEONRELOAD"] = function() ReloadUI(); end
	end);
end

-- Open KeystoneLoot and select our tab. Used by /kslbd and the welcome window.
function Addon:OpenBestDungeonsTab()
    local KSLFrame = _G.KeystoneLootFrame;
    if (KSLFrame) then
        KSLFrame:Show();
        if (KSLFrame.kslBestDungeonTabId) then
            KSLFrame:SetTab(KSLFrame.kslBestDungeonTabId);
        end
    else
        print("|cff9d5db8KSLBestDungeon|r: KeystoneLoot frame not found. Type /ksl to open KeystoneLoot first.");
    end
end

SLASH_KSLBESTDUNGEON1 = "/kslbd";
SLASH_KSLBESTDUNGEON2 = "/kslbestdungeon";

SlashCmdList.KSLBESTDUNGEON = function(msg)
    msg = msg and msg:lower() or "";

    if (msg == "config" or msg == "options") then
        print("|cff9d5db8KSLBestDungeon|r: Type /kslbd to open the Best Dungeons tab. The options are in the toolbar along its top.");
    elseif (msg == "notes" or msg == "changelog") then
        if (Addon.ShowReleaseNotes) then Addon:ShowReleaseNotes(); end
    elseif (msg == "welcome") then
        if (Addon.ShowWelcome) then Addon:ShowWelcome(); end
    elseif (msg == "reset") then
        KSLBestDungeonDB = nil;
        ReloadUI();
    elseif (msg == "debug") then
        -- Debug favorites data
        if (not KeystoneLootDB or not KeystoneLootCharDB) then
            print("|cffff0000KeystoneLoot not loaded|r");
            return;
        end

        local characterKey = KeystoneLootCharDB.ui and KeystoneLootCharDB.ui.selectedCharacterKey;
        print("|cff9d5db8KSLBestDungeon Debug:|r");
        print("  Character Key: " .. tostring(characterKey));

        local favorites = KeystoneLootDB.favorites and KeystoneLootDB.favorites[characterKey];
        if (not favorites) then
            print("  No favorites found for this character");
            return;
        end

        print("  Favorites sources:");
        for sourceId, sourceData in pairs(favorites) do
            print("    Source: " .. tostring(sourceId));
            for specId, specData in pairs(sourceData) do
                local count = 0;
                for _ in pairs(specData) do count = count + 1; end
                print("      Spec: " .. tostring(specId) .. " - " .. count .. " items");
                for itemId, itemInfo in pairs(specData) do
                    local name = C_Item.GetItemInfo(itemId);
                    print("        Item: " .. itemId .. " (" .. tostring(name) .. ") Tier: " .. tostring(itemInfo.tier));
                end
            end
        end

        -- Also check current filter spec
        local filterSpecId = KeystoneLootCharDB.filters and KeystoneLootCharDB.filters.specId;
        local filterClassId = KeystoneLootCharDB.filters and KeystoneLootCharDB.filters.classId;
        print("  Current Filter Spec: " .. tostring(filterSpecId) .. " Class: " .. tostring(filterClassId));

    elseif (msg == "debugui" or msg == "dropdown") then
        -- Debug UI/Dropdown state
        local KSLFrame = _G.KeystoneLootFrame;
        if (not KSLFrame) then
            print("|cffff0000KSL Frame not found|r");
            return;
        end
        print("|cff9d5db8KSLBestDungeon UI Debug:|r");
        print("  KSL Frame: " .. tostring(KSLFrame));
        print("  KSL TabSystem: " .. tostring(KSLFrame.TabSystem));
        print("  Our Tab ID: " .. tostring(KSLFrame.kslBestDungeonTabId));
        print("  Rankings Frame: " .. tostring(KSLFrame.kslBestDungeonRankingsFrame));
        local toolbar = KSLFrame.kslBestDungeonRankingsFrame and KSLFrame.kslBestDungeonRankingsFrame.Toolbar;
        print("  Toolbar: " .. tostring(toolbar));
        if (toolbar) then
            print("  Toolbar Visible: " .. tostring(toolbar:IsVisible()) .. " Size: " .. tostring(toolbar:GetWidth()) .. "x" .. tostring(toolbar:GetHeight()));
        end

        if (KSLFrame.TabSystem and KSLFrame.TabSystem.GetSelectedTab) then
            local currentTab = KSLFrame.TabSystem:GetSelectedTab();
            print("  Current Tab: " .. tostring(currentTab));
        end

        -- Note: _G.KeystoneLoot does not exist. KSL keeps its modules on a private
        -- table and only exposes _G.KeystoneLootAPI, so read state from its DB directly.
        print("  KSL API: " .. tostring(_G.KeystoneLootAPI));
        print("  KSL ui.selectedTab: " .. tostring(KeystoneLootCharDB and KeystoneLootCharDB.ui and KeystoneLootCharDB.ui.selectedTab));
        print("  KSL dungeon track: " .. tostring(KeystoneLootCharDB and KeystoneLootCharDB.filters and KeystoneLootCharDB.filters.dungeon and KeystoneLootCharDB.filters.dungeon.track)
            .. " rank: " .. tostring(KeystoneLootCharDB and KeystoneLootCharDB.filters and KeystoneLootCharDB.filters.dungeon and KeystoneLootCharDB.filters.dungeon.rank));

    elseif (msg == "show") then
        -- Force show our tab, toolbar and KSL's item level dropdown
        local KSLFrame = _G.KeystoneLootFrame;
        if (not KSLFrame) then
            print("|cffff0000KSL Frame not found|r");
            return;
        end
        KSLFrame:Show();
        if (KSLFrame.kslBestDungeonTabId) then
            KSLFrame:SetTab(KSLFrame.kslBestDungeonTabId);
        end
        local toolbar = KSLFrame.kslBestDungeonRankingsFrame and KSLFrame.kslBestDungeonRankingsFrame.Toolbar;
        if (toolbar) then
            toolbar:Show();
            print("Toolbar forced show");
        end
        if (KSLFrame.ItemLevelDropdown) then
            KSLFrame.ItemLevelDropdown:Show();
            print("KSL ItemLevel dropdown forced show");
        end

    else
        Addon:OpenBestDungeonsTab();
    end
end