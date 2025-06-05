---------------------------
-- 1) f_effective_spell_cost
---------------------------
CREATE OR REPLACE FUNCTION f_effective_spell_cost(
  p_spell_id INT,
  p_caster_id INT
) RETURNS NUMERIC AS
$$
DECLARE
  r RECORD;
  v_baseapcost INT;
  v_basedmg    INT; 
  v_catid      INT;
  v_catmod     NUMERIC := 1.0;  
  v_effcost    NUMERIC;
  v_sum_attr   NUMERIC := 0.0;  
  v_itemmod    NUMERIC := 0.0;  
BEGIN
  SELECT baseapcost, basedamage, spellcat_id
    INTO v_baseapcost, v_basedmg, v_catid
    FROM spell
    WHERE spell_id = p_spell_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Spell % neexistuje!', p_spell_id;
  END IF;

  -- Získaj category modifier z tabuľky spellcategory
  SELECT category_value INTO v_catmod
  FROM spellcategory
  WHERE spellcat_id = v_catid;

  -- Výpočet vplyvu atribútov
  FOR r IN (
    SELECT attributetype, weight
    FROM spellattributedependency
    WHERE spell_id = p_spell_id
  ) LOOP
    IF r.attributetype = 'Strength' THEN
      v_sum_attr := v_sum_attr + (
         (SELECT strength FROM "character" WHERE character_id = p_caster_id) * r.weight
      ) / 100.0;
    ELSIF r.attributetype = 'Intelligence' THEN
      v_sum_attr := v_sum_attr + (
         (SELECT intelligence FROM "character" WHERE character_id = p_caster_id) * r.weight
      ) / 100.0;
    ELSIF r.attributetype = 'Dexterity' THEN
      v_sum_attr := v_sum_attr + (
         (SELECT dexterity FROM "character" WHERE character_id = p_caster_id) * r.weight
      ) / 100.0;
    ELSIF r.attributetype = 'Constitution' THEN
      v_sum_attr := v_sum_attr + (
         (SELECT constitution FROM "character" WHERE character_id = p_caster_id) * r.weight
      ) / 100.0;
    END IF;
  END LOOP;
  
  -- Výpočet vplyvu itemov (z inventára postavy)
  SELECT COALESCE(SUM(i.itemmod), 0)
    INTO v_itemmod
  FROM combatitemdrop cid
  JOIN item i ON cid.item_id = i.item_id
  WHERE cid.inventory_id = (
    SELECT inventory_id
    FROM characterinventory
    WHERE character_id = p_caster_id
  )
  AND cid.istaken = true;

  v_effcost := v_baseapcost * v_catmod * (1 - v_sum_attr) * (1 - v_itemmod);
  IF v_effcost < 0 THEN
    v_effcost := 0;
  END IF;

  RETURN v_effcost;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION f_check_and_reset_round(p_combat_id INT) RETURNS VOID AS $$
DECLARE
    v_char1 INT;
    v_char2 INT;
    v_char1_ap INT;
    v_char2_ap INT;
    v_spell_cost INT;
    v_char1_can_cast BOOLEAN := FALSE;
    v_char2_can_cast BOOLEAN := FALSE;
BEGIN
    SELECT character_1_id, character_2_id INTO v_char1, v_char2 FROM combat WHERE combat_id = p_combat_id;

    IF v_char1 IS NULL OR v_char2 IS NULL THEN
        RETURN;
    END IF;

    SELECT actualap INTO v_char1_ap FROM "character" WHERE character_id = v_char1;
    SELECT actualap INTO v_char2_ap FROM "character" WHERE character_id = v_char2;

    FOR v_spell_cost IN SELECT spell_id FROM spell LOOP
        IF NOT v_char1_can_cast AND v_char1_ap >= f_effective_spell_cost(v_spell_cost, v_char1) THEN
            v_char1_can_cast := TRUE;
        END IF;
        IF NOT v_char2_can_cast AND v_char2_ap >= f_effective_spell_cost(v_spell_cost, v_char2) THEN
            v_char2_can_cast := TRUE;
        END IF;
        EXIT WHEN v_char1_can_cast AND v_char2_can_cast;
    END LOOP;

    IF NOT v_char1_can_cast AND NOT v_char2_can_cast THEN
        PERFORM sp_reset_round(p_combat_id);
    END IF;
