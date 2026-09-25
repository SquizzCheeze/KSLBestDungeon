local AddonName, KSLBestDungeon = ...;
local Addon = KSLBestDungeon;

-- Constants (matching KeystoneLoot)
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

local TIER_COLOR = {
    [TIER_BIS] = "|cff00ff00",
    [TIER_MUST] = "|cffffff00",
    [TIER_NICE] = "|cff00ffff",
    [TIER_TRANSMOG] = "|cff808080",
    [TIER_CATALYST] = "|cffa335ee",
};

-- StaticPopup for whisper target
StaticPopupDialogs["KSLBESTDUNGEON_WHISPER_TARGET"] = {
    text = "Enter character name to whisper:",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 12,
    editBoxWidth = 200,
    OnAccept = function(self)
        local target = self.editBox:GetText();
        if (target and target ~= "") then
            Addon:SendRankedDungeonsToChat("WHISPER", target);
        end
    end,
    OnShow = function(self)
        self.editBox:SetFocus();
    end,
    OnHide = function(self)
        ChatEdit_FocusActiveWindow();
        self.editBox:SetText("");
    end,
    EditBoxOnEnterPressed = function(self)
        local target = self:GetText();
        if (target and target ~= "") then
            Addon:SendRankedDungeonsToChat("WHISPER", target);
        end
        self:GetParent():Hide();
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide();
    end,
    timeout = 0,
    exclusive = 1,
    whileDead = 1,
    hideOnEscape = 1,
};

-- ============================================================
-- Settings Dropdown Mixin (for KSL frame integration)
-- ============================================================
KSLBestDungeonSettingsDropdownMixin = {};

function KSLBestDungeonSettingsDropdownMixin:Init()
    local function GenerateMenu(dropdown, rootDescription)
        -- Sort By
        local sortBy = rootDescription:CreateButton("Sort By");
        local sorts = {
            { value = "score", text = "Score (Weighted)" },
            { value = "count", text = "Total Favorites Count" },
            { value = "bis", text = "BiS Count" },
            { value = "name", text = "Dungeon Name" },
        };
        for _, sort in ipairs(sorts) do
            sortBy:CreateRadio(sort.text, function() return Addon:GetSetting("sortBy") == sort.value end,
                function() Addon:SetSetting("sortBy", sort.value); self:GetParent():Refresh(); end);
        end

        rootDescription:CreateDivider();

        -- Min Favorites
        local minFavs = rootDescription:CreateButton("Min Favorites: " .. Addon:GetSetting("minFavorites"));
        for i = 1, 10 do
            minFavs:CreateRadio(tostring(i), function() return Addon:GetSetting("minFavorites") == i end,
                function() Addon:SetSetting("minFavorites", i); self:GetParent():Refresh(); end);
        end

        rootDescription:CreateDivider();

        -- Weight by Tier
        rootDescription:CreateCheckbox("Weight by Tier", function() return Addon:GetSetting("weightByTier") end,
            function() Addon:SetSetting("weightByTier", not Addon:GetSetting("weightByTier")); self:GetParent():Refresh(); end);

        -- Show All Specs
        rootDescription:CreateCheckbox("Show All Specs", function() return Addon:GetSetting("showAllSpecs") end,
            function() Addon:SetSetting("showAllSpecs", not Addon:GetSetting("showAllSpecs")); self:GetParent():Refresh(); end);

        -- Only with Favorites
        rootDescription:CreateCheckbox("Only Show Dungeons with Favorites", function() return Addon:GetSetting("showOnlyWithFavorites") end,
            function() Addon:SetSetting("showOnlyWithFavorites", not Addon:GetSetting("showOnlyWithFavorites")); self:GetParent():Refresh(); end);

        rootDescription:CreateDivider();

        -- Send to Chat
        local sendToChat = rootDescription:CreateButton("Send to Chat");
        local channels = {
            { value = "PARTY", text = "Party" },
            { value = "INSTANCE_CHAT", text = "Instance" },
            { value = "GUILD", text = "Guild" },
            { value = "SAY", text = "Say" },
            { value = "YELL", text = "Yell" },
        };
        for _, channel in ipairs(channels) do
            sendToChat:CreateButton(channel.text, function()
                Addon:SendRankedDungeonsToChat(channel.value);
            end);
        end
        -- Battle.net Whisper - submenu with friends list (refreshed each menu open)
        local bnetWhisper = sendToChat:CreateButton("Battle.net Whisper");
        bnetWhisper:SetScrollMode(300);
        local numTotal = BNGetNumFriends();
        if (numTotal == 0) then
            bnetWhisper:CreateButton("|cff808080No Battle.net friends|r", function() end):SetEnabled(false);
        else
            for i = 1, numTotal do
                local accountInfo = C_BattleNet.GetFriendAccountInfo(i);
                if (accountInfo and accountInfo.bnetAccountID and accountInfo.gameAccountInfo) then
                    local gameAccountInfo = accountInfo.gameAccountInfo;
                    local characterName = "";
                    if (gameAccountInfo.characterName and gameAccountInfo.characterName ~= "") then
                        characterName = " (" .. gameAccountInfo.characterName .. ")";
                    end
                    local isOnline = gameAccountInfo.isOnline;
                    local text = accountInfo.battleTag .. characterName;
                    if (not isOnline) then
                        text = "|cff808080" .. text .. " (Offline)|r";
                    end
                    bnetWhisper:CreateButton(text, function()
                        if (isOnline) then
                            Addon:SendRankedDungeonsToChat("BN_WHISPER", accountInfo.bnetAccountID);
                        end
                    end):SetEnabled(isOnline);
                end
            end
        end

        rootDescription:CreateDivider();

        -- Refresh
        rootDescription:CreateButton("Refresh Now", function()
            self:GetParent():Refresh();
        end);

        -- Reset
        rootDescription:CreateButton("Reset Settings", function()
            KSLBestDungeonDB = nil;
            ReloadUI();
        end);
    end

    self:SetupMenu(GenerateMenu);
    self:SetWidth(150);
