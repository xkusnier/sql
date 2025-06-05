-- 1) DROP existujúcich tabuliek a pohľadov

DROP TABLE IF EXISTS combatlog CASCADE;
DROP TABLE IF EXISTS combatitemdrop CASCADE;
DROP TABLE IF EXISTS combat CASCADE;
DROP TABLE IF EXISTS characterinventory CASCADE;
DROP TABLE IF EXISTS "character" CASCADE;
DROP TABLE IF EXISTS class CASCADE;
DROP TABLE IF EXISTS item CASCADE;
DROP TABLE IF EXISTS spellattributedependency CASCADE;
DROP TABLE IF EXISTS spell CASCADE;
DROP TABLE IF EXISTS spellcategory CASCADE;

-- 2) Vytvorenie tabuliek
CREATE TABLE class (
    class_id    INT PRIMARY KEY,  -- Nepoužívame SERIAL, aby sme mohli explicitne vložiť 1,2,3
    name        VARCHAR(100) NOT NULL,
    classarmorbonus INT NOT NULL DEFAULT 0,
    inventorysizemodifier NUMERIC NOT NULL DEFAULT 1.0,
    actionpointsmodifier NUMERIC NOT NULL DEFAULT 1.0
);

CREATE TABLE "character" (
    character_id    SERIAL PRIMARY KEY,
    name            VARCHAR(100) NOT NULL,
    strength        INT NOT NULL,
    dexterity       INT NOT NULL,
    intelligence    INT NOT NULL,
    constitution    INT NOT NULL,
    armorclass      INT NOT NULL,
    isincombat      BOOLEAN NOT NULL DEFAULT false,
    maxap           INT NOT NULL,
    actualap        INT NOT NULL,
    maxhealth       INT NOT NULL,
    actualhealth    INT NOT NULL,
    class_id        INT NOT NULL,
    CONSTRAINT fk_character_class
        FOREIGN KEY (class_id) REFERENCES class(class_id)
);

CREATE TABLE combat (
    combat_id      SERIAL PRIMARY KEY,
    character_1_id INT,
    character_2_id INT,
    isactive       BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE combatlog (
    combatlog_id       SERIAL PRIMARY KEY,
    combat_id          INT NOT NULL,
    attacker_id        INT,
    defender_id        INT,
    combatitemdrop_id  INT,
    spell_id           INT,
    actiontype   VARCHAR(30),
    damage_dealt       INT,
    hit                BOOLEAN,
    round              INT,
    usedap             INT
);

CREATE TABLE combatitemdrop (
    combatitemdrop_id  SERIAL PRIMARY KEY,
    combat_id          INT NOT NULL,
    inventory_id       INT,
    istaken            BOOLEAN NOT NULL DEFAULT false,
    item_id            INT NOT NULL
);

CREATE TABLE characterinventory (
    inventory_id       SERIAL PRIMARY KEY,
    character_id       INT NOT NULL,
    maxinventorysize   INT NOT NULL
);

CREATE TABLE item (
    item_id      SERIAL PRIMARY KEY,
    name         VARCHAR(100) NOT NULL,
    vaha         INT NOT NULL,
    bonus_type   VARCHAR(50),       -- napr. 'Strength', 'Intelligence', ...
    bonus_value  INT DEFAULT 0,      -- o koľko daný atribút zvyšuje
	itemmod NUMERIC DEFAULT 0
);


CREATE TABLE spellcategory (
    spellcat_id   SERIAL PRIMARY KEY,
    category_value NUMERIC NOT NULL DEFAULT 1.0
);

CREATE TABLE spell (
    spell_id     SERIAL PRIMARY KEY,
    spellcat_id  INT NOT NULL,
    name         VARCHAR(100) NOT NULL,
    baseapcost   INT NOT NULL,
    basedamage   INT NOT NULL
);

CREATE TABLE spellattributedependency (
    spell_id       INT NOT NULL,
    attributetype  VARCHAR(50) NOT NULL,
    weight         INT NOT NULL,
    PRIMARY KEY (spell_id, attributetype)
);

-- 3) Definícia cudzích kľúčov
ALTER TABLE combat
    ADD CONSTRAINT fk_combat_char1
        FOREIGN KEY (character_1_id) REFERENCES "character"(character_id),
    ADD CONSTRAINT fk_combat_char2
        FOREIGN KEY (character_2_id) REFERENCES "character"(character_id);

ALTER TABLE combatlog
    ADD CONSTRAINT fk_combatlog_combat
        FOREIGN KEY (combat_id) REFERENCES combat(combat_id),
    ADD CONSTRAINT fk_combatlog_attacker
        FOREIGN KEY (attacker_id) REFERENCES "character"(character_id),
    ADD CONSTRAINT fk_combatlog_defender
        FOREIGN KEY (defender_id) REFERENCES "character"(character_id),
    ADD CONSTRAINT fk_combatlog_spell
        FOREIGN KEY (spell_id) REFERENCES spell(spell_id),
    ADD CONSTRAINT fk_combatlog_cidrop
        FOREIGN KEY (combatitemdrop_id) REFERENCES combatitemdrop(combatitemdrop_id);

ALTER TABLE combatitemdrop
    ADD CONSTRAINT fk_cidrop_combat
        FOREIGN KEY (combat_id) REFERENCES combat(combat_id),
    ADD CONSTRAINT fk_cidrop_inventory
        FOREIGN KEY (inventory_id) REFERENCES characterinventory(inventory_id),
    ADD CONSTRAINT fk_cidrop_item
        FOREIGN KEY (item_id) REFERENCES item(item_id);

ALTER TABLE characterinventory
    ADD CONSTRAINT fk_inventory_character
        FOREIGN KEY (character_id) REFERENCES "character"(character_id);

ALTER TABLE spell
    ADD CONSTRAINT fk_spell_spellcategory
        FOREIGN KEY (spellcat_id) REFERENCES spellcategory(spellcat_id);

ALTER TABLE spellattributedependency
    ADD CONSTRAINT fk_spelldep_spell
        FOREIGN KEY (spell_id) REFERENCES spell(spell_id);

-- 4) Indexy
CREATE INDEX idx_combatlog_combat ON combatlog (combat_id);
CREATE INDEX idx_character_name    ON "character" (name);
CREATE INDEX idx_spell_name        ON spell (name);