END;
$$ LANGUAGE plpgsql;

---------------------------
-- 2) sp_cast_spell
---------------------------
CREATE OR REPLACE FUNCTION sp_cast_spell(
  p_caster_id INT,
  p_target_id INT,
  p_spell_id  INT
) RETURNS VOID AS
$$
DECLARE
  v_combat_id INT;
  v_caster_ap INT;
  v_cost      NUMERIC;
  v_roll      INT;
  v_hit       BOOLEAN;
  v_damage    NUMERIC := 0;
  v_target_ac INT;
  v_round     INT := 1;
  v_char1 INT;
  v_char2 INT;
  v_ap1 INT;
  v_ap2 INT;
  v_min_cost1 NUMERIC;
  v_min_cost2 NUMERIC;
  v_new_hp INT;
  v_base_damage INT;
  v_attr_type VARCHAR(50);
  v_attr_weight INT;
  v_attr_value INT;
  v_scaling NUMERIC;
BEGIN
  -- Nájdeme boj, v ktorom p_caster_id figuruje
  SELECT combat_id
    INTO v_combat_id
    FROM combat
    WHERE (character_1_id = p_caster_id OR character_2_id = p_caster_id)
      AND isactive = true
    LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Postava % nie je v aktívnom boji!', p_caster_id;
  END IF;

  -- Overíme, že cieľ (defender) je súčasťou rovnakého boja
  IF NOT EXISTS (
    SELECT 1 FROM combat
    WHERE combat_id = v_combat_id
      AND (character_1_id = p_target_id OR character_2_id = p_target_id)
  ) THEN
    RAISE EXCEPTION 'Postava % nie je účastníkom rovnakého boja ako útočník!', p_target_id;
  END IF;

  -- Získame ID oboch postáv v boji
  SELECT character_1_id, character_2_id
    INTO v_char1, v_char2
    FROM combat
    WHERE combat_id = v_combat_id;

  SELECT actualap INTO v_caster_ap
    FROM "character"
    WHERE character_id = p_caster_id;

  v_cost := f_effective_spell_cost(p_spell_id, p_caster_id);

  IF v_caster_ap < v_cost THEN
    RAISE EXCEPTION 'AP nedostatočné! (%.2f < %.2f)', v_caster_ap, v_cost;
  END IF;

  -- Odpočítaj AP
  UPDATE "character"
     SET actualap = actualap - v_cost
   WHERE character_id = p_caster_id;

  v_roll := (random()*20 + 1)::INT;  -- 1..20

  SELECT armorclass
    INTO v_target_ac
    FROM "character"
    WHERE character_id = p_target_id;

  IF v_roll >= v_target_ac THEN
    v_hit := TRUE;

    -- Získaj base damage
    SELECT basedamage INTO v_base_damage
    FROM spell
    WHERE spell_id = p_spell_id;

    -- Získaj dominantný atribút a jeho váhu
    SELECT attributetype, weight
      INTO v_attr_type, v_attr_weight
      FROM spellattributedependency
      WHERE spell_id = p_spell_id
      ORDER BY weight DESC
      LIMIT 1;

    -- Získaj hodnotu dominantného atribútu
    IF v_attr_type = 'Strength' THEN
      SELECT strength INTO v_attr_value FROM "character" WHERE character_id = p_caster_id;
    ELSIF v_attr_type = 'Dexterity' THEN
      SELECT dexterity INTO v_attr_value FROM "character" WHERE character_id = p_caster_id;
    ELSIF v_attr_type = 'Intelligence' THEN
      SELECT intelligence INTO v_attr_value FROM "character" WHERE character_id = p_caster_id;
    ELSIF v_attr_type = 'Constitution' THEN
      SELECT constitution INTO v_attr_value FROM "character" WHERE character_id = p_caster_id;
    ELSE
      v_attr_value := 0;
    END IF;

    -- Výpočet škálovania
    v_scaling := (v_attr_value * v_attr_weight) / 20.0;

    -- Výsledné poškodenie
    v_damage := v_base_damage * (1 + v_scaling);

    -- Zaokrúhlenie na celé číslo
    v_damage := round(v_damage);

    -- Zníž HP cieľa a získaj nové HP
    UPDATE "character"
       SET actualhealth = actualhealth - v_damage
     WHERE character_id = p_target_id
     RETURNING actualhealth INTO v_new_hp;

    -- Ak cieľ padol
    IF v_new_hp <= 0 THEN
      UPDATE "character"
         SET isincombat = false
       WHERE character_id = p_target_id;
    END IF;

  ELSE
    v_hit := FALSE;
    v_damage := 0;
  END IF;

  -- Zaloguj do CombatLog
  INSERT INTO combatlog(
    combat_id, attacker_id, defender_id,
    spell_id, actiontype, damage_dealt,
    hit, round, usedap
  ) VALUES(
    v_combat_id,
    p_caster_id,
    p_target_id,
    p_spell_id,
    'SPELL',
    v_damage,
    v_hit,
    f_get_current_round(v_combat_id),
    v_cost::INT
  );

  -- Kontrola konca kola a boja
  PERFORM f_check_and_reset_round(v_combat_id);
  PERFORM f_check_and_end_combat(v_combat_id);
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION f_check_and_end_combat(p_combat_id INT) RETURNS VOID AS $$
DECLARE
    v_char1 INT;
    v_char2 INT;
    v_hp1 INT;
    v_hp2 INT;
    v_drop RECORD;  
