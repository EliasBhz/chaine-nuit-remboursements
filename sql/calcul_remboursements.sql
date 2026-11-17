-- Calcul des remboursements du lot, règles volontairement simplifiées :
-- taux de l'acte, porté à 100 % pour une affection longue durée (ald = 'O'), arrondi au centime.
-- SQL standard (CASE, CAST, ROUND, CURRENT_TIMESTAMP) : la requête passe aussi sous Oracle.
-- Le lot est recalculé entièrement à chaque passage, ce qui rend le job rejouable.
BEGIN;

DELETE FROM remboursement WHERE lot = DATE :'lot';

INSERT INTO remboursement (id_feuille, lot, id_assure, taux_applique, montant_rembourse, calcule_le)
SELECT f.id_feuille,
       f.lot,
       f.id_assure,
       CASE WHEN f.ald = 'O' THEN 100 ELSE t.taux END,
       ROUND(f.montant * CASE WHEN f.ald = 'O' THEN 100 ELSE t.taux END / 100, 2),
       CURRENT_TIMESTAMP
FROM feuille_soins f
JOIN taux_remboursement t ON t.code_acte = f.code_acte
WHERE f.lot = DATE :'lot';

COMMIT;
