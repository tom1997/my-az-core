/*
 * Copyright (C) 2026 my-az-core contributors
 * Released under the GNU AGPL v3 license.
 */

#include "Chat.h"
#include "ConfigValueCache.h"
#include "DatabaseEnv.h"
#include "GameTime.h"
#include "Item.h"
#include "ItemTemplate.h"
#include "LFG.h"
#include "LFGMgr.h"
#include "Log.h"
#include "Mail.h"
#include "Map.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "Random.h"
#include "ScriptMgr.h"

#include <algorithm>
#include <sstream>
#include <unordered_map>
#include <vector>

namespace
{
constexpr uint32 LANG_REWARD_BAG = 85000;
constexpr uint32 LANG_REWARD_MAIL = 85001;
constexpr uint32 LANG_NO_PERSONAL_REWARD = 85002;
constexpr uint32 LANG_TIMED_SUMMARY = 85003;
constexpr uint32 LANG_OVERTIME_SUMMARY = 85004;
constexpr uint32 LANG_WEEKLY_REWARD = 85005;
constexpr uint64 SECONDS_PER_WEEK = 7 * DAY;

enum class RewardConfig
{
    Enabled,
    ChancePct,
    MailOnFull,
    IncludeWeapons,
    CandidateWindowPct,
    TimedPartyItems,
    OvertimePartyItems,
    WeeklyEnabled,
    NumConfigs
};

class RewardConfigData : public ConfigValueCache<RewardConfig>
{
public:
    RewardConfigData() : ConfigValueCache(RewardConfig::NumConfigs) { }

