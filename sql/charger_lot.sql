-- Remplace le contenu du lot par celui de la table d'import, en une seule transaction :
-- en cas d'erreur, le lot reste dans son état précédent.
-- Les remboursements du lot sont supprimés aussi : ils ne correspondent plus aux données chargées.
BEGIN;

DELETE FROM remboursement WHERE lot = DATE :'lot';
DELETE FROM feuille_soins WHERE lot = DATE :'lot';

INSERT INTO feuille_soins (id_feuille, lot, id_assure, id_professionnel, date_soins, code_acte, montant, ald)
SELECT id_feuille,
       DATE :'lot',
       id_assure,
       id_professionnel,
       CAST(date_soins AS DATE),
       code_acte,
       CAST(montant AS NUMERIC(10,2)),
       ald
FROM feuille_soins_import;

COMMIT;
