-- Move generated rewards into the 3.3.5 client-compatible item ID range.
-- Keep old templates so rewards already present in character inventories remain valid.
DROP TEMPORARY TABLE IF EXISTS `tmp_mythic_item_template`;
CREATE TEMPORARY TABLE `tmp_mythic_item_template` LIKE `item_template`;
INSERT INTO `tmp_mythic_item_template`
SELECT * FROM `item_template` WHERE `entry` BETWEEN 9100000 AND 9899999;
UPDATE `tmp_mythic_item_template` SET `entry` = `entry` - 8400000;
INSERT IGNORE INTO `item_template` SELECT * FROM `tmp_mythic_item_template`;
DROP TEMPORARY TABLE `tmp_mythic_item_template`;

DROP TEMPORARY TABLE IF EXISTS `tmp_mythic_item_locale`;
CREATE TEMPORARY TABLE `tmp_mythic_item_locale` LIKE `item_template_locale`;
INSERT INTO `tmp_mythic_item_locale`
SELECT * FROM `item_template_locale` WHERE `ID` BETWEEN 9100000 AND 9899999;
UPDATE `tmp_mythic_item_locale` SET `ID` = `ID` - 8400000;
INSERT IGNORE INTO `item_template_locale` SELECT * FROM `tmp_mythic_item_locale`;
DROP TEMPORARY TABLE `tmp_mythic_item_locale`;

UPDATE `mod_mythic_rewards_item_pool`
SET `item_entry` = `item_entry` - 8400000
WHERE `item_entry` BETWEEN 9100000 AND 9899999;