    void BuildConfigCache() override
    {
        SetConfigValue<bool>(RewardConfig::Enabled, "MythicRewards.Enable", true);
        SetConfigValue<uint32>(RewardConfig::ChancePct, "MythicRewards.ChancePct", 100);
        SetConfigValue<bool>(RewardConfig::MailOnFull, "MythicRewards.MailOnFull", true);
        SetConfigValue<bool>(RewardConfig::IncludeWeapons, "MythicRewards.IncludeWeapons", true);
        SetConfigValue<uint32>(RewardConfig::CandidateWindowPct, "MythicRewards.CandidateWindowPct", 20);
        SetConfigValue<uint32>(RewardConfig::TimedPartyItems, "MythicRewards.TimedPartyItems", 3);
        SetConfigValue<uint32>(RewardConfig::OvertimePartyItems, "MythicRewards.OvertimePartyItems", 2);
        SetConfigValue<bool>(RewardConfig::WeeklyEnabled, "MythicRewards.Weekly.Enable", true);
    }
};

struct LevelBand
{
    uint32 minLevel;
    uint32 maxLevel;
    uint32 endVariant;
    uint32 weeklyVariant;
    uint32 money;
};

RewardConfigData rewardConfig;
std::vector<LevelBand> levelBands;
std::unordered_map<uint64, std::vector<uint32>> candidateCache;

uint32 CurrentWeek()
{
    return uint32(GameTime::GetGameTime().count() / SECONDS_PER_WEEK);
}

bool IsBodyArmor(uint32 inventoryType)
{
    switch (inventoryType)
    {
        case INVTYPE_HEAD:
        case INVTYPE_SHOULDERS:
        case INVTYPE_CHEST:
        case INVTYPE_ROBE:
        case INVTYPE_LEGS:
        case INVTYPE_HANDS:
        case INVTYPE_WAIST:
        case INVTYPE_FEET:
        case INVTYPE_WRISTS:
            return true;
        default:
            return false;
    }
}

uint32 PreferredArmorSubclass(uint8 playerClass)
{
    switch (playerClass)
    {
        case CLASS_WARRIOR:
        case CLASS_PALADIN:
        case CLASS_DEATH_KNIGHT:
            return ITEM_SUBCLASS_ARMOR_PLATE;
        case CLASS_HUNTER:
        case CLASS_SHAMAN:
            return ITEM_SUBCLASS_ARMOR_MAIL;
        case CLASS_ROGUE:
        case CLASS_DRUID:
            return ITEM_SUBCLASS_ARMOR_LEATHER;
        default:
            return ITEM_SUBCLASS_ARMOR_CLOTH;
    }
}

struct StatProfile
{
    int32 physical = 0;
    int32 caster = 0;
    int32 tank = 0;
    int32 stamina = 0;
};

void AddStats(ItemTemplate const* item, StatProfile& profile)
{
    for (uint32 i = 0; i < item->StatsCount && i < MAX_ITEM_PROTO_STATS; ++i)
    {
        int32 value = std::max<int32>(0, item->ItemStat[i].ItemStatValue);
        switch (item->ItemStat[i].ItemStatType)
        {
            case ITEM_MOD_AGILITY:
            case ITEM_MOD_STRENGTH:
            case ITEM_MOD_ATTACK_POWER:
            case ITEM_MOD_RANGED_ATTACK_POWER:
            case ITEM_MOD_ARMOR_PENETRATION_RATING:
            case ITEM_MOD_EXPERTISE_RATING:
            case ITEM_MOD_HIT_MELEE_RATING:
            case ITEM_MOD_HIT_RANGED_RATING:
            case ITEM_MOD_CRIT_MELEE_RATING:
            case ITEM_MOD_CRIT_RANGED_RATING:
            case ITEM_MOD_HASTE_MELEE_RATING:
            case ITEM_MOD_HASTE_RANGED_RATING:
                profile.physical += value;
                break;
            case ITEM_MOD_INTELLECT:
            case ITEM_MOD_SPIRIT:
            case ITEM_MOD_MANA_REGENERATION:
            case ITEM_MOD_SPELL_POWER:
            case ITEM_MOD_HIT_SPELL_RATING:
            case ITEM_MOD_CRIT_SPELL_RATING:
            case ITEM_MOD_HASTE_SPELL_RATING:
                profile.caster += value;
                break;
            case ITEM_MOD_DEFENSE_SKILL_RATING:
            case ITEM_MOD_DODGE_RATING:
            case ITEM_MOD_PARRY_RATING:
            case ITEM_MOD_BLOCK_RATING:
            case ITEM_MOD_BLOCK_VALUE:
                profile.tank += value;
                break;
            case ITEM_MOD_STAMINA:
                profile.stamina += value;
                break;
            case ITEM_MOD_HIT_RATING:
            case ITEM_MOD_CRIT_RATING:
            case ITEM_MOD_HASTE_RATING:
                profile.physical += value;
                profile.caster += value;
                break;
            default:
                break;
        }
    }
}

StatProfile BuildEquippedProfile(Player* player)
{
    StatProfile profile;
    for (uint8 slot = EQUIPMENT_SLOT_START; slot < EQUIPMENT_SLOT_END; ++slot)
        if (Item* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot))
            AddStats(item->GetTemplate(), profile);
    return profile;
}

uint8 GetRole(Player* player)
{
    return sLFGMgr->GetRoles(player->GetGUID()) &
        (lfg::PLAYER_ROLE_TANK | lfg::PLAYER_ROLE_HEALER | lfg::PLAYER_ROLE_DAMAGE);
}

int64 ScoreCandidate(ItemTemplate const* item, StatProfile const& equipped, uint8 role)
{
    StatProfile stats;
    AddStats(item, stats);
    if (role & lfg::PLAYER_ROLE_TANK)
        return int64(stats.tank) * 8 + int64(stats.stamina) * 2 + stats.physical + stats.caster / 2;
    if (role & lfg::PLAYER_ROLE_HEALER)
        return int64(stats.caster) * 5 + stats.stamina;

    bool preferCaster = equipped.caster > equipped.physical;
    return int64(preferCaster ? stats.caster : stats.physical) * 5 + stats.stamina + stats.tank / 4;
}

LevelBand const* FindBand(uint32 mythicLevel)
{
    for (LevelBand const& band : levelBands)
        if (mythicLevel >= band.minLevel && mythicLevel <= band.maxLevel)
            return &band;
    return nullptr;
}