BEGIN
    SELECT character_1_id, character_2_id INTO v_char1, v_char2
    FROM combat
    WHERE combat_id = p_combat_id;

    IF v_char1 IS NULL OR v_char2 IS NULL THEN
        RETURN;
    END IF;

    SELECT actualhealth INTO v_hp1 FROM "character" WHERE character_id = v_char1;
    SELECT actualhealth INTO v_hp2 FROM "character" WHERE character_id = v_char2;

    -- Ak aspoň jeden z nich má 0 alebo menej HP, ukončíme boj
    IF v_hp1 <= 0 OR v_hp2 <= 0 THEN

        -- Ukonči samotný boj
        UPDATE combat
        SET isactive = false
        WHERE combat_id = p_combat_id;

        -- Vypni isincombat pre oboch
        UPDATE "character"
        SET isincombat = false
        WHERE character_id IN (v_char1, v_char2);

        -- Odhodenie itemov z inventárov + update postáv
        FOR v_drop IN
            SELECT combatitemdrop_id, inventory_id
            FROM combatitemdrop
            WHERE combat_id = p_combat_id
              AND inventory_id IS NOT NULL
        LOOP
            PERFORM sp_drop_item(
                v_drop.combatitemdrop_id,
                (SELECT character_id
                 FROM characterinventory
                 WHERE inventory_id = v_drop.inventory_id)
            );
        END LOOP;

        -- Zaloguj GAME_END
        INSERT INTO combatlog(
            combat_id,
            actiontype,
            round
        ) VALUES (
            p_combat_id,
            'GAME_END',
            f_get_current_round(p_combat_id)
        );
    END IF;
END;
$$ LANGUAGE plpgsql;





---------------------------
-- 3) sp_rest_character
---------------------------
CREATE OR REPLACE FUNCTION sp_rest_character(
  p_character_id INT
) RETURNS VOID AS
$$
DECLARE
  v_incombat BOOLEAN;
  v_actualhealth INT;
BEGIN
  SELECT isincombat, actualhealth
    INTO v_incombat, v_actualhealth
    FROM "character"
    WHERE character_id = p_character_id;

  IF v_incombat THEN
    RAISE EXCEPTION 'Postava % je v boji, nemôže odpočívať!', p_character_id;
  END IF;

  IF v_actualhealth <= 0 THEN
    RAISE EXCEPTION 'Postava % je mŕtva a nemôže odpočívať!', p_character_id;
  END IF;

  UPDATE "character"
     SET actualhealth = maxhealth,
         actualap = maxap
   WHERE character_id = p_character_id;
