#!/bin/sh
# shellcheck source-path=SCRIPTDIR
# Job 3 : charge les lignes valides du lot dans PostgreSQL.
# COPY dans une table tampon, puis remplacement du lot en une transaction (sql/charger_lot.sql) :
# rejouer le job donne toujours le même contenu, sans doublon ni lot chargé à moitié.
set -u
JOB_REP=$(dirname "$0")
# shellcheck source=lib/commun.sh
. "$JOB_REP/lib/commun.sh"
initialiser_job charger_base
verifier_base

set --
for fichier in "$DIR_VALIDES"/FS_"$DATE_TRAITEMENT"_*.csv; do
    [ -f "$fichier" ] && set -- "$@" "$fichier"
done
[ "$#" -gt 0 ] \
    || echec "$RC_ERREUR_FONCTIONNELLE" "Aucun fichier contrôlé pour le lot $LOT"

A_CHARGER=$DIR_TRAVAIL/charge_$DATE_TRAITEMENT.csv
cat "$@" > "$A_CHARGER" || echec "$RC_ERREUR_TECHNIQUE" "Impossible de préparer $A_CHARGER"
attendues=$(wc -l < "$A_CHARGER" | tr -d ' ')
[ "$attendues" -gt 0 ] || echec "$RC_ERREUR_FONCTIONNELLE" "Aucune ligne valide à charger"

sql -c 'TRUNCATE TABLE feuille_soins_import' \
    || echec "$RC_ERREUR_TECHNIQUE" "Échec du vidage de la table d'import"
sql -c "COPY feuille_soins_import (id_feuille, id_assure, id_professionnel, date_soins, code_acte, montant, ald) FROM STDIN WITH (FORMAT csv, DELIMITER ';')" \
    < "$A_CHARGER" || echec "$RC_ERREUR_TECHNIQUE" "Échec du COPY vers la table d'import"
sql -f "$CHAINE_RACINE/sql/charger_lot.sql" \
    || echec "$RC_ERREUR_TECHNIQUE" "Échec du remplacement du lot"

chargees=$(sql_valeur "SELECT COUNT(*) FROM feuille_soins WHERE lot = DATE '$LOT'") \
    || echec "$RC_ERREUR_TECHNIQUE" "Impossible de compter les lignes chargées"
[ "$chargees" -eq "$attendues" ] \
    || echec "$RC_ERREUR_FONCTIONNELLE" "Écart de chargement : $chargees lignes en base pour $attendues attendues"

log_event INFO bilan "Lot chargé" lignes="$chargees"
terminer_job "$RC_OK"
