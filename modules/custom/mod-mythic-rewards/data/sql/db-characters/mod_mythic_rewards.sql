CREATE TABLE IF NOT EXISTS `mod_mythic_rewards_history_v2` (
  `instance_id` int unsigned NOT NULL,
  `guid` int unsigned NOT NULL,
  `map_id` smallint unsigned NOT NULL,
  `mythic_level` tinyint unsigned NOT NULL,
  `timed` tinyint unsigned NOT NULL DEFAULT 0,
  `item_entry` int unsigned NOT NULL DEFAULT 0,
  `mailed` tinyint unsigned NOT NULL DEFAULT 0,
  `rewarded_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`instance_id`, `guid`),
  KEY `idx_guid_rewarded_at` (`guid`, `rewarded_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mod_mythic_rewards_weekly` (
  `week_key` int unsigned NOT NULL,
  `guid` int unsigned NOT NULL,
  `highest_level` tinyint unsigned NOT NULL,
  `map_id` smallint unsigned NOT NULL,
  `claimed` tinyint unsigned NOT NULL DEFAULT 0,
  `item_entry` int unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`week_key`, `guid`),
  KEY `idx_guid_claimed` (`guid`, `claimed`, `week_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
