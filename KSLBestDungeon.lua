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
    [TIER_CATALYST] = 5,
    [TIER_TRANSMOG] = 1,
};

-- Default settings
local DEFAULT_SETTINGS = {
    minFavorites = 1,
    weightByTier = true,
    showOnlyWithFavorites = true,
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

    -- Fallback: use current player's class/spec
    local _, playerClassId = UnitClass("player");
    local playerSpecId = C_SpecializationInfo.GetSpecializationInfo(C_SpecializationInfo.GetSpecialization() or 1);

    return playerClassId, playerSpecId;
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
                                tiers = { [TIER_BIS] = 0, [TIER_MUST] = 0, [TIER_NICE] = 0, [TIER_CATALYST] = 0, [TIER_TRANSMOG] = 0 },
                            };
                        end

                        table.insert(result[challengeModeId].items, {
                            itemId = itemId,
                            tier = tier,
                            specId = currentSpecId,
                            -- Keep original bonusIds for reference
                            bonusIds = itemInfo.bonusIds,
                            gems = itemInfo.gems,
                            enchant = itemInfo.enchant,
                        });
                        -- Tolerate tiers KeystoneLoot adds that we do not know about yet
                        local tiers = result[challengeModeId].tiers;
                        tiers[tier] = (tiers[tier] or 0) + 1;
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

    -- Create the rankings frame as a child of KSL's frame
    local rankingsFrame = CreateFrame("Frame", nil, KSLFrame);
    rankingsFrame:SetPoint("TOPLEFT", 0, -60);
    rankingsFrame:SetPoint("BOTTOMRIGHT", 0, 0);
    rankingsFrame:Hide(); -- Hide initially, tab system will show when our tab is selected

    -- Mix in the RankingsFrame methods
    for k, v in pairs(KSLBestDungeonRankingsFrameMixin) do
        rankingsFrame[k] = v;
    end

    -- Create inset
    rankingsFrame.Inset = CreateFrame("Frame", nil, rankingsFrame, "InsetFrameTemplate3");
    rankingsFrame.Inset:SetPoint("TOPLEFT", 4, -4);
    rankingsFrame.Inset:SetPoint("BOTTOMRIGHT", -6, 4);

    -- Create scroll frame
    rankingsFrame.ScrollFrame = CreateFrame("ScrollFrame", nil, rankingsFrame, "UIPanelScrollFrameTemplate");
    rankingsFrame.ScrollFrame:SetPoint("TOPLEFT", rankingsFrame.Inset, "TOPLEFT", 4, -4);
    rankingsFrame.ScrollFrame:SetPoint("BOTTOMRIGHT", rankingsFrame.Inset, "BOTTOMRIGHT", -4, 4);

    -- Hide the scrollbar
    if (rankingsFrame.ScrollFrame.ScrollBar) then
        rankingsFrame.ScrollFrame.ScrollBar:Hide();
    end

    -- Create container
    rankingsFrame.ScrollFrame.Container = CreateFrame("Frame", nil, rankingsFrame.ScrollFrame);
    rankingsFrame.ScrollFrame.Container:SetSize(580, 1);
    rankingsFrame.ScrollFrame.Container:SetPoint("TOPLEFT");
    rankingsFrame.ScrollFrame:SetScrollChild(rankingsFrame.ScrollFrame.Container);

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

    -- Create Settings Dropdown (parented to rankingsFrame so it's inside our tab's content area)
    -- Position at top-right of the rankings frame (our tab's content area)
    -- TabSystem automatically shows/hides child frames when switching tabs, so no manual Show/Hide needed
    local settingsDropdown = CreateFrame("DropdownButton", nil, rankingsFrame, "WowStyle1DropdownTemplate");
    settingsDropdown:SetPoint("TOPRIGHT", rankingsFrame, "TOPRIGHT", -20, -10);
    settingsDropdown:SetFrameLevel(rankingsFrame:GetFrameLevel() + 10); -- Ensure it's above Inset/ScrollFrame
    for k, v in pairs(KSLBestDungeonSettingsDropdownMixin) do
        settingsDropdown[k] = v;
    end
    settingsDropdown:Init();
    -- Don't hide - TabSystem will show it when our tab is selected
    KSLFrame.kslBestDungeonSettingsDropdown = settingsDropdown;

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

SLASH_KSLBESTDUNGEON1 = "/kslbd";
SLASH_KSLBESTDUNGEON2 = "/kslbestdungeon";

SlashCmdList.KSLBESTDUNGEON = function(msg)
    msg = msg and msg:lower() or "";

    if (msg == "config" or msg == "options") then
        print("|cff9d5db8KSLBestDungeon|r: Use the minimap button or type /ksl to open KeystoneLoot, then click the 'Best Dungeons' tab.");
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
        print("  Settings Dropdown: " .. tostring(KSLFrame.kslBestDungeonSettingsDropdown));

        if (KSLFrame.kslBestDungeonSettingsDropdown) then
            local sd = KSLFrame.kslBestDungeonSettingsDropdown;
            print("  Settings Dropdown Visible: " .. tostring(sd:IsShown()));
            print("  Settings Dropdown Point: " .. tostring(sd:GetPoint()));
            print("  Settings Dropdown Parent: " .. tostring(sd:GetParent()));
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
        -- Force show our tab and dropdowns
        local KSLFrame = _G.KeystoneLootFrame;
        if (not KSLFrame) then
            print("|cffff0000KSL Frame not found|r");
            return;
        end
        KSLFrame:Show();
        if (KSLFrame.kslBestDungeonTabId) then
            KSLFrame:SetTab(KSLFrame.kslBestDungeonTabId);
        end
        if (KSLFrame.kslBestDungeonSettingsDropdown) then
            KSLFrame.kslBestDungeonSettingsDropdown:Show();
            print("Settings dropdown forced show");
        end
        if (KSLFrame.ItemLevelDropdown) then
            KSLFrame.ItemLevelDropdown:Show();
            print("KSL ItemLevel dropdown forced show");
        end

    else
        -- Open KeystoneLoot and select our tab
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
end