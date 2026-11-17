-- Enregistre le bilan du lot, relu par la supervision (volumes, historique des exécutions).
-- MERGE (SQL:2003) plutôt que INSERT ... ON CONFLICT, propre à PostgreSQL : la requête passe aussi sous Oracle.
-- Variables psql attendues : lot, lues, rejets.
MERGE INTO lot_traitement l
USING (
    SELECT f.lot,
           COUNT(*) AS nb_feuilles,
           SUM(f.montant) AS montant_presente,
           SUM(r.montant_rembourse) AS montant_rembourse,
           COUNT(DISTINCT r.id_assure) AS nb_paiements
    FROM feuille_soins f
    JOIN remboursement r ON r.id_feuille = f.id_feuille
    WHERE f.lot = DATE :'lot'
    GROUP BY f.lot
) s
ON (l.lot = s.lot)
WHEN MATCHED THEN
    UPDATE SET nb_lignes_lues = :lues,
               nb_rejets = :rejets,
               nb_feuilles = s.nb_feuilles,
               montant_presente = s.montant_presente,
               montant_rembourse = s.montant_rembourse,
               nb_paiements = s.nb_paiements,
               exporte_le = CURRENT_TIMESTAMP
WHEN NOT MATCHED THEN
    INSERT (lot, nb_lignes_lues, nb_rejets, nb_feuilles, montant_presente, montant_rembourse, nb_paiements, exporte_le)
    VALUES (s.lot, :lues, :rejets, s.nb_feuilles, s.montant_presente, s.montant_rembourse, s.nb_paiements, CURRENT_TIMESTAMP);
