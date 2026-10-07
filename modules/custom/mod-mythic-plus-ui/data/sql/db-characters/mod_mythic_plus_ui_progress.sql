-- Persistent objective state for active Mythic Plus instances.
CREATE TABLE IF NOT EXISTS `mythic_plus_ui_run` (
  `instance_id` int unsigned NOT NULL,
  `map_id` smallint unsigned NOT NULL,
  `final_boss_killed` tinyint unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`instance_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mythic_plus_ui_progress` (
  `instance_id` int unsigned NOT NULL,
  `objective_id` int unsigned NOT NULL,
  `current_count` int unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`instance_id`, `objective_id`),
  KEY `idx_mythic_plus_ui_progress_objective` (`objective_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
