CREATE TABLE IF NOT EXISTS `mod_mythic_rewards_level` (
  `min_mythic_level` tinyint unsigned NOT NULL,
  `max_mythic_level` tinyint unsigned NOT NULL,
  `min_item_level` smallint unsigned NOT NULL,
  `max_item_level` smallint unsigned NOT NULL,
  `money` int unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`min_mythic_level`, `max_mythic_level`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DELETE FROM `mod_mythic_rewards_level`;
INSERT INTO `mod_mythic_rewards_level`
(`min_mythic_level`, `max_mythic_level`, `min_item_level`, `max_item_level`, `money`) VALUES
(1, 1, 200, 200, 200000),
(2, 2, 213, 213, 300000),
(3, 3, 219, 219, 400000),
(4, 4, 226, 226, 500000),
(5, 5, 232, 232, 600000),
(6, 6, 239, 239, 700000),
(7, 255, 245, 245, 800000);

DELETE FROM `acore_string` WHERE `entry` BETWEEN 85000 AND 85002;
INSERT INTO `acore_string`
(`entry`, `content_default`, `locale_koKR`, `locale_frFR`, `locale_deDE`, `locale_zhCN`, `locale_zhTW`, `locale_esES`, `locale_esMX`, `locale_ruRU`) VALUES
(85000, 'Mythic +{} personal equipment reward was placed in your bags.', '', '', '', '大秘境 +{} 个人装备奖励已放入你的背包。', '', '', '', ''),
(85001, 'Mythic +{} personal equipment reward was mailed because your bags were full.', '', '', '', '你的背包已满，大秘境 +{} 个人装备奖励已通过邮件寄出。', '', '', '', ''),
(85002, 'Mythic +{} has no usable equipment candidate for this character. No equipment was awarded.', '', '', '', '大秘境 +{} 没有找到该角色可使用的装备，因此本次未发放装备。', '', '', '', '');
