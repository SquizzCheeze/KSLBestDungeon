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

local TIER_NAME = {
    [TIER_NICE] = "Nice to have",
    [TIER_MUST] = "Must have",
    [TIER_BIS] = "Best in Slot",
    [TIER_TRANSMOG] = "Transmog",
    [TIER_CATALYST] = "Catalyst",
};

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

-- Get the currently selected character's class and spec
local function GetCurrentCharacterInfo()
    local characterKey = KeystoneLootCharDB and KeystoneLootCharDB.ui and KeystoneLootCharDB.ui.selectedCharacterKey;
    if (not characterKey) then
        return nil, nil;
    end

    local name, realm = strsplit("-", characterKey);
    local classId, specId;

    -- Try to get from filters (what the user is currently viewing)
    local filterClassId = KeystoneLootCharDB.filters and KeystoneLootCharDB.filters.classId;
    local filterSpecId = KeystoneLootCharDB.filters and KeystoneLootCharDB.filters.specId;

    if (filterClassId and filterSpecId and filterSpecId ~= 0) then
        return filterClassId, filterSpecId;
    end

    -- Fallback: use current player's class/spec. UnitClass returns name, file, ID:
    -- the numeric ID is the THIRD value, matching KSL's filters.classId. The second
    -- is the class file ("HUNTER"), which this used to return by mistake.
    local _, _, playerClassId = UnitClass("player");
    local playerSpecId = C_SpecializationInfo.GetSpecializationInfo(C_SpecializationInfo.GetSpecialization() or 1);

    return playerClassId, playerSpecId;
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
    return string.format("%s:%s:%s:%s", tostring(characterKey), tostring(classId), tostring(specId),
        tostring(GetSetting("showAllSpecs")));
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

    for sourceId, sourceData in pairs(favorites[characterKey]) do
        -- Only process dungeon sources (challengeModeId numbers)
        if (type(sourceId) == "number" and sourceId > 0 and sourceId < 1000) then
            local challengeModeId = sourceId;

            -- Get dungeon name from WoW API (dynamic, current season)
            local name = C_ChallengeMode.GetMapUIInfo(challengeModeId);
            local dungeonName = name or ("Dungeon " .. challengeModeId);

            for currentSpecId, specData in pairs(sourceData) do
                -- If showAllSpecs is false, only include current spec
                if (GetSetting("showAllSpecs") or currentSpecId == specId) then
                    for itemId, itemInfo in pairs(specData) do
                        local tier = itemInfo.tier or TIER_MUST;

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

-- Get ranked dungeon list
function Addon:GetRankedDungeons()
    if (not KeystoneLootDB or not KeystoneLootCharDB) then
        return {}, "KeystoneLoot not loaded";
    end

    local favoritesByDungeon = GetAllFavorites();
    local ranked = {};

    for challengeModeId, data in pairs(favoritesByDungeon) do
        local stats = CalculateDungeonScore(data);

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

    return ranked;
end

-- Get item info (uses WoW API for icon/name)
-- Optional bonusId parameter to get item info at specific item level (same method as KSL)
function Addon:GetItemInfo(itemId, bonusId)
    local itemLink = "item:" .. itemId;
    if (bonusId) then
        itemLink = itemLink .. ":" .. bonusId;
    end
    local name, link, quality, ilvl, reqLevel, class, subclass, maxStack, equipSlot, icon, vendorPrice = C_Item.GetItemInfo(itemLink);
    if (name) then
        return { name = name, link = link, icon = icon, quality = quality, ilvl = ilvl };
    end
    return nil;
end

-- Get item info from a full item link (for icons at correct ilvl)
function Addon:GetItemInfoFromLink(itemLink)
    local name, link, quality, ilvl, reqLevel, class, subclass, maxStack, equipSlot, icon, vendorPrice = C_Item.GetItemInfo(itemLink);
    if (name) then
        return { name = name, link = link, icon = icon, quality = quality, ilvl = ilvl };
    end
    return nil;
end

-- Format tier counts for display
function Addon:FormatTierCounts(dungeonData)
    local parts = {};
    if (dungeonData.stats.bisCount > 0) then
        table.insert(parts, string.format("|cff00ff00%d BiS|r", dungeonData.stats.bisCount));
    end
    if (dungeonData.stats.mustCount > 0) then
        table.insert(parts, string.format("|cffffff00%d Must|r", dungeonData.stats.mustCount));
    end
    if (dungeonData.stats.niceCount > 0) then
        table.insert(parts, string.format("|cff00ffff%d Nice|r", dungeonData.stats.niceCount));
    end
    if (dungeonData.stats.catalystCount > 0) then
        table.insert(parts, string.format("|cffa335ee%d Cata|r", dungeonData.stats.catalystCount));
    end
    if (dungeonData.stats.transmogCount > 0) then
        table.insert(parts, string.format("|cff808080%d TMog|r", dungeonData.stats.transmogCount));
    end
    return table.concat(parts, "  ");
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

    -- Hook KSL frame OnShow to refresh our data when tab is shown
    local originalOnShow = KSLFrame:GetScript("OnShow");
    KSLFrame:SetScript("OnShow", function(self, ...)
        if (originalOnShow) then
            originalOnShow(self, ...);
        end
        -- Refresh our rankings frame if our tab is active
        if (KSLFrame.tabSystem and KSLFrame.tabSystem.GetSelectedTab and KSLFrame.tabSystem:GetSelectedTab() == tabId) then
            rankingsFrame:Refresh();
        end
    end);

    -- Also hook SetTab to refresh when our tab is selected
    hooksecurefunc(KSLFrame, "SetTab", function(self, tabIdArg)
        if (tabIdArg == tabId and rankingsFrame.Refresh) then
            rankingsFrame:Refresh();
        end
    end);

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

local initFrame = CreateFrame("Frame");
initFrame:RegisterEvent("PLAYER_LOGIN");
initFrame:RegisterEvent("ADDON_LOADED");

initFrame:SetScript("OnEvent", function(self, event, arg1)
    if (event == "PLAYER_LOGIN") then
        -- All addon files are loaded by now, and KeystoneLoot should be loaded
        if (KeystoneLootDB and KeystoneLootCharDB) then
            -- Try to hook (will retry until KSL's tab system is ready)
            TryHook();
        end
    elseif (event == "ADDON_LOADED" and arg1 == "KeystoneLoot") then
        -- KeystoneLoot just loaded, try to hook
        C_Timer.After(0.5, TryHook);
    end
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