END;
$$ LANGUAGE plpgsql;


---------------------------
-- 4) sp_enter_combat (vylepšené o kontrolu isincombat)
--   (Vloží aj 4 náhodné itemy do boja, ak boj neexistoval)
---------------------------
CREATE OR REPLACE FUNCTION sp_enter_combat(
  p_combat_id   INT,
  p_character_id INT
) RETURNS VOID AS
$$
DECLARE
  v_char1  INT;
  v_char2  INT;
  v_isincombat BOOLEAN;
  v_actualhealth INT;

BEGIN
  -- Overíme, či je postava už v boji a či má pozitívne HP
  SELECT isincombat, actualhealth INTO v_isincombat, v_actualhealth
  FROM "character"
  WHERE character_id = p_character_id;

  IF v_actualhealth <= 0 THEN
    RAISE EXCEPTION 'Postava % má 0 alebo menej HP a nemôže vstúpiť do boja!', p_character_id;
  END IF;

  IF v_isincombat THEN
    RAISE EXCEPTION 'Postava % je už v boji!', p_character_id;
  END IF;


  -- Skontrolujeme, či combat_id už existuje
  IF NOT EXISTS (
    SELECT 1 
    FROM combat 
    WHERE combat_id = p_combat_id
  ) THEN
    -- Vytvoríme nový boj
    INSERT INTO combat(combat_id, isactive)
    VALUES (p_combat_id, true);

    -- Pridáme 4 náhodné itemy do boja
    INSERT INTO combatitemdrop(combat_id, item_id, inventory_id, istaken)
    SELECT p_combat_id, item_id, NULL, false
    FROM item
    ORDER BY random()
    LIMIT 4;
  END IF;

  -- Získame obsadenosť v boji
  SELECT character_1_id, character_2_id
    INTO v_char1, v_char2
    FROM combat
    WHERE combat_id = p_combat_id;

  -- Pridáme postavu do boja
  IF v_char1 IS NULL THEN
    UPDATE combat
       SET character_1_id = p_character_id
     WHERE combat_id = p_combat_id;
  ELSIF v_char2 IS NULL THEN
    UPDATE combat
       SET character_2_id = p_character_id
     WHERE combat_id = p_combat_id;
  ELSE
    RAISE EXCEPTION 'Tento boj (%) je už plný!', p_combat_id;
  END IF;

  -- Aktivujeme postavu a nastavíme jej AP
  UPDATE "character"
     SET isincombat = true,
         actualap   = maxap
   WHERE character_id = p_character_id;

  -- Log vstupu do boja
  INSERT INTO combatlog(
    combat_id,
    attacker_id,
    actiontype,
	round
  ) VALUES(
    p_combat_id,
    p_character_id,
    'JOIN',
	f_get_current_round(p_combat_id)
  );
END;
$$
LANGUAGE plpgsql;



---------------------------
-- 5) sp_loot_item
---------------------------
CREATE OR REPLACE FUNCTION sp_loot_item(
  p_combat_id INT,
  p_character_id INT,
  p_combatitemdrop_id INT
) RETURNS VOID AS
$$
DECLARE
  v_is_taken BOOLEAN;
  v_char_inv_id INT;
  v_curr_weight INT := 0;
  v_new_weight INT := 0;
  v_strength INT;
  v_constitution INT;
  v_max_weight INT;
  v_item_id INT;
  v_bonus_type VARCHAR(50);
  v_bonus_value INT;