bool IsEligible(Player* player, ItemTemplate const* item)
{
    if (!item || player->CanUseItem(item) != EQUIP_ERR_OK || item->ItemSet != 0)
        return false;
    if (!rewardConfig.GetConfigValue<bool>(RewardConfig::IncludeWeapons) && item->Class == ITEM_CLASS_WEAPON)
        return false;
    if (item->Class == ITEM_CLASS_ARMOR && IsBodyArmor(item->InventoryType) &&
        item->SubClass != PreferredArmorSubclass(player->getClass()))
        return false;
    return true;
}

uint32 SelectReward(Player* player, uint32 mapId, uint32 variantId)
{
    uint64 key = (uint64(mapId) << 32) | variantId;
    auto found = candidateCache.find(key);
    if (found == candidateCache.end())
        return 0;

    StatProfile equipped = BuildEquippedProfile(player);
    uint8 role = GetRole(player);
    std::vector<std::pair<int64, uint32>> ranked;
    for (uint32 entry : found->second)
    {
        ItemTemplate const* item = sObjectMgr->GetItemTemplate(entry);
        if (IsEligible(player, item))
            ranked.emplace_back(ScoreCandidate(item, equipped, role), entry);
    }
    if (ranked.empty())
        return 0;

    std::sort(ranked.begin(), ranked.end(), [](auto const& left, auto const& right)
    {
        return left.first > right.first;
    });
    uint32 pct = std::clamp<uint32>(rewardConfig.GetConfigValue<uint32>(RewardConfig::CandidateWindowPct), 1, 100);
    uint32 window = std::max<uint32>(1, uint32((ranked.size() * pct + 99) / 100));
    return ranked[urand(0, window - 1)].second;
}

std::string ItemLink(Player* player, uint32 entry)
{
    ItemTemplate const* item = sObjectMgr->GetItemTemplate(entry);
    if (!item)
        return std::to_string(entry);

    std::string name = item->Name1;
    if (player->GetSession())
        if (ItemLocale const* locale = sObjectMgr->GetItemLocale(entry))
            ObjectMgr::GetLocaleString(locale->Name, player->GetSession()->GetSessionDbLocaleIndex(), name);

    std::ostringstream out;
    out << "|c" << std::hex << ItemQualityColors[item->Quality] << std::dec
        << "|Hitem:" << entry << ":0:0:0:0:0:0:0:0:0|h[" << name << "]|h|r";
    return out.str();
}

bool MailReward(Player* player, uint32 entry, bool weekly)
{
    if (!rewardConfig.GetConfigValue<bool>(RewardConfig::MailOnFull))
        return false;
    Item* item = Item::CreateItem(entry, 1, player);
    if (!item)
        return false;

    CharacterDatabaseTransaction transaction = CharacterDatabase.BeginTransaction();
    item->SaveToDB(transaction);
    MailDraft draft(weekly ? "Weekly Mythic reward" : "Mythic Plus reward",
        "Your inventory was full, so the reward is attached.");
    draft.AddItem(item);
    draft.SendMailTo(transaction, MailReceiver(player),
        MailSender(MAIL_NORMAL, player->GetGUID().GetCounter(), MAIL_STATIONERY_GM));
    CharacterDatabase.CommitTransaction(transaction);
    return true;
}

bool GiveReward(Player* player, uint32 entry, bool weekly, bool& mailed)
{
    mailed = false;
    if (player->AddItem(entry, 1))
        return true;
    mailed = MailReward(player, entry, weekly);
    return mailed;
}

bool WasRewarded(uint32 instanceId, uint32 playerGuid)
{
    return bool(CharacterDatabase.Query(
        "SELECT 1 FROM mod_mythic_rewards_history_v2 WHERE instance_id = {} AND guid = {} LIMIT 1",
        instanceId, playerGuid));
}

