-- Optional objective rows for Mythic Plus UI and completion requirements.
-- objective_type: 0 = boss, 1 = trash. entry = 0 matches any eligible trash.
CREATE TABLE IF NOT EXISTS `mythic_plus_ui_objective` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `map_id` smallint unsigned NOT NULL,
  `objective_type` tinyint unsigned NOT NULL,
  `entry` int unsigned NOT NULL DEFAULT 0,
  `required_count` int unsigned NOT NULL DEFAULT 1,
  `label` varchar(128) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_mythic_plus_ui_objective_map` (`map_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
