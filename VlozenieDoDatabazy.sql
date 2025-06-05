
CREATE OR REPLACE FUNCTION sp_create_character(
    p_name VARCHAR,
    p_strength INT,
    p_dexterity INT,
    p_intelligence INT,
    p_constitution INT,
    p_maxhealth INT,
    p_class_id INT
) RETURNS VOID AS $$
DECLARE
    v_classarmorbonus INT;
    v_inventorymodifier NUMERIC;
    v_apmodifier NUMERIC;
    v_armorclass INT;
    v_maxap INT;
    v_inventorysize INT;
    v_new_char_id INT;
BEGIN
    SELECT classarmorbonus, inventorysizemodifier, actionpointsmodifier
    INTO v_classarmorbonus, v_inventorymodifier, v_apmodifier
    FROM class
    WHERE class_id = p_class_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Trieda % neexistuje', p_class_id;
    END IF;

    v_armorclass := 10 + (p_dexterity / 2) + v_classarmorbonus;
    v_maxap := ROUND((p_dexterity + p_intelligence) * v_apmodifier);
    v_inventorysize := ROUND((p_strength + p_constitution) * v_inventorymodifier);

    -- Vytvorenie postavy
    INSERT INTO "character" (
        name, strength, dexterity, intelligence, constitution,
        armorclass, maxap, actualap, maxhealth, actualhealth, class_id
    ) VALUES (
        p_name, p_strength, p_dexterity, p_intelligence, p_constitution,
        v_armorclass, v_maxap, v_maxap, p_maxhealth, p_maxhealth, p_class_id
    )
    RETURNING character_id INTO v_new_char_id;

    -- Vytvorenie inventára
    INSERT INTO characterinventory(character_id, maxinventorysize)
    VALUES (v_new_char_id, v_inventorysize);
END;
$$ LANGUAGE plpgsql;




TRUNCATE combatlog, combatitemdrop, combat, characterinventory, "character", class, item, spellcategory, spell, spellattributedependency RESTART IDENTITY CASCADE;

-- Triedy
INSERT INTO class(class_id, name, classarmorbonus, inventorysizemodifier, actionpointsmodifier) VALUES
(1, 'Knight', 4, 1.2, 1.0),
(2, 'Rogue', 2, 1.0, 1.2),
(3, 'Mage', 1, 0.8, 1.5);

-- Vytvorenie postáv cez procedúru
SELECT sp_create_character('Arthas', 8, 2, 1, 7, 100, 1); -- ID 1
SELECT sp_create_character('Valeera', 3, 7, 4, 3, 80, 2); -- ID 2
SELECT sp_create_character('Medivh', 1, 3, 10, 4, 60, 3); -- ID 3




INSERT INTO spellcategory(spellcat_id, category_value) VALUES
(1, 1.0),
(2, 1.2);


INSERT INTO spell(spell_id, spellcat_id, name, baseapcost, basedamage) VALUES
(1, 1, 'Fire Bolt', 5, 30),
(2, 1, 'Flamestrike', 8, 50),
(3, 2, 'Frost Spike', 4, 20);


INSERT INTO spellattributedependency(spell_id, attributetype, weight) VALUES
(1, 'Intelligence', 3),
(2, 'Intelligence', 5),
(3, 'Intelligence', 2);

-- Itemy
INSERT INTO item(name, vaha, bonus_type, bonus_value, itemmod) VALUES
('Iron Sword', 5, 'Strength', 2, 0.1),         -- +2 Strength
('Wooden Shield', 4, 'Constitution', 1, 0.3),  -- +1 Constitution
('Magic Staff', 3, 'Intelligence', 3, 0.8),    -- +3 Intelligence
('Heavy Axe', 12, 'Strength', 4, 0);         -- +4 Strength