end

-- Send ranked dungeons to chat channel
function Addon:SendRankedDungeonsToChat(channel, whisperTarget)
    local ranked = Addon:GetRankedDungeons();
    if (#ranked == 0) then
        print("|cff9d5db8KSLBestDungeon|r: No dungeons to send");
        return;
    end

    local parts = {};
    for i, dungeonData in ipairs(ranked) do
        table.insert(parts, string.format("%d.[%s]", i, dungeonData.dungeon.name));
    end
    local message = "KSL Best Dungeons: " .. table.concat(parts, ", ");

    if (channel == "WHISPER" and whisperTarget) then
        SendChatMessage(message, "WHISPER", nil, whisperTarget);
    elseif (channel == "BN_WHISPER" and whisperTarget) then
        -- whisperTarget is the bnetAccountID (presenceID)
        BNSendWhisper(whisperTarget, message);
        print("|cff9d5db8KSLBestDungeon|r: Sent to Battle.net friend");
    else
        SendChatMessage(message, channel);
        print("|cff9d5db8KSLBestDungeon|r: Sent to " .. channel);
    end
end

-- Get Battle.net account ID by BattleTag from friends list (kept for backward compatibility)
function Addon:GetBNetAccountIDByBattleTag(battleTag)
    local numTotal = BNGetNumFriends();
    for i = 1, numTotal do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i);
        if (accountInfo and accountInfo.battleTag == battleTag) then
            return accountInfo.bnetAccountID;
        end
    end
    return nil;
end

-- ============================================================
-- Rankings Frame Methods
-- ============================================================
KSLBestDungeonRankingsFrameMixin = {};

function KSLBestDungeonRankingsFrameMixin:Init()
    -- Subscribe to KeystoneLoot's public API. KSL's internal DB observers are not
    -- reachable from here (see the item level note above), KeystoneLootAPI is.
    local API = _G.KeystoneLootAPI;
    if (API and API.RegisterCallback) then
        API:RegisterCallback(API.Event.FAVORITES_CHANGED, function() self:OnFavoritesChanged(); end, self);
    end

    -- The mixin is copied onto a plain CreateFrame() frame rather than applied from an
    -- XML template, so OnShow/OnHide are not wired up for us - do it by hand.
    self:SetScript("OnShow", self.OnShow);
    self:SetScript("OnHide", self.OnHide);

    self.lastFavoritesHash = nil;
    self:StartPolling();
    self:Refresh();
