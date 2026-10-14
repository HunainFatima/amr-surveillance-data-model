-- =====================================================================
-- AMR Surveillance Data Model  |  Hunain Fatima
-- Normalised (3NF) relational model for veterinary clinical microbiology
-- and antimicrobial susceptibility testing (AST) surveillance data.
-- All data is SYNTHETIC (invented for demonstration).
-- Safe to re-run: it deletes and rebuilds everything each time.
-- =====================================================================

PRAGMA foreign_keys = ON;

-- ---------- 0. Clean start (child objects first, then parents) ----------
DROP VIEW  IF EXISTS isolate_mdr;
DROP VIEW  IF EXISTS ast_corrected;
DROP TABLE IF EXISTS ast_result;
DROP TABLE IF EXISTS intrinsic_resistance;
DROP TABLE IF EXISTS isolate;
DROP TABLE IF EXISTS sample;
DROP TABLE IF EXISTS animal;
DROP TABLE IF EXISTS antimicrobial;
DROP TABLE IF EXISTS antimicrobial_class;
DROP TABLE IF EXISTS bacterium;
DROP TABLE IF EXISTS host_species;
DROP TABLE IF EXISTS animal_class;

-- ---------- 1. Reference (lookup) tables ----------
CREATE TABLE animal_class (
    animal_class_id   INTEGER PRIMARY KEY,
    class_name        TEXT NOT NULL UNIQUE
);

CREATE TABLE host_species (
    host_species_id   INTEGER PRIMARY KEY,
    animal_class_id   INTEGER NOT NULL REFERENCES animal_class(animal_class_id),
    scientific_name   TEXT NOT NULL UNIQUE,
    common_name       TEXT
);

CREATE TABLE bacterium (
    bacterium_id      INTEGER PRIMARY KEY,
    scientific_name   TEXT NOT NULL UNIQUE,
    gram_stain        TEXT CHECK (gram_stain IN ('positive','negative'))
);

CREATE TABLE antimicrobial_class (
    am_class_id       INTEGER PRIMARY KEY,
    class_name        TEXT NOT NULL UNIQUE
);

CREATE TABLE antimicrobial (
    antimicrobial_id  INTEGER PRIMARY KEY,
    name              TEXT NOT NULL UNIQUE,
    am_class_id       INTEGER NOT NULL REFERENCES antimicrobial_class(am_class_id),
    aware_category    TEXT CHECK (aware_category IN ('Access','Watch','Reserve'))
);

-- EUCAST expected (intrinsic) resistance: scientific rules stored as data
CREATE TABLE intrinsic_resistance (
    bacterium_id      INTEGER REFERENCES bacterium(bacterium_id),
    antimicrobial_id  INTEGER REFERENCES antimicrobial(antimicrobial_id),
    source            TEXT DEFAULT 'EUCAST Expected Resistant Phenotypes',
    PRIMARY KEY (bacterium_id, antimicrobial_id)
);

-- ---------- 2. Core tables ----------
CREATE TABLE animal (
    animal_id         INTEGER PRIMARY KEY,
    host_species_id   INTEGER NOT NULL REFERENCES host_species(host_species_id),
    sex               TEXT CHECK (sex IN ('M','F','U'))
);

CREATE TABLE sample (
    sample_id         INTEGER PRIMARY KEY,
    animal_id         INTEGER NOT NULL REFERENCES animal(animal_id),
    collection_date   DATE NOT NULL,
    sample_type       TEXT
);

CREATE TABLE isolate (
    isolate_id        INTEGER PRIMARY KEY,
    sample_id         INTEGER NOT NULL REFERENCES sample(sample_id),
    bacterium_id      INTEGER NOT NULL REFERENCES bacterium(bacterium_id)
);

-- Fact table. Grain: one isolate x one antimicrobial tested
CREATE TABLE ast_result (
    isolate_id        INTEGER REFERENCES isolate(isolate_id),
    antimicrobial_id  INTEGER REFERENCES antimicrobial(antimicrobial_id),
    interpretation    TEXT NOT NULL CHECK (interpretation IN ('S','I','R')),
    PRIMARY KEY (isolate_id, antimicrobial_id)
);

-- ---------- 3. Synthetic data ----------
INSERT INTO animal_class VALUES (1,'Mammalia'),(2,'Aves'),(3,'Reptilia');

INSERT INTO host_species VALUES
 (1,1,'Canis lupus familiaris','Dog'),
 (2,2,'Gallus gallus domesticus','Chicken'),
 (3,3,'Iguana iguana','Green iguana');

INSERT INTO bacterium VALUES
 (1,'Escherichia coli','negative'),
 (2,'Pseudomonas aeruginosa','negative'),
 (3,'Staphylococcus aureus','positive');

INSERT INTO antimicrobial_class VALUES
 (1,'Penicillins'),(2,'Fluoroquinolones'),(3,'Aminoglycosides'),(4,'Tetracyclines');

INSERT INTO antimicrobial VALUES
 (1,'Ampicillin',1,'Access'),
 (2,'Enrofloxacin',2,'Watch'),
 (3,'Gentamicin',3,'Access'),
 (4,'Doxycycline',4,'Access');

-- P. aeruginosa is intrinsically resistant to ampicillin and doxycycline
INSERT INTO intrinsic_resistance (bacterium_id, antimicrobial_id) VALUES (2,1),(2,4);

INSERT INTO animal VALUES (1,1,'M'),(2,2,'F'),(3,3,'U');