BEGIN
  -- Získaj inventory ID postavy
  SELECT inventory_id
  INTO v_char_inv_id
  FROM characterinventory
  WHERE character_id = p_character_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Postava % nemá inventory!', p_character_id;
  END IF;

  -- Over, že postava je v danom boji
  IF NOT EXISTS (
    SELECT 1
    FROM combat
    WHERE combat_id = p_combat_id
      AND (character_1_id = p_character_id OR character_2_id = p_character_id)
  ) THEN
    RAISE EXCEPTION 'Postava % nie je účastníkom boja %!', p_character_id, p_combat_id;
  END IF;

  -- Získaj informáciu o danom dropnutom iteme
  SELECT item_id, istaken
  INTO v_item_id, v_is_taken
  FROM combatitemdrop
  WHERE combatitemdrop_id = p_combatitemdrop_id
    AND combat_id = p_combat_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'CombatItemDrop % neexistuje pre boj %!', p_combatitemdrop_id, p_combat_id;
  END IF;

  IF v_is_taken THEN
    RAISE EXCEPTION 'Item % (drop_id=%) je už vzatý!', v_item_id, p_combatitemdrop_id;
  END IF;

  -- Získaj aktuálnu hmotnosť inventára
  SELECT COALESCE(SUM(i.vaha), 0)
  INTO v_curr_weight
  FROM combatitemdrop cid
  JOIN item i ON i.item_id = cid.item_id
  WHERE cid.inventory_id = v_char_inv_id
    AND cid.istaken = true;

  -- Získaj vlastnosti itemu
  SELECT vaha, bonus_type, bonus_value
  INTO v_new_weight, v_bonus_type, v_bonus_value
  FROM item
  WHERE item_id = v_item_id;

  -- Získaj atribúty postavy
  SELECT strength, constitution
  INTO v_strength, v_constitution
  FROM "character"
  WHERE character_id = p_character_id;

	-- Získaj maximálnu kapacitu z inventára
	SELECT maxinventorysize INTO v_max_weight
	FROM characterinventory
	WHERE character_id = p_character_id;


  IF (v_curr_weight + v_new_weight) > v_max_weight THEN
    RAISE EXCEPTION 'Prekročená kapacita! (% + % > %)', v_curr_weight, v_new_weight, v_max_weight;
  END IF;

  -- Označ item ako vzatý a priraď inventár pomocou combatitemdrop_id
  UPDATE combatitemdrop
  SET inventory_id = v_char_inv_id,
      istaken = true
  WHERE combatitemdrop_id = p_combatitemdrop_id;

  -- Pripočítaj bonus k atribútu postavy
  IF v_bonus_type = 'Strength' THEN
    UPDATE "character" SET strength = strength + v_bonus_value WHERE character_id = p_character_id;
  ELSIF v_bonus_type = 'Dexterity' THEN
    UPDATE "character" SET dexterity = dexterity + v_bonus_value WHERE character_id = p_character_id;
  ELSIF v_bonus_type = 'Intelligence' THEN
    UPDATE "character" SET intelligence = intelligence + v_bonus_value WHERE character_id = p_character_id;
  ELSIF v_bonus_type = 'Constitution' THEN
    UPDATE "character" SET constitution = constitution + v_bonus_value WHERE character_id = p_character_id;
  ELSIF v_bonus_type = 'MaxHealth' THEN
    UPDATE "character" 
    SET maxhealth = maxhealth + v_bonus_value,
        actualhealth = actualhealth + v_bonus_value
    WHERE character_id = p_character_id;
  END IF;

  -- Prepočítaj odvodené hodnoty
  PERFORM sp_update_character_stats(p_character_id);

  -- Zaloguj akciu
  INSERT INTO combatlog(
    combat_id, attacker_id, combatitemdrop_id, actiontype, round
  ) VALUES(
    p_combat_id,
    p_character_id,
    p_combatitemdrop_id,
    'ITEM_PICKUP',
    f_get_current_round(p_combat_id)
  );
END;
$$ LANGUAGE plpgsql;




---------------------------
-- 6) sp_reset_round
---------------------------
CREATE OR REPLACE FUNCTION sp_reset_round(
  p_combat_id INT
) RETURNS VOID AS
$$
DECLARE
  v_char1 INT;
  v_char2 INT;
