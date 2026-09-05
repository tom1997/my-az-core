/*
 * Copyright (C) 2026 my-az-core contributors
 * Released under the GNU AGPL v3 license.
 */

#include "Chat.h"
#include "ConfigValueCache.h"
#include "DatabaseEnv.h"
#include "Item.h"
#include "ItemTemplate.h"
#include "LFG.h"
#include "LFGMgr.h"
#include "Log.h"
#include "Mail.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "Random.h"
#include "ScriptMgr.h"

#include <algorithm>
#include <array>
#include <unordered_map>
#include <vector>

namespace
{
constexpr uint32 LANG_REWARD_BAG = 85000;
constexpr uint32 LANG_REWARD_MAIL = 85001;
constexpr uint32 LANG_NO_REWARD = 85002;

enum class RewardConfig
{
    Enabled,
    ChancePct,
    MailOnFull,
    IncludeWeapons,
    CandidateWindowPct,
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
    }
};

struct LevelBand
{
    uint32 minLevel;
    uint32 maxLevel;
    uint32 minItemLevel;
    uint32 maxItemLevel;
};

RewardConfigData rewardConfig;
std::vector<LevelBand> levelBands;
std::unordered_map<uint64, std::vector<uint32>> candidateCache;

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

std::vector<uint32> const& GetCandidates(LevelBand const& band)
{
    uint64 key = (uint64(band.minItemLevel) << 32) | band.maxItemLevel;
    auto cached = candidateCache.find(key);
    if (cached == candidateCache.end())
    {
        std::vector<uint32> entries;
        QueryResult result = WorldDatabase.Query(
            "SELECT DISTINCT i.entry FROM item_template i JOIN "
            "(SELECT Item FROM creature_loot_template WHERE Item > 0 UNION "
            "SELECT Item FROM reference_loot_template WHERE Item > 0) loot ON loot.Item = i.entry "
            "WHERE i.Quality = 4 "
            "AND i.ItemLevel BETWEEN {} AND {} AND i.RequiredLevel <= 80 "
            "AND i.InventoryType <> 0 AND i.class IN (2, 4) AND i.Bonding <> 4 "
            "AND i.StartQuest = 0",
            band.minItemLevel, band.maxItemLevel);
        if (result)
            do
            {
                entries.push_back(result->Fetch()[0].Get<uint32>());
            } while (result->NextRow());
        cached = candidateCache.emplace(key, std::move(entries)).first;
    }

    return cached->second;
}

bool IsEligible(Player* player, ItemTemplate const* item)
{
    if (!item || player->CanUseItem(item) != EQUIP_ERR_OK)
        return false;

    if (!rewardConfig.GetConfigValue<bool>(RewardConfig::IncludeWeapons) && item->Class == ITEM_CLASS_WEAPON)
        return false;

    if (item->Class == ITEM_CLASS_ARMOR && IsBodyArmor(item->InventoryType) &&
        item->SubClass != PreferredArmorSubclass(player->getClass()))
        return false;

    return true;
}

uint32 SelectReward(Player* player, LevelBand const& band)
{
    StatProfile equipped = BuildEquippedProfile(player);
    uint8 role = GetRole(player);
    std::vector<std::pair<int64, uint32>> ranked;

    for (uint32 entry : GetCandidates(band))
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

    uint32 windowPct = std::clamp<uint32>(rewardConfig.GetConfigValue<uint32>(RewardConfig::CandidateWindowPct), 1, 100);
    uint32 window = std::max<uint32>(1, uint32((ranked.size() * windowPct + 99) / 100));
    return ranked[urand(0, window - 1)].second;
}

bool WasRewarded(uint32 instanceId, uint32 playerGuid)
{
    return bool(CharacterDatabase.Query(
        "SELECT 1 FROM mod_mythic_rewards_history WHERE instance_id = {} AND guid = {} LIMIT 1",
        instanceId, playerGuid));
}

