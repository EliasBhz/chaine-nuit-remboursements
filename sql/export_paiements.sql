-- Un paiement par assuré pour le lot, numéroté de façon stable (tri sur l'assuré)
-- pour qu'un rejeu produise exactement le même fichier.
SELECT 'PAI-' || :'date_traitement' || '-' || LPAD(CAST(ROW_NUMBER() OVER (ORDER BY id_assure) AS VARCHAR(6)), 6, '0'),
       id_assure,
       COUNT(*),
       SUM(montant_rembourse)
FROM remboursement
WHERE lot = DATE :'lot'
GROUP BY id_assure
ORDER BY id_assure;