void RecordCompletion(uint32 instanceId, uint32 playerGuid, uint32 mapId, uint32 mythicLevel,
    bool timed, uint32 itemEntry, bool mailed)
{
    CharacterDatabase.Execute(
        "INSERT IGNORE INTO mod_mythic_rewards_history_v2 "
        "(instance_id, guid, map_id, mythic_level, timed, item_entry, mailed) "
        "VALUES ({}, {}, {}, {}, {}, {}, {})",
        instanceId, playerGuid, mapId, mythicLevel, timed ? 1 : 0, itemEntry, mailed ? 1 : 0);
}

void RecordWeekly(Player* player, uint32 mythicLevel, uint32 mapId)
{
    if (!rewardConfig.GetConfigValue<bool>(RewardConfig::WeeklyEnabled))
        return;
    CharacterDatabase.Execute(
        "INSERT INTO mod_mythic_rewards_weekly (week_key, guid, highest_level, map_id, claimed) "
        "VALUES ({}, {}, {}, {}, 0) ON DUPLICATE KEY UPDATE "
        "map_id = IF(VALUES(highest_level) > highest_level, VALUES(map_id), map_id), "
        "highest_level = GREATEST(highest_level, VALUES(highest_level))",
        CurrentWeek(), player->GetGUID().GetCounter(), mythicLevel, mapId);
}

uint32 Mix(uint32 value)
{
    value ^= value >> 16;
    value *= 0x7feb352dU;
    value ^= value >> 15;
    value *= 0x846ca68bU;
    return value ^ (value >> 16);
}

bool IsPartyItemWinner(Player* player, uint32 instanceId, bool timed)
{
    std::vector<std::pair<uint32, uint32>> order;
    for (Map::PlayerList::const_iterator itr = player->GetMap()->GetPlayers().begin();
         itr != player->GetMap()->GetPlayers().end(); ++itr)
        if (Player* member = itr->GetSource())
            order.emplace_back(Mix(member->GetGUID().GetCounter() ^ instanceId), member->GetGUID().GetCounter());

    std::sort(order.begin(), order.end());
    uint32 configured = rewardConfig.GetConfigValue<uint32>(
        timed ? RewardConfig::TimedPartyItems : RewardConfig::OvertimePartyItems);
    uint32 winners = std::min<uint32>(configured, order.size());
    uint32 guid = player->GetGUID().GetCounter();
    return std::any_of(order.begin(), order.begin() + winners,
        [guid](auto const& candidate) { return candidate.second == guid; });
}

void LoadRewardData()
{
    levelBands.clear();
    candidateCache.clear();
    if (QueryResult levels = WorldDatabase.Query(
        "SELECT min_mythic_level, max_mythic_level, end_variant_id, weekly_variant_id, money "
        "FROM mod_mythic_rewards_level_v2 ORDER BY min_mythic_level"))
        do
        {
            Field* fields = levels->Fetch();
            levelBands.push_back({fields[0].Get<uint32>(), fields[1].Get<uint32>(),
                fields[2].Get<uint32>(), fields[3].Get<uint32>(), fields[4].Get<uint32>()});
        } while (levels->NextRow());

    if (QueryResult pool = WorldDatabase.Query(
        "SELECT map_id, variant_id, item_entry FROM mod_mythic_rewards_item_pool"))
        do
        {
            Field* fields = pool->Fetch();
            uint32 mapId = fields[0].Get<uint32>();
            uint32 variantId = fields[1].Get<uint32>();
            candidateCache[(uint64(mapId) << 32) | variantId].push_back(fields[2].Get<uint32>());
        } while (pool->NextRow());

    LOG_INFO("module", "[MythicRewards] Loaded {} level bands and {} dungeon/variant pools.",
        levelBands.size(), candidateCache.size());
}