BEGIN
  SELECT character_1_id, character_2_id
    INTO v_char1, v_char2
    FROM combat
    WHERE combat_id=p_combat_id;

  IF v_char1 IS NOT NULL THEN
    UPDATE "character"
       SET actualap=maxap
     WHERE character_id=v_char1;
  END IF;
  IF v_char2 IS NOT NULL THEN
    UPDATE "character"
       SET actualap=maxap
     WHERE character_id=v_char2;
  END IF;

  INSERT INTO combatlog(
    combat_id, actiontype, round
  ) VALUES(
    p_combat_id,
    'RESET_ROUND',
	f_get_current_round(p_combat_id)+1
  );
END;
$$ LANGUAGE plpgsql;

--aktualne kolo
CREATE OR REPLACE FUNCTION f_get_current_round(p_combat_id INT) RETURNS INT AS $$
DECLARE
    v_round INT;
BEGIN
    SELECT COALESCE(MAX(round), 1)
      INTO v_round
      FROM combatlog
     WHERE combat_id = p_combat_id;

    RETURN v_round;
END;
$$ LANGUAGE plpgsql;



-- VIEW Popis: Aktuálne kolo, zoznam aktívnych postáv a ich zostávajúce AP.
CREATE OR REPLACE VIEW v_combat_state AS
SELECT
    cl.combat_id,
    c.character_id,
    c.name AS character_name,
    f_get_current_round( cl.combat_id) AS current_round,
    c.actualap
FROM combatlog cl
JOIN "character" c ON cl.attacker_id = c.character_id
JOIN combat co ON cl.combat_id = co.combat_id
WHERE co.isactive = true
GROUP BY cl.combat_id, c.character_id, c.name, c.actualap;

-- VIEW most damage Popis
CREATE OR REPLACE VIEW v_most_damage AS
SELECT
    c.character_id,
    c.name AS character_name,
    SUM(cl.damage_dealt) AS total_damage
FROM combatlog cl
JOIN "character" c ON cl.attacker_id = c.character_id
WHERE cl.damage_dealt IS NOT NULL
GROUP BY c.character_id, c.name
ORDER BY total_damage DESC;

-- VIEW v_strongest_characters : Výkonnosť postáv (poškodenie + zostávajúce zdravie).
CREATE OR REPLACE VIEW v_strongest_characters AS
SELECT
    c.character_id,
    c.name AS character_name,
    COALESCE(SUM(cl.damage_dealt), 0) AS total_damage,
    c.actualhealth,
    (COALESCE(SUM(cl.damage_dealt), 0) + c.actualhealth) AS performance_score
FROM "character" c
LEFT JOIN combatlog cl ON cl.attacker_id = c.character_id
GROUP BY c.character_id, c.name, c.actualhealth
ORDER BY performance_score DESC;

-- VIEW v_combat_damage
--  Súhrn poškodení podľa bojov.
CREATE OR REPLACE VIEW v_combat_damage AS
SELECT
    cl.combat_id,
    SUM(cl.damage_dealt) AS total_combat_damage
FROM combatlog cl
GROUP BY cl.combat_id
ORDER BY total_combat_damage DESC;

-- VIEW v_spell_statistics Štatistiky kúziel – počet použití, zásahy, celkové poškodenie.
CREATE OR REPLACE VIEW v_spell_statistics AS
SELECT
    s.spell_id,
    s.name AS spell_name,
    COUNT(cl.spell_id) AS times_used,
    SUM(CASE WHEN cl.hit THEN 1 ELSE 0 END) AS total_hits,
    SUM(cl.damage_dealt) AS total_damage
FROM spell s
LEFT JOIN combatlog cl ON cl.spell_id = s.spell_id
GROUP BY s.spell_id, s.name
ORDER BY total_damage DESC;


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


CREATE OR REPLACE FUNCTION sp_update_character_stats(p_character_id INT)
RETURNS VOID AS $$
DECLARE
    v_strength INT;
    v_dexterity INT;
    v_intelligence INT;
    v_constitution INT;
    v_class_id INT;
    v_classarmorbonus INT;
    v_inventorymodifier NUMERIC;
    v_apmodifier NUMERIC;
    v_armorclass INT;
    v_maxap INT;
    v_inventorysize INT;
    v_inventory_id INT;