end

-- Polling fallback: catches everything the API does not fire for, such as the
-- character/spec filter changing in KSL.
function KSLBestDungeonRankingsFrameMixin:StartPolling()
    if (self.pollTimer) then return; end

    self.pollTimer = C_Timer.NewTicker(1.0, function()
        if (not self:IsShown()) then return; end

        if (self:GetFavoritesHash() ~= self.lastFavoritesHash) then
            self:Refresh();
        end
    end);
end

function KSLBestDungeonRankingsFrameMixin:OnFavoritesChanged()
    if (not self:IsShown()) then return; end
    self:Refresh();
end

function KSLBestDungeonRankingsFrameMixin:OnShow()
    -- OnHide cancels the ticker, so it has to be recreated every time our tab is selected.
    self:StartPolling();
    self:Refresh();
end

function KSLBestDungeonRankingsFrameMixin:OnHide()
    if (self.pollTimer) then
        self.pollTimer:Cancel();
        self.pollTimer = nil;
    end
end

function KSLBestDungeonRankingsFrameMixin:GetFavoritesHash()
    if (not KeystoneLootDB or not KeystoneLootCharDB) then return nil; end

    -- The selected character and class/spec filter are part of the hash: changing spec
    -- leaves the favorites tables untouched, so without this the list would keep showing
    -- the previous spec's ranking until a /reload.
    local stateKey = Addon.GetFilterStateKey and Addon:GetFilterStateKey() or "";

    local characterKey = KeystoneLootCharDB.ui and KeystoneLootCharDB.ui.selectedCharacterKey;
    if (not characterKey) then return stateKey .. "|nochar"; end

    local favorites = KeystoneLootDB.favorites and KeystoneLootDB.favorites[characterKey];
    if (not favorites) then return stateKey .. "|empty"; end

    -- Create a simple hash from the favorites data
    local hashParts = {};
    for sourceId, sourceData in pairs(favorites) do
        if (type(sourceId) == "number" and sourceId > 0 and sourceId < 1000) then
            for specId, specData in pairs(sourceData) do
                for itemId, itemInfo in pairs(specData) do
                    table.insert(hashParts, string.format("%d:%d:%d:%d", sourceId, specId, itemId, itemInfo.tier or 0));
                end
            end
        end
    end
    table.sort(hashParts);
    return stateKey .. "|" .. table.concat(hashParts, ",");
end

-- Show a status message instead of the list.
-- Reuses a single FontString: FontStrings are regions, not children, so they are not
-- picked up by the container:GetChildren() cleanup in Refresh().
function KSLBestDungeonRankingsFrameMixin:ShowMessage(text, r, g, b)
    local container = self.ScrollFrame.Container;

    if (not self.MessageText) then
        self.MessageText = container:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
        self.MessageText:SetPoint("TOP", 0, -120);
    end

    self.MessageText:SetText(text);
    self.MessageText:SetTextColor(r, g, b);
    self.MessageText:Show();
end

function KSLBestDungeonRankingsFrameMixin:HideMessage()
    if (self.MessageText) then
        self.MessageText:Hide();
    end
end

