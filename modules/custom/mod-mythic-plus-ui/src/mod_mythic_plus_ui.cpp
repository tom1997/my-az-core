/*
 * Mythic Plus UI bridge.  The server remains authoritative; the client addon
 * only renders the state sent through filtered system messages.
 */

#include "Chat.h"
#include "Creature.h"
#include "DatabaseEnv.h"
#include "GameTime.h"
#include "Group.h"
#include "Map.h"
#include "Player.h"
#include "ScriptMgr.h"

#include <algorithm>
#include <cstdint>
#include <mutex>
#include <sstream>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace MythicPlusUI
{
enum class ObjectiveType : uint8
{
    Boss = 0,
    Trash = 1
};

struct ObjectiveDefinition
{
    uint32 id = 0;
    uint32 mapId = 0;
    ObjectiveType type = ObjectiveType::Boss;
    uint32 entry = 0;              // 0 means any eligible trash creature.
    uint32 required = 1;
    std::string label;
};

struct ObjectiveState
{
    ObjectiveDefinition definition;
    uint32 current = 0;
};

struct RunState
{
    uint32 mapId = 0;
    uint32 level = 0;
    uint32 timeLimit = 0;
    uint64 startTime = 0;
    uint32 deaths = 0;
    uint32 penaltySeconds = 0;
    bool finalBossKilled = false;
    std::vector<ObjectiveState> objectives;
};

std::vector<ObjectiveDefinition> definitions;
std::unordered_map<uint32, RunState> runs;
std::mutex runsMutex;

std::string Clean(std::string value)
{
    std::replace(value.begin(), value.end(), '|', '/');
    std::replace(value.begin(), value.end(), '\n', ' ');
    std::replace(value.begin(), value.end(), '\r', ' ');
    return value;
}

void Send(Map* map, std::string const& payload)
{
    if (!map)
        return;

    std::string message = "MPUI|" + payload;
    for (Map::PlayerList::const_iterator itr = map->GetPlayers().begin(); itr != map->GetPlayers().end(); ++itr)
        if (Player* player = itr->GetSource())
            ChatHandler(player->GetSession()).SendSysMessage(message);
}

void SendRun(Map* map, RunState const& run)
{
    std::ostringstream start;
    start << "START|" << run.mapId << '|' << run.level << '|' << run.timeLimit << '|' << run.startTime << '|'
          << run.deaths << '|' << run.penaltySeconds;
    Send(map, start.str());

    for (ObjectiveState const& objective : run.objectives)
    {
        std::ostringstream row;
        row << "OBJECTIVE|" << objective.definition.id << '|'
            << uint32(objective.definition.type) << '|'
            << objective.definition.entry << '|'
            << objective.current << '|'
            << objective.definition.required << '|'
            << Clean(objective.definition.label);
        Send(map, row.str());
    }
}

RunState* GetRunUnlocked(Map* map)
{
    if (!map)
        return nullptr;
    auto itr = runs.find(map->GetInstanceId());
    return itr == runs.end() ? nullptr : &itr->second;
}

void LoadDefinitions()
{
    definitions.clear();
    QueryResult result = WorldDatabase.Query("SELECT id, map_id, objective_type, entry, required_count, label FROM mythic_plus_ui_objective ORDER BY map_id, id");
    if (!result)
        return;

    do
    {
        Field* fields = result->Fetch();
        ObjectiveDefinition definition;
        definition.id = fields[0].Get<uint32>();
        definition.mapId = fields[1].Get<uint32>();
        definition.type = fields[2].Get<uint8>() == 1 ? ObjectiveType::Trash : ObjectiveType::Boss;
        definition.entry = fields[3].Get<uint32>();
        definition.required = std::max<uint32>(1, fields[4].Get<uint32>());
        definition.label = fields[5].Get<std::string>();
        definitions.push_back(std::move(definition));
    } while (result->NextRow());
}

void SendObjectiveProgress(Map* map, ObjectiveState const& objective)
{
    std::ostringstream row;
    row << "PROGRESS|" << objective.definition.id << '|' << objective.current << '|' << objective.definition.required;
    Send(map, row.str());
}

bool AllObjectivesComplete(RunState const& run)
{
    return std::all_of(run.objectives.begin(), run.objectives.end(), [](ObjectiveState const& objective)
    {
        return objective.current >= objective.definition.required;
    });
}
}

void MythicPlusUI_OnStart(Map* map, uint32 level, uint32 timeLimit, uint64 startTime, uint32 penaltySeconds,
                          bool resume)
{
    if (!map)
        return;

    std::lock_guard<std::mutex> lock(MythicPlusUI::runsMutex);
    if (MythicPlusUI::runs.find(map->GetInstanceId()) != MythicPlusUI::runs.end())
        return;

    MythicPlusUI::RunState run;
    run.mapId = map->GetId();
    run.level = level;
    run.timeLimit = timeLimit;
    run.startTime = startTime;
    run.penaltySeconds = penaltySeconds;
    for (MythicPlusUI::ObjectiveDefinition const& definition : MythicPlusUI::definitions)
        if (definition.mapId == run.mapId)
            run.objectives.push_back({ definition, 0 });

    uint32 const instanceId = map->GetInstanceId();
    if (resume)
    {
        if (QueryResult savedRun = CharacterDatabase.Query(
                "SELECT final_boss_killed FROM mythic_plus_ui_run WHERE instance_id = {}", instanceId))
            run.finalBossKilled = savedRun->Fetch()[0].Get<bool>();

        if (QueryResult progress = CharacterDatabase.Query(
                "SELECT objective_id, current_count FROM mythic_plus_ui_progress WHERE instance_id = {}", instanceId))
        {
            do
            {
                Field* fields = progress->Fetch();
                uint32 const objectiveId = fields[0].Get<uint32>();
                for (MythicPlusUI::ObjectiveState& objective : run.objectives)
                    if (objective.definition.id == objectiveId)
                        objective.current = std::min(objective.definition.required, fields[1].Get<uint32>());
            } while (progress->NextRow());
        }
    }
    else
    {
        CharacterDatabase.Execute("DELETE FROM mythic_plus_ui_progress WHERE instance_id = {}", instanceId);
        CharacterDatabase.Execute("DELETE FROM mythic_plus_ui_run WHERE instance_id = {}", instanceId);
        CharacterDatabase.Execute("INSERT INTO mythic_plus_ui_run (instance_id, map_id, final_boss_killed) VALUES ({}, {}, 0)",
                                instanceId, map->GetId());
    }

    MythicPlusUI::runs[instanceId] = std::move(run);
    MythicPlusUI::SendRun(map, MythicPlusUI::runs[instanceId]);
}