INSERT INTO sample VALUES
 (1,1,'2010-03-14','faeces'),
 (2,2,'2018-07-02','wound swab'),
 (3,3,'2024-11-20','faeces');

INSERT INTO isolate VALUES (1,1,1),(2,2,2),(3,3,3),(4,3,1);

INSERT INTO ast_result VALUES
 (1,1,'R'),(1,2,'R'),(1,3,'R'),(1,4,'S'),   -- E. coli: R in 3 classes -> MDR
 (2,1,'R'),(2,2,'S'),(2,3,'S'),(2,4,'R'),   -- P. aeruginosa: R only intrinsic -> not MDR
 (3,1,'R'),(3,2,'S'),(3,3,'S'),(3,4,'S'),   -- S. aureus: R in 1 class -> not MDR
 (4,1,'R'),(4,2,'R'),(4,3,'S'),(4,4,'R');   -- E. coli: R in 3 classes -> MDR

-- ---------- 4. Analytical views ----------
-- Results with EUCAST intrinsic resistance removed
CREATE VIEW ast_corrected AS
SELECT r.*
FROM ast_result r
JOIN isolate i ON i.isolate_id = r.isolate_id
WHERE NOT EXISTS (
    SELECT 1 FROM intrinsic_resistance ir
    WHERE ir.bacterium_id = i.bacterium_id
      AND ir.antimicrobial_id = r.antimicrobial_id);

-- MDR = non-susceptible to >=1 agent in >=3 classes (Magiorakos et al., 2012)
CREATE VIEW isolate_mdr AS
SELECT i.isolate_id,
       COUNT(DISTINCT CASE WHEN c.interpretation IN ('R','I') THEN a.am_class_id END) AS resistant_classes,
       CASE WHEN COUNT(DISTINCT CASE WHEN c.interpretation IN ('R','I') THEN a.am_class_id END) >= 3
            THEN 1 ELSE 0 END AS is_mdr
FROM isolate i
JOIN ast_corrected c ON c.isolate_id = i.isolate_id
JOIN antimicrobial a ON a.antimicrobial_id = c.antimicrobial_id
GROUP BY i.isolate_id;

-- ---------- 5. Analytical queries (run one at a time) ----------

-- Q0: Readable results - JOIN turns the IDs in ast_result into names
SELECT i.isolate_id,
       hs.common_name      AS animal,
       b.scientific_name   AS bacterium,
       a.name              AS antimicrobial,
       a.aware_category    AS aware,
       r.interpretation    AS result
FROM ast_result r
JOIN isolate i       ON i.isolate_id = r.isolate_id
JOIN bacterium b     ON b.bacterium_id = i.bacterium_id
JOIN antimicrobial a ON a.antimicrobial_id = r.antimicrobial_id
JOIN sample s        ON s.sample_id = i.sample_id
JOIN animal an       ON an.animal_id = s.animal_id
JOIN host_species hs ON hs.host_species_id = an.host_species_id
ORDER BY i.isolate_id;

-- Q1: MDR rate by animal class
SELECT ac.class_name,
       COUNT(*) AS isolates,
       SUM(m.is_mdr) AS mdr_isolates,
       ROUND(100.0 * SUM(m.is_mdr) / COUNT(*), 1) AS mdr_pct
FROM isolate_mdr m
JOIN isolate i       ON i.isolate_id = m.isolate_id
JOIN sample s        ON s.sample_id = i.sample_id
JOIN animal an       ON an.animal_id = s.animal_id
JOIN host_species hs ON hs.host_species_id = an.host_species_id
JOIN animal_class ac ON ac.animal_class_id = hs.animal_class_id
GROUP BY ac.class_name;

-- Q2: Resistance % per antimicrobial and AWaRe category (corrected)
SELECT a.name, a.aware_category,
       COUNT(*) AS tested,
       ROUND(100.0 * SUM(c.interpretation = 'R') / COUNT(*), 1) AS resistant_pct
FROM ast_corrected c
JOIN antimicrobial a ON a.antimicrobial_id = c.antimicrobial_id
GROUP BY a.name, a.aware_category
ORDER BY resistant_pct DESC;

-- Q3: Impact of the EUCAST correction (raw vs corrected resistant results)
SELECT (SELECT COUNT(*) FROM ast_result    WHERE interpretation = 'R') AS raw_R,
       (SELECT COUNT(*) FROM ast_corrected WHERE interpretation = 'R') AS corrected_R;

-- Q4: CTE + window functions: resistance % per AWaRe category per year,
-- ranked within each year, with change versus the previous year
WITH yearly AS (
    SELECT strftime('%Y', s.collection_date) AS yr,
           a.aware_category,
           ROUND(100.0 * SUM(c.interpretation = 'R') / COUNT(*), 1) AS resistant_pct
    FROM ast_corrected c
    JOIN isolate i       ON i.isolate_id = c.isolate_id
    JOIN sample s        ON s.sample_id = i.sample_id
    JOIN antimicrobial a ON a.antimicrobial_id = c.antimicrobial_id
    GROUP BY yr, a.aware_category
)
SELECT yr, aware_category, resistant_pct,
       RANK() OVER (PARTITION BY yr ORDER BY resistant_pct DESC) AS rank_in_year,
       resistant_pct - LAG(resistant_pct) OVER (PARTITION BY aware_category ORDER BY yr) AS change_vs_prev
FROM yearly
ORDER BY yr, rank_in_year;
