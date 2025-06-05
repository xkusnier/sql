-- -- -- -- -- USE CASE: PRIDANIE POSTAV DO BOJA -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
--Pre funkcnost testov ich treba vykonavat v poradi, v ktorom su napisane. Databaza je nato pripravena (nieje pripravena na ine poradie).

-- Pozitívny test - pridanie postavy do boja a vytvorenie boju
-- OČAKÁVANÝ VÝSTUP: postava ID=1 sa pridá do boja 99, vznikne záznam v `combat`, `combatlog`, `combatitemdrop`
SELECT sp_enter_combat(99, 1);
SELECT * FROM combat;           -- kontrola či je postava s id_1 v boji a či sa boj vytvoril
SELECT * FROM combatlog;        -- kontrola logu vstupu do boja
SELECT * FROM combatitemdrop;   -- kontrola pridaných itemov do boja

-- Negatívny test - pridanie do boja postavi, ktora uz v boji je
-- OČAKÁVANÝ VÝSTUP: chyba - postava je už v boji = ERROR:  Postava 1 je už v boji!
SELECT sp_enter_combat(98, 1);
SELECT * FROM combat;           -- kontrola ze postava nieje v boji 98

-- Negatívny test - pridanie mrtvej postavy do boja
-- OČAKÁVANÝ VÝSTUP: ERROR:  Postava 3 má 0 alebo menej HP a nemôže vstúpiť do boja!
UPDATE "character" SET actualhealth = 0 WHERE character_id = 3; -- pre jednoduchost setneme postave 3 0hp (je mrtva)
SELECT sp_enter_combat(99, 3);
SELECT * FROM combat;           -- kontrola ze postava nieje v boji
UPDATE "character" SET actualhealth = maxhealth WHERE character_id = 3; -- vratenie HPcok naspat

-- Pozitívny test - pridanie druhej postavy do boja
-- OČAKÁVANÝ VÝSTUP: druhá postava sa úspešne pridá do boja 99
SELECT sp_enter_combat(99, 2);
SELECT * FROM combat;           -- boj obsahuje obe postavy - pridanie postavy 2 s id_2
SELECT * FROM combatlog;        -- pridaný záznam o vstupe postavy ID=2

-- Negatívny test - pridanie tretieho characteru do boju - boj je iba 1 vs 1
-- OČAKÁVANÝ VÝSTUP: chyba - boj je už plný - ERROR:  Tento boj (99) je už plný! (boj je 1 vs 1)
SELECT sp_enter_combat(99, 3);


-- -- -- -- USE CASE: ITEM PICKUP -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 

-- Pozitívny test
-- OČAKÁVANÝ VÝSTUP: postava 1 zoberie item 1(combatitemdrop id_1), záznam v combatitemdrop
SELECT sp_loot_item(99, 1, 1);
SELECT * FROM combatitemdrop;                     -- item je priradený inventáru postavy
SELECT * FROM combatlog ; -- log akcie

-- Negatívny test - prevzatie itemu, ktori uz je v niakom inventari
-- OČAKÁVANÝ VÝSTUP: chyba - item už bol vzatý - ERROR:  Item 1 je už vzatý!
SELECT sp_loot_item(99, 2, 1);
SELECT * FROM combatitemdrop;  -- overenie, ze item stale vlastni postava 1

-- Negatívny test - postava nieje v boji
-- OČAKÁVANÝ VÝSTUP: chyba - ERROR:  Postava 3 nie je účastníkom boja 99!
SELECT sp_loot_item(99, 3, 4); 
SELECT * FROM combatitemdrop;  -- overenie, ze postava nevlastni item

-- Negatívny test -- item sa nezmesti do inventara
-- OČAKÁVANÝ VÝSTUP: chyba - prekročená kapacita (item váži viac ako postava unesie) ERROR:  Prekročená kapacita!
UPDATE characterinventory SET maxinventorysize = 1 WHERE character_id = 2; -- pre jednoznacny test nastavime characteru s id2 maxinventorysize na hodnotu 1
SELECT sp_loot_item(99, 2, 3);		-- ERROR:  Prekročená kapacita! (0 + 3 > 1)		
SELECT * FROM characterinventory; -- kapacita inventára
SELECT * FROM combatitemdrop;     -- overenie že item 4 nebol vzatý
SELECT sp_update_character_stats(2); -- vratenie povodneho maxinventorysize pre postavu

-- Pozitívny test
-- OČAKÁVANÝ VÝSTUP: po zodvihnutí sa pripočíta bonus k atribútu a nanovo sa vypočítajú odvodené hodnoty
SELECT character_id, strength, intelligence, dexterity, constitution FROM "character" WHERE character_id = 1;  -- zapamätaj si pôvodné hodnoty
SELECT * FROM combatitemdrop JOIN item USING (item_id) WHERE combat_id = 99;  -- overíme, aký buff má item s drop_id=1
SELECT sp_loot_item(99, 1, 2);  -- postava zoberie item s buffom (napr. Strength +2)
-- očakávame vyššiu hodnotu zvoleneho atribútu
SELECT character_id, strength, intelligence, dexterity, constitution FROM "character" WHERE character_id = 1; -- očakávame vyššiu hodnotu zvoleneho atribútu


