-- Schéma de la chaîne de remboursements. Rejouable : les objets existants sont conservés.
-- Types et contraintes en SQL standard. Écarts avec Oracle : IF NOT EXISTS (absent avant
-- Oracle 23ai) et la clause VALUES de la source du MERGE (SELECT ... FROM dual sous Oracle).

CREATE TABLE IF NOT EXISTS taux_remboursement (
    code_acte  VARCHAR(4)   PRIMARY KEY,
    libelle    VARCHAR(40)  NOT NULL,
    taux       NUMERIC(5,2) NOT NULL CHECK (taux BETWEEN 0 AND 100)
);

-- Table tampon du chargement : tout en texte pour que le COPY ne rejette rien,
-- les conversions se font à l'insertion dans feuille_soins.
CREATE TABLE IF NOT EXISTS feuille_soins_import (
    id_feuille        VARCHAR(40),
    id_assure         VARCHAR(40),
    id_professionnel  VARCHAR(40),
    date_soins        VARCHAR(40),
    code_acte         VARCHAR(40),
    montant           VARCHAR(40),
    ald               VARCHAR(40)
);

CREATE TABLE IF NOT EXISTS feuille_soins (
    id_feuille        VARCHAR(20)   PRIMARY KEY,
    lot               DATE          NOT NULL,
    id_assure         VARCHAR(20)   NOT NULL,
    id_professionnel  VARCHAR(20)   NOT NULL,
    date_soins        DATE          NOT NULL,
    code_acte         VARCHAR(4)    NOT NULL REFERENCES taux_remboursement (code_acte),
    montant           NUMERIC(10,2) NOT NULL CHECK (montant > 0),
    ald               CHAR(1)       NOT NULL CHECK (ald IN ('O', 'N'))
);
CREATE INDEX IF NOT EXISTS ix_feuille_soins_lot ON feuille_soins (lot);

CREATE TABLE IF NOT EXISTS remboursement (
    id_feuille         VARCHAR(20)   PRIMARY KEY REFERENCES feuille_soins (id_feuille),
    lot                DATE          NOT NULL,
    id_assure          VARCHAR(20)   NOT NULL,
    taux_applique      NUMERIC(5,2)  NOT NULL,
    montant_rembourse  NUMERIC(10,2) NOT NULL,
    calcule_le         TIMESTAMP     NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_remboursement_lot ON remboursement (lot);

-- Bilan par lot, alimenté à l'export et relu par la supervision.
CREATE TABLE IF NOT EXISTS lot_traitement (
    lot                DATE          PRIMARY KEY,
    nb_lignes_lues     INTEGER       NOT NULL,
    nb_rejets          INTEGER       NOT NULL,
    nb_feuilles        INTEGER       NOT NULL,
    montant_presente   NUMERIC(12,2) NOT NULL,
    montant_rembourse  NUMERIC(12,2) NOT NULL,
    nb_paiements       INTEGER       NOT NULL,
    exporte_le         TIMESTAMP     NOT NULL
);

-- Taux volontairement simplifiés, sans valeur réglementaire.
MERGE INTO taux_remboursement t
USING (VALUES ('CONS', 'Consultation', 70.00),
              ('VISI', 'Visite à domicile', 70.00),
              ('INFI', 'Acte infirmier', 60.00),
              ('KINE', 'Séance de kinésithérapie', 60.00),
              ('PHAR', 'Délivrance en pharmacie', 65.00)) AS s (code_acte, libelle, taux)
ON (t.code_acte = s.code_acte)
WHEN MATCHED THEN
    UPDATE SET libelle = s.libelle, taux = s.taux
WHEN NOT MATCHED THEN
    INSERT (code_acte, libelle, taux) VALUES (s.code_acte, s.libelle, s.taux);