void RecordReward(uint32 instanceId, uint32 playerGuid, uint32 mythicLevel, uint32 itemEntry, bool mailed)
{
    CharacterDatabase.Execute(
        "INSERT IGNORE INTO mod_mythic_rewards_history "
        "(instance_id, guid, mythic_level, item_entry, mailed) VALUES ({}, {}, {}, {}, {})",
        instanceId, playerGuid, mythicLevel, itemEntry, mailed ? 1 : 0);
}

bool MailReward(Player* player, uint32 entry)
{
    if (!rewardConfig.GetConfigValue<bool>(RewardConfig::MailOnFull))
        return false;

    Item* item = Item::CreateItem(entry, 1, player);
    if (!item)
        return false;

    CharacterDatabaseTransaction transaction = CharacterDatabase.BeginTransaction();
    item->SaveToDB(transaction);
    MailDraft draft("Mythic Plus reward", "Your bags were full, so your personal Mythic Plus reward is attached.");
    draft.AddItem(item);
    draft.SendMailTo(transaction, MailReceiver(player), MailSender(MAIL_NORMAL, player->GetGUID().GetCounter(), MAIL_STATIONERY_GM));
    CharacterDatabase.CommitTransaction(transaction);
    return true;
}

void LoadLevelBands()
{
    levelBands.clear();
    candidateCache.clear();
    QueryResult result = WorldDatabase.Query(
        "SELECT min_mythic_level, max_mythic_level, min_item_level, max_item_level "
        "FROM mod_mythic_rewards_level ORDER BY min_mythic_level");
    if (result)
        do
        {
            Field* fields = result->Fetch();
            levelBands.push_back({fields[0].Get<uint32>(), fields[1].Get<uint32>(),
                fields[2].Get<uint32>(), fields[3].Get<uint32>()});
        } while (result->NextRow());

    LOG_INFO("module", "[MythicRewards] Loaded {} reward level bands.", levelBands.size());
}

class MythicRewardsWorldScript : public WorldScript
{
public:
    MythicRewardsWorldScript() : WorldScript("MythicRewardsWorldScript",
        { WORLDHOOK_ON_BEFORE_CONFIG_LOAD, WORLDHOOK_ON_STARTUP }) { }

    void OnBeforeConfigLoad(bool reload) override
    {
        rewardConfig.Initialize(reload);
    }

    void OnStartup() override
    {
        LoadLevelBands();
    }
};
}

// Called by the deliberately small bridge in mod-mythic-plus after a timed completion.
// Keeping all policy here means upstream updates only have to preserve a single call site.
void RewardMythicEquipment(Player* player, uint32 mythicLevel, uint32 instanceId)
{
    if (!player || !rewardConfig.GetConfigValue<bool>(RewardConfig::Enabled))
        return;

    uint32 chance = std::min<uint32>(100, rewardConfig.GetConfigValue<uint32>(RewardConfig::ChancePct));
    if (chance == 0 || urand(1, 100) > chance)
        return;

    uint32 playerGuid = player->GetGUID().GetCounter();
    if (WasRewarded(instanceId, playerGuid))
        return;

    LevelBand const* band = FindBand(mythicLevel);
    uint32 itemEntry = band ? SelectReward(player, *band) : 0;
    if (!itemEntry)
    {
        if (player->GetSession())
            ChatHandler(player->GetSession()).PSendSysMessage(LANG_NO_REWARD, mythicLevel);
        return;
    }

    bool mailed = false;
    if (!player->AddItem(itemEntry, 1))
    {
        mailed = MailReward(player, itemEntry);
        if (!mailed)
            return;
    }

    RecordReward(instanceId, playerGuid, mythicLevel, itemEntry, mailed);
    if (player->GetSession())
        ChatHandler(player->GetSession()).PSendSysMessage(mailed ? LANG_REWARD_MAIL : LANG_REWARD_BAG, mythicLevel);
}

void AddMythicRewardsScripts()
{
    new MythicRewardsWorldScript();
}