-- -- -- -- USE CASE: ITEM DROP -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 

-- Pozitivny test - vyhodenie itemu, ktori postave nepatri 
-- OČAKÁVANÝ VÝSTUP: ERROR:  Postava 2 nevlastní item drop_id 2!
SELECT sp_drop_item(2, 2); -- ERROR:  Postava 2 nevlastní item drop_id 2!
SELECT * FROM combatitemdrop WHERE combat_id = 99; 

-- Pozitívny test - vyhodenie itemu
-- OČAKÁVANÝ VÝSTUP: postava ID=1 zhodí item s combatitemdrop_id=1
SELECT sp_drop_item(1, 1);
SELECT * FROM combatitemdrop WHERE combat_id = 99;  -- item by mal byť istaken=false

-- Pozitívny test – zahodenie itemu, ktorý mal buff -- skontrolovat !!!!!!!!!!
-- OČAKÁVANÝ VÝSTUP: odpočíta sa príslušný buff (napr. Strength - 2) 
SELECT * FROM combatitemdrop JOIN item USING (item_id) WHERE combat_id = 99; -- zobrazenie okolko ma ktory item aky atribut buffnut
SELECT character_id, strength,intelligence,dexterity,constitution FROM "character" WHERE character_id = 1;  -- zapamatame si hodnoty pred dropom itemu (+1 constitution)
SELECT sp_drop_item(1, 1); -- zahodíme item s drop_id=1, ktorý mal buff 
SELECT character_id,  strength,intelligence,dexterity,constitution FROM "character" WHERE character_id = 1; -- očakávame nizsiu hodnotu u daneho atributu (constitution 7)


-- -- -- -- -- --  USE CASE: CASTOVANIE SPELLU  -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 

-- Pozitívny test
-- OČAKÁVANÝ VÝSTUP: postava 2 zaútočí na postavu 1 spellom ID=3, log akcie
SELECT sp_cast_spell(2, 1, 3);
SELECT * FROM v_combat_state; -- VIEW USECASE
SELECT * FROM combatlog; -- zistenie, used ap
SELECT character_id, name, actualap, maxap, actualhealth, maxhealth FROM "character"; -- porovnanie usedap

-- Negatívny test - neexistujuce spellID
-- OČAKÁVANÝ VÝSTUP: chyba - spell ID 5 neexistuje
SELECT sp_cast_spell(2, 1, 5);
SELECT * FROM combatlog; -- spell sa nezapisal

-- Negatívny test - zautocenie na neexistujucu postavu
-- OČAKÁVANÝ VÝSTUP: chyba - Postava 7 nie je v aktívnom boji!
SELECT sp_cast_spell(7, 1, 3);
SELECT * FROM combatlog; -- overenie

-- Negatívny test - zautocenie na postavu, ktora neni v boji
-- OČAKÁVANÝ VÝSTUP: ERROR:  Postava 3 nie je účastníkom rovnakého boja ako útočník!
SELECT sp_cast_spell(2, 3, 3);
SELECT * FROM combatlog; -- overenie

-- Negatívny test
-- OČAKÁVANÝ VÝSTUP: chyba - nedostatok AP
SELECT sp_cast_spell(1, 2, 3);
SELECT * FROM combatlog; -- overenie

-- -- USE CASE CAST SPELL 2 + sp_reset_round
-- Pozitívny test
-- OČAKÁVANÝ VÝSTUP: automaticky sa spustí reset kola a zapise sa do combatlogu RESET_ROUND. nasledne sa resetuju actualap characterov
UPDATE "character" SET actualap = 5 WHERE character_id = 2;
SELECT sp_cast_spell(2, 1, 1); -- pri tomto caste urcite dojde ap kedze spell stoji 4 AP a postava 2 ma 5 AP a postava 1 ma 3 AP
SELECT * FROM combatlog WHERE combat_id = 99 ORDER BY combatlog_id ASC; -- overenie RESET_ROUND v combatlogu
SELECT character_id, name, actualap, maxap FROM "character"; -- overenie resetu AP

-- -- -- USECASE CASTOVANIE SPELLU 3 
-- Pozitívny test - overenie funkcnosti trafenia cielu
-- OČAKÁVANÝ VÝSTUP:- postava urcite nezasiahne ciel 
UPDATE "character" SET armorclass = 100 WHERE character_id = 1;  -- cieľ má veľmi vysokú AC
SELECT sp_cast_spell(2, 1, 1);  -- castnutie spellu
SELECT * FROM combatlog ORDER BY combatlog_id DESC LIMIT 1; -- kontrola že hit=false

