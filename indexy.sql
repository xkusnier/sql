DROP INDEX IF EXISTS idx_character_class_id;
DROP INDEX IF EXISTS idx_characterinventory_character_id;
DROP INDEX IF EXISTS idx_combat_character_1_id;
DROP INDEX IF EXISTS idx_combat_character_2_id;
DROP INDEX IF EXISTS idx_combatitemdrop_combat_id;
DROP INDEX IF EXISTS idx_combatitemdrop_inventory_id;
DROP INDEX IF EXISTS idx_combatlog_combat_id;
DROP INDEX IF EXISTS idx_spell_spellcat_id;
DROP INDEX IF EXISTS idx_spellattributedependency_spell_id;
DROP INDEX IF EXISTS idx_item_name;

CREATE INDEX idx_character_class_id ON "character"(class_id);
CREATE INDEX idx_characterinventory_character_id ON characterinventory(character_id);
CREATE INDEX idx_combat_character_1_id ON combat(character_1_id);
CREATE INDEX idx_combat_character_2_id ON combat(character_2_id);
CREATE INDEX idx_combatitemdrop_combat_id ON combatitemdrop(combat_id);
CREATE INDEX idx_combatitemdrop_inventory_id ON combatitemdrop(inventory_id);
CREATE INDEX idx_combatlog_combat_id ON combatlog(combat_id);
CREATE INDEX idx_spell_spellcat_id ON spell(spellcat_id);
CREATE INDEX idx_spellattributedependency_spell_id ON spellattributedependency(spell_id);
CREATE INDEX idx_item_name ON item(name);




