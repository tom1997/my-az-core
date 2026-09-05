CREATE TABLE IF NOT EXISTS `mod_mythic_rewards_history` (
  `instance_id` int unsigned NOT NULL,
  `guid` int unsigned NOT NULL,
  `mythic_level` tinyint unsigned NOT NULL,
  `item_entry` int unsigned NOT NULL,
  `mailed` tinyint unsigned NOT NULL DEFAULT 0,
  `rewarded_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`instance_id`, `guid`),
  KEY `idx_guid_rewarded_at` (`guid`, `rewarded_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