-- Pozitívny test - overenie funkcnosti trafenia cielu
-- OČAKÁVANÝ VÝSTUP:- postava urcite zasiahne ciel 
UPDATE "character" SET armorclass = 1 WHERE character_id = 1;  -- cieľ má veľmi nízku AC
SELECT sp_cast_spell(2, 1, 1);  -- castnutie spellu
SELECT * FROM combatlog ORDER BY combatlog_id DESC LIMIT 1; -- kontrola že hit=true



-- -- USE CASE CASTOVANIE SPELLU 4: ZABITIE POSTAVY A UKONCENIE BOJA -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 

-- Pozitívny test
-- OČAKÁVANÝ VÝSTUP: po viacerých útokoch padne postava a boj sa ukončí (GAME_END)
SELECT sp_cast_spell(2, 1, 1);  -- opakovať podľa potreby
SELECT * FROM "character";     -- kontrola HP a isincombat
SELECT * FROM combatlog;       -- očakávame záznam o GAME_END
SELECT * FROM combatitemdrop;  -- itemy by mali byť na zemi
SELECT * FROM combat;  -- isactive = false


-- -- -- -- -- --  USE CASE: sp_rest_character -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 

-- Pozitívny test - odpocivanie mimo boju zivej postavy
-- OČAKÁVANÝ VÝSTUP: actualhealth sa bude rovnat maxhealth
UPDATE "character" SET actualhealth = 1 WHERE character_id = 3; -- pre jednoduchost setneme postave 3 1hp
SELECT character_id, name,actualhealth, maxhealth FROM "character" WHERE character_id=3; -- zapamatanie aktualnych hp
SELECT sp_rest_character(3);
SELECT character_id, name,actualhealth, maxhealth FROM "character" WHERE character_id=3; -- overie pridania HP


-- Negatívny test - odpocivanie v boji
-- OČAKÁVANÝ VÝSTUP: chyba - Postava 2 je v boji, nemôže odpočívať!
UPDATE "character" SET actualhealth = 1 WHERE character_id = 2;
SELECT sp_enter_combat(98, 2);
SELECT sp_rest_character(2);
SELECT character_id, name, actualhealth, maxhealth FROM "character"; -- stale ma 1 HP

-- Negatívny test - odpocivanie mrtvej postavy
-- OČAKÁVANÝ VÝSTUP: Postava 3 je mŕtva a nemôže odpočívať!
UPDATE "character" SET actualhealth = 0 WHERE character_id = 3; -- pre jednoduchost setneme postave 3 0hp (je mrtva)
SELECT sp_rest_character(3);


SELECT * FROM v_most_damage; -- VIEW MOST DAMAGE
SELECT * FROM v_strongest_characters; -- VIEW strongest 
SELECT * FROM v_combat_damage; -- VIEW --  Súhrn poškodení podľa bojov.
SELECT * FROM v_spell_statistics --view Štatistiky kúziel
-- -- -- -- -- --  USE CASE: f_effective_spell_cost -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- Pozitívny test
-- OČAKÁVANÝ VÝSTUP: Funkcia vráti číselnú hodnotu efektívneho AP costu pre spell ID=2 a postavu ID=2,
-- ktorá závisí od baseapcost, spellcategory.category_value a atribútov postavy (napr. strength, intelligence...)
-- pri zmene atributov sa zmeni hodnota spell cost
UPDATE "character" SET strength = 0, intelligence = 0, dexterity = 0, constitution = 0 WHERE character_id = 2;
SELECT f_effective_spell_cost(2, 2); -- efektívny cost bude blízko baseapcost

UPDATE "character" SET strength = 5, intelligence = 5, dexterity = 5, constitution = 5 WHERE character_id = 2;
SELECT f_effective_spell_cost(2, 2); -- efektívny cost klesne

-- -- -- -- -- -- -- -- -- -- --  USE CASE: update character -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- tato procedura sa vola vo pri funkciac, kde sa meni strength, dexterity,intelligence alebo constitution. Kedze od tychto atributov zavisia ostatne
-- konkretne atributy : v_armorclass, v_maxap, v_inventorysize
SELECT c.character_id, c.armorclass, c.maxap, ci.maxinventorysize FROM "character" cJOIN characterinventory ci ON c.character_id = ci.character_idWHERE c.character_id = 2;

-- Pred prípravou zmeníme atribúty postavy ID=1
UPDATE "character" SET strength = 5, dexterity = 10, intelligence = 8, constitution = 6 WHERE character_id = 2;

-- Zavoláme aktualizačnú procedúru
SELECT sp_update_character_stats(2);

-- Overíme výsledok:
-- ArmorClass je : 10 + (dexterity/2) + classarmorbonus
-- MaxAP je : round((dexterity + intelligence) * actionpointsmodifier)
-- MaxInventorySize je : round((strength + constitution) * inventorysizemodifier)
SELECT c.character_id, c.armorclass, c.maxap, ci.maxinventorysizeFROM "character" cJOIN characterinventory ci ON c.character_id = ci.character_idWHERE c.character_id = 2;