void MythicPlusUI_OnPlayerEnter(Map* map, Player* player)
{
    std::lock_guard<std::mutex> lock(MythicPlusUI::runsMutex);
    MythicPlusUI::RunState* run = MythicPlusUI::GetRunUnlocked(map);
    if (!run || !player)
        return;

    std::string message = "MPUI|";
    std::ostringstream start;
    start << "START|" << run->mapId << '|' << run->level << '|' << run->timeLimit << '|' << run->startTime << '|'
          << run->deaths << '|' << run->penaltySeconds;
    ChatHandler(player->GetSession()).SendSysMessage(message + start.str());
    for (MythicPlusUI::ObjectiveState const& objective : run->objectives)
    {
        std::ostringstream row;
        row << message << "OBJECTIVE|" << objective.definition.id << '|'
            << uint32(objective.definition.type) << '|' << objective.definition.entry << '|'
            << objective.current << '|' << objective.definition.required << '|'
            << MythicPlusUI::Clean(objective.definition.label);
        ChatHandler(player->GetSession()).SendSysMessage(row.str());
    }
}

bool MythicPlusUI_OnCreatureDeath(Map* map, Creature* creature, Unit* killer, bool isBoss, bool isFinalBoss)
{
    std::lock_guard<std::mutex> lock(MythicPlusUI::runsMutex);
    MythicPlusUI::RunState* run = MythicPlusUI::GetRunUnlocked(map);
    if (!run || !creature)
        return isFinalBoss;
    if (!killer || (!killer->ToPlayer() && !killer->IsControlledByPlayer()))
        return false;

    for (MythicPlusUI::ObjectiveState& objective : run->objectives)
    {
        bool matches = objective.definition.type == (isBoss ? MythicPlusUI::ObjectiveType::Boss : MythicPlusUI::ObjectiveType::Trash) &&
            (objective.definition.entry == 0 || objective.definition.entry == creature->GetEntry());
        if (!matches || objective.current >= objective.definition.required)
            continue;

        ++objective.current;
        CharacterDatabase.Execute(
            "REPLACE INTO mythic_plus_ui_progress (instance_id, objective_id, current_count) VALUES ({}, {}, {})",
            map->GetInstanceId(), objective.definition.id, objective.current);
        MythicPlusUI::SendObjectiveProgress(map, objective);
    }

    if (isFinalBoss && !run->finalBossKilled)
    {
        run->finalBossKilled = true;
        CharacterDatabase.Execute("UPDATE mythic_plus_ui_run SET final_boss_killed = 1 WHERE instance_id = {}",
                                  map->GetInstanceId());
    }

    return run->finalBossKilled && MythicPlusUI::AllObjectivesComplete(*run);
}

void MythicPlusUI_OnPlayerDeath(Map* map, uint32 deaths, uint32 penaltySeconds)
{
    std::lock_guard<std::mutex> lock(MythicPlusUI::runsMutex);
    MythicPlusUI::RunState* run = MythicPlusUI::GetRunUnlocked(map);
    if (!run)
        return;
    run->deaths = deaths;
    std::ostringstream row;
    row << "DEATH|" << deaths << '|' << penaltySeconds;
    MythicPlusUI::Send(map, row.str());
}

void MythicPlusUI_OnComplete(Map* map, uint32 level, uint32 elapsedSeconds, bool timed)
{
    if (!map)
        return;
    std::lock_guard<std::mutex> lock(MythicPlusUI::runsMutex);
    std::ostringstream row;
    row << "COMPLETE|" << level << '|' << elapsedSeconds << '|' << (timed ? 1 : 0);
    MythicPlusUI::Send(map, row.str());
    MythicPlusUI::runs.erase(map->GetInstanceId());
    CharacterDatabase.Execute("DELETE FROM mythic_plus_ui_progress WHERE instance_id = {}", map->GetInstanceId());
    CharacterDatabase.Execute("DELETE FROM mythic_plus_ui_run WHERE instance_id = {}", map->GetInstanceId());
}

void MythicPlusUI_OnDestroy(Map* map)
{
    if (map)
    {
        std::lock_guard<std::mutex> lock(MythicPlusUI::runsMutex);
        MythicPlusUI::runs.erase(map->GetInstanceId());
    }
}

class MythicPlusUIWorldScript : public WorldScript
{
public:
    MythicPlusUIWorldScript() : WorldScript("MythicPlusUIWorldScript") { }

    void OnStartup() override
    {
        MythicPlusUI::LoadDefinitions();
    }
};

void AddMythicPlusUIScripts()
{
    new MythicPlusUIWorldScript();
}