BEGIN
    -- Získaj aktuálne atribúty a triedu postavy
    SELECT strength, dexterity, intelligence, constitution, class_id
    INTO v_strength, v_dexterity, v_intelligence, v_constitution, v_class_id
    FROM "character"
    WHERE character_id = p_character_id;

    -- Získaj modifikátory z tabuľky class
    SELECT classarmorbonus, inventorysizemodifier, actionpointsmodifier
    INTO v_classarmorbonus, v_inventorymodifier, v_apmodifier
    FROM class
    WHERE class_id = v_class_id;

    -- Prepočet hodnôt
    v_armorclass := 10 + (v_dexterity / 2) + v_classarmorbonus;
    v_maxap := ROUND((v_dexterity + v_intelligence) * v_apmodifier);
    v_inventorysize := ROUND((v_strength + v_constitution) * v_inventorymodifier);

    -- Aktualizácia postavy
    UPDATE "character"
    SET armorclass = v_armorclass,
        maxap = v_maxap,
        actualap = LEAST(actualap, v_maxap)  -- ak je potrebné obmedziť actualap
    WHERE character_id = p_character_id;

    -- Získaj ID inventára
    SELECT inventory_id INTO v_inventory_id
    FROM characterinventory
    WHERE character_id = p_character_id;

    -- Aktualizuj veľkosť inventára
    UPDATE characterinventory
    SET maxinventorysize = v_inventorysize
    WHERE inventory_id = v_inventory_id;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION sp_drop_item(
  p_combatitemdrop_id INT,
  p_character_id INT
) RETURNS VOID AS
$$
DECLARE
  v_item_id INT;
  v_bonus_type VARCHAR(50);
  v_bonus_value INT;
  v_inventory_id INT;
  v_owner_inventory_id INT;
BEGIN
  -- Získaj item_id a inventory_id z combatitemdrop
  SELECT item_id, inventory_id INTO v_item_id, v_inventory_id
  FROM combatitemdrop
  WHERE combatitemdrop_id = p_combatitemdrop_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'CombatItemDrop % neexistuje!', p_combatitemdrop_id;
  END IF;

  -- Získaj inventory_id, ktoré patrí characterovi
  SELECT inventory_id INTO v_owner_inventory_id
  FROM characterinventory
  WHERE character_id = p_character_id;

  -- Over či item naozaj patrí danému characterovi
  IF v_inventory_id IS DISTINCT FROM v_owner_inventory_id THEN
    RAISE EXCEPTION 'Postava % nevlastní item drop_id %!', p_character_id, p_combatitemdrop_id;
  END IF;
  -- Získaj bonus_type a bonus_value
  SELECT bonus_type, bonus_value INTO v_bonus_type, v_bonus_value
  FROM item
  WHERE item_id = v_item_id;

  -- Odrátaj bonus od atribútu postavy
  IF v_bonus_type = 'Strength' THEN
    UPDATE "character" SET strength = strength - v_bonus_value WHERE character_id = p_character_id;
  ELSIF v_bonus_type = 'Dexterity' THEN
    UPDATE "character" SET dexterity = dexterity - v_bonus_value WHERE character_id = p_character_id;
  ELSIF v_bonus_type = 'Intelligence' THEN
    UPDATE "character" SET intelligence = intelligence - v_bonus_value WHERE character_id = p_character_id;
  ELSIF v_bonus_type = 'Constitution' THEN
    UPDATE "character" SET constitution = constitution - v_bonus_value WHERE character_id = p_character_id;
  ELSIF v_bonus_type = 'MaxHealth' THEN
    UPDATE "character"
    SET maxhealth = maxhealth - v_bonus_value,
        actualhealth = LEAST(actualhealth, maxhealth - v_bonus_value)
    WHERE character_id = p_character_id;
  END IF;

  -- Odstráň item z inventára
  UPDATE combatitemdrop
  SET inventory_id = NULL,
      istaken = false
  WHERE combatitemdrop_id = p_combatitemdrop_id;

  -- Prepočet odvodených hodnôt
  PERFORM sp_update_character_stats(p_character_id);
END;
$$ LANGUAGE plpgsql;
