#!/bin/sh
# shellcheck source-path=SCRIPTDIR
# Job 4 : calcule les remboursements du lot (sql/calcul_remboursements.sql).
# Vérifie ensuite que chaque feuille chargée a bien son remboursement.
set -u
JOB_REP=$(dirname "$0")
# shellcheck source=lib/commun.sh
. "$JOB_REP/lib/commun.sh"
initialiser_job calculer_remboursements
verifier_base

feuilles=$(sql_valeur "SELECT COUNT(*) FROM feuille_soins WHERE lot = DATE '$LOT'") \
    || echec "$RC_ERREUR_TECHNIQUE" "Impossible de compter les feuilles du lot"
[ "$feuilles" -gt 0 ] || echec "$RC_ERREUR_FONCTIONNELLE" "Aucune feuille chargée pour le lot $LOT"

sql -f "$CHAINE_RACINE/sql/calcul_remboursements.sql" \
    || echec "$RC_ERREUR_TECHNIQUE" "Échec du calcul des remboursements"

calcules=$(sql_valeur "SELECT COUNT(*) FROM remboursement WHERE lot = DATE '$LOT'") \
    || echec "$RC_ERREUR_TECHNIQUE" "Impossible de compter les remboursements du lot"
[ "$calcules" -eq "$feuilles" ] \
    || echec "$RC_ERREUR_FONCTIONNELLE" "$((feuilles - calcules)) feuille(s) sans remboursement calculé"

montant=$(sql_valeur "SELECT SUM(montant_rembourse) FROM remboursement WHERE lot = DATE '$LOT'")
log_event INFO bilan "Remboursements calculés" feuilles="$feuilles" montant_rembourse="$montant"
terminer_job "$RC_OK"