function KSLBestDungeonRankingsFrameMixin:Refresh()
    local container = self.ScrollFrame.Container;

    -- Record the state this rebuild reflects, including the early-return paths below, so
    -- the poll ticker only fires again once something actually changed.
    self.lastFavoritesHash = self:GetFavoritesHash();

    -- Release all existing children
    local children = { container:GetChildren() };
    for _, child in ipairs(children) do
        child:Hide();
        child:SetParent(nil);
    end

    self:HideMessage();

    -- Check KeystoneLoot
    if (not KeystoneLootDB or not KeystoneLootCharDB) then
        self:ShowMessage("|cffff0000KeystoneLoot not loaded|r\n\nEnable KeystoneLoot addon to use KSLBestDungeon", 1, 0.3, 0.3);
        return;
    end

    -- Check character
    local characterKey = KeystoneLootCharDB.ui and KeystoneLootCharDB.ui.selectedCharacterKey;
    local info = characterKey and { strsplit("-", characterKey) };
    if (not info or #info < 2) then
        self:ShowMessage("|cffffcc00No character selected|r\n\nOpen KeystoneLoot (/ksl) and select a character", 1, 0.8, 0);
        return;
    end

    -- Get ranked dungeons
    local ranked = Addon:GetRankedDungeons();

    if (#ranked == 0) then
        self:ShowMessage("|cff00ffffNo favorites found|r\n\nAdd favorites in KeystoneLoot for this character/spec", 0, 1, 1);
        return;
    end

    -- Create entry for each dungeon
    local yOffset = 0;
    for rank, dungeonData in ipairs(ranked) do
        local frame = CreateFrame("Frame", nil, container, "KSLBestDungeonEntryTemplate");
        frame:SetPoint("TOPLEFT", 0, -yOffset);
        frame:SetPoint("TOPRIGHT", 0, -yOffset);
        frame:Init(rank, dungeonData);
        frame:Show();
        yOffset = yOffset + frame:GetHeight() + 4;
    end

    container:SetHeight(math.max(yOffset, self.ScrollFrame:GetHeight()));
end

-- ============================================================
-- Item level correctness
--
-- KeystoneLoot's Upgrade module (which scales an item to the ilvl picked in KSL's
-- dropdown) lives on KSL's addon-private table. That table is NOT a global -- KSL
-- only exposes _G.KeystoneLootAPI -- so we cannot call Upgrade:BuildItemLink() and
-- any link we build ourselves shows the item at its base ilvl.
--
-- Instead we render item icons with KSL's own global button template,
-- KeystoneLootLootIconButtonTemplate. Its OnEnter/OnClick close over KSL's private
-- Upgrade module, so tooltips, quality colouring and chat links are built inside KSL
-- and always match the dropdown. Do not hand-roll item links here.
-- ============================================================
local KSL_ICON_BUTTON_TEMPLATE = "KeystoneLootLootIconButtonTemplate";

-- ============================================================
-- Entry Template Mixin
-- ============================================================
KSLBestDungeonEntryMixin = {};

function KSLBestDungeonEntryMixin:OnLoad()
    self.RankText = self:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
    self.RankText:SetPoint("LEFT", 10, 0);
    self.RankText:SetTextColor(1, 0.82, 0);

    self.NameText = self:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    self.NameText:SetPoint("TOPLEFT", 50, -8);

    self.ScoreText = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    self.ScoreText:SetPoint("TOPLEFT", 50, -26);
    self.ScoreText:SetTextColor(0.8, 0.8, 0.8);

    self.TierText = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    self.TierText:SetPoint("TOPLEFT", 50, -42);
    self.TierText:SetTextColor(0.7, 0.7, 0.7);

    self.IconContainer = CreateFrame("Frame", nil, self);
    self.IconContainer:SetPoint("TOPRIGHT", -10, -8);
    self.IconContainer:SetSize(400, 60);

    self.iconFrames = {};

    self:SetScript("OnEnter", function(self)
        if (self.dungeonData and #self.dungeonData.items > 0) then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
            GameTooltip:AddLine(self.dungeonData.dungeon.name, 1, 1, 1);
            GameTooltip:AddLine(" ");
            -- Names only. Hover an icon for the full tooltip at the selected item level.
            for _, item in ipairs(self.dungeonData.items) do
                local name = C_Item.GetItemInfo(item.itemId);
                local tierName = TIER_NAME[item.tier] or "Unknown";
                local tierColor = TIER_COLOR[item.tier] or "|cffffffff";
                GameTooltip:AddDoubleLine(name or ("Item " .. item.itemId), tierColor .. tierName .. "|r");
            end
            GameTooltip:Show();
        end
    end);

    self:SetScript("OnLeave", function(self)
        GameTooltip:Hide();
    end);
end

function KSLBestDungeonEntryMixin:Init(rank, dungeonData)
    self.dungeonData = dungeonData;

    self.RankText:SetText("#" .. rank);
    self.NameText:SetText(dungeonData.dungeon.name);

    local scoreText = string.format("Score: %.0f  |  Items: %d", dungeonData.stats.score, dungeonData.stats.totalItems);
    self.ScoreText:SetText(scoreText);

    local tierParts = {};
    if (dungeonData.stats.bisCount > 0) then
        table.insert(tierParts, string.format("%s%d BiS|r", TIER_COLOR[TIER_BIS], dungeonData.stats.bisCount));
    end
    if (dungeonData.stats.mustCount > 0) then
        table.insert(tierParts, string.format("%s%d Must|r", TIER_COLOR[TIER_MUST], dungeonData.stats.mustCount));
    end
    if (dungeonData.stats.niceCount > 0) then
        table.insert(tierParts, string.format("%s%d Nice|r", TIER_COLOR[TIER_NICE], dungeonData.stats.niceCount));
    end
    if (dungeonData.stats.catalystCount > 0) then
        table.insert(tierParts, string.format("%s%d Cata|r", TIER_COLOR[TIER_CATALYST], dungeonData.stats.catalystCount));
    end
    if (dungeonData.stats.transmogCount > 0) then
        table.insert(tierParts, string.format("%s%d TMog|r", TIER_COLOR[TIER_TRANSMOG], dungeonData.stats.transmogCount));
    end
    self.TierText:SetText(table.concat(tierParts, "   "));

    -- Item icons
    local container = self.IconContainer;
    local maxIcons = 10;
    local iconSize = 34; -- KeystoneLootLootIconButtonTemplate is 34x34
    local spacing = 2;

    for _, iconFrame in ipairs(self.iconFrames) do
        iconFrame:Hide();
        iconFrame:SetParent(nil);
    end
    self.iconFrames = {};

    for i, item in ipairs(dungeonData.items) do
        if (i > maxIcons) then break; end

        -- KSL's own button: it sets the icon and builds the tooltip/chat link through
        -- KSL's Upgrade module, so the item level always matches KSL's dropdown.
        local iconFrame = CreateFrame("Button", nil, container, KSL_ICON_BUTTON_TEMPLATE);
        iconFrame:SetPoint("TOPLEFT", (i - 1) * (iconSize + spacing), 0);
        iconFrame:Init({ itemId = item.itemId });

        -- KSL's Init() desaturates/dims icons that don't match its stat highlighting
        -- filter. Everything in this list is already a favorite, so show them all fully.
        iconFrame.Content.Icon:SetDesaturated(false);
        iconFrame:SetAlpha(1);

        -- KSL marks the tier with a corner icon, but only for the spec currently
        -- filtered in KSL. This list can span specs (showAllSpecs), so keep our own
        -- tier-coloured border, which reflects the tier the item was favorited at.
        iconFrame.Content.IconBorder:Hide();
        iconFrame.TierBorder = iconFrame:CreateTexture(nil, "OVERLAY");
        iconFrame.TierBorder:SetAllPoints();
        local tier = item.tier;
        if (tier == TIER_BIS) then
            iconFrame.TierBorder:SetAtlas("loottoast-itemborder-legendary");
        elseif (tier == TIER_MUST) then
            iconFrame.TierBorder:SetAtlas("loottoast-itemborder-epic");
        elseif (tier == TIER_NICE) then
            iconFrame.TierBorder:SetAtlas("loottoast-itemborder-rare");
        else
            iconFrame.TierBorder:SetAtlas("loottoast-itemborder-uncommon");
        end

        iconFrame:Show();
        table.insert(self.iconFrames, iconFrame);
    end

    if (#dungeonData.items > maxIcons) then
        local moreText = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
        moreText:SetPoint("LEFT", maxIcons * (iconSize + spacing), 0);
        moreText:SetText("|cff808080+" .. (#dungeonData.items - maxIcons) .. " more|r");
        table.insert(self.iconFrames, moreText);
    end

    self:SetHeight(70);
end