void ClaimWeeklyReward(Player* player)
{
    if (!rewardConfig.GetConfigValue<bool>(RewardConfig::Enabled) ||
        !rewardConfig.GetConfigValue<bool>(RewardConfig::WeeklyEnabled))
        return;

    QueryResult result = CharacterDatabase.Query(
        "SELECT week_key, highest_level, map_id FROM mod_mythic_rewards_weekly "
        "WHERE guid = {} AND week_key < {} AND claimed = 0 ORDER BY week_key DESC LIMIT 1",
        player->GetGUID().GetCounter(), CurrentWeek());
    if (!result)
        return;

    Field* fields = result->Fetch();
    uint32 weekKey = fields[0].Get<uint32>();
    uint32 mythicLevel = fields[1].Get<uint32>();
    uint32 mapId = fields[2].Get<uint32>();
    LevelBand const* band = FindBand(mythicLevel);
    uint32 entry = band ? SelectReward(player, mapId, band->weeklyVariant) : 0;
    bool mailed = false;
    if (!entry || !GiveReward(player, entry, true, mailed))
        return;

    CharacterDatabase.Execute(
        "UPDATE mod_mythic_rewards_weekly SET claimed = 1, item_entry = {} "
        "WHERE week_key = {} AND guid = {} AND claimed = 0",
        entry, weekKey, player->GetGUID().GetCounter());
    if (player->GetSession())
        ChatHandler(player->GetSession()).PSendSysMessage(LANG_WEEKLY_REWARD, mythicLevel, ItemLink(player, entry));
}

class MythicRewardsWorldScript : public WorldScript
{
public:
    MythicRewardsWorldScript() : WorldScript("MythicRewardsWorldScript",
        { WORLDHOOK_ON_BEFORE_CONFIG_LOAD, WORLDHOOK_ON_STARTUP }) { }

    void OnBeforeConfigLoad(bool reload) override { rewardConfig.Initialize(reload); }
    void OnStartup() override { LoadRewardData(); }
};

class MythicRewardsPlayerScript : public PlayerScript
{
public:
    MythicRewardsPlayerScript() : PlayerScript("MythicRewardsPlayerScript", { PLAYERHOOK_ON_LOGIN }) { }
    void OnPlayerLogin(Player* player) override { ClaimWeeklyReward(player); }
};
}

// Called once for each party member by the deliberately small mod-mythic-plus bridge.
void RewardMythicCompletion(Player* player, uint32 mythicLevel, uint32 instanceId, uint32 mapId, bool timed)
{
    if (!player || !rewardConfig.GetConfigValue<bool>(RewardConfig::Enabled))
        return;
    uint32 playerGuid = player->GetGUID().GetCounter();
    if (WasRewarded(instanceId, playerGuid))
        return;

    LevelBand const* band = FindBand(mythicLevel);
    if (!band)
        return;

    RecordWeekly(player, mythicLevel, mapId);
    if (band->money)
        player->ModifyMoney(band->money);

    bool winner = IsPartyItemWinner(player, instanceId, timed);
    uint32 chance = std::min<uint32>(100, rewardConfig.GetConfigValue<uint32>(RewardConfig::ChancePct));
    if (!winner || chance == 0 || urand(1, 100) > chance)
    {
        RecordCompletion(instanceId, playerGuid, mapId, mythicLevel, timed, 0, false);
        if (player->GetSession())
        {
            ChatHandler handler(player->GetSession());
            handler.PSendSysMessage(LANG_NO_PERSONAL_REWARD, mythicLevel);
            handler.PSendSysMessage(timed ? LANG_TIMED_SUMMARY : LANG_OVERTIME_SUMMARY, mythicLevel);
        }
        return;
    }

    uint32 entry = SelectReward(player, mapId, band->endVariant);
    bool mailed = false;
    if (!entry || !GiveReward(player, entry, false, mailed))
    {
        RecordCompletion(instanceId, playerGuid, mapId, mythicLevel, timed, 0, false);
        return;
    }

    RecordCompletion(instanceId, playerGuid, mapId, mythicLevel, timed, entry, mailed);
    if (player->GetSession())
    {
        ChatHandler handler(player->GetSession());
        handler.PSendSysMessage(mailed ? LANG_REWARD_MAIL : LANG_REWARD_BAG, mythicLevel, ItemLink(player, entry));
        handler.PSendSysMessage(timed ? LANG_TIMED_SUMMARY : LANG_OVERTIME_SUMMARY, mythicLevel);
    }
}

void AddMythicRewardsScripts()
{
    new MythicRewardsWorldScript();
    new MythicRewardsPlayerScript();
}
