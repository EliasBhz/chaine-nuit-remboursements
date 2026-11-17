#!/bin/sh
# shellcheck source-path=SCRIPTDIR
# Job 2 : contrôle le format des fichiers reçus pour le lot.
# Lignes valides vers valides/, rejets vers rejets/ avec leur motif, bilan dans travail/.
# Code retour : 0 sans rejet, 1 si les rejets restent sous SEUIL_REJET (% des lignes, 5 par défaut),
# 2 au-delà du seuil ou si un fichier est inexploitable.
set -u
JOB_REP=$(dirname "$0")
# shellcheck source=lib/commun.sh
. "$JOB_REP/lib/commun.sh"
initialiser_job controler_format

SEUIL_REJET=${SEUIL_REJET:-5}
ENTETE='id_feuille;id_assure;id_professionnel;date_soins;code_acte;montant;ald'
ACTES_CONNUS='CONS VISI INFI KINE PHAR'
STATS=$DIR_TRAVAIL/controle_$DATE_TRAITEMENT.stats

nb_fichiers=0
for fichier in "$DIR_ENTREE"/FS_"$DATE_TRAITEMENT"_*.csv; do
    [ -f "$fichier" ] || continue
    nb_fichiers=$((nb_fichiers + 1))
    # Un entête inattendu signale un fichier d'un autre format ou tronqué : rien n'est traité.
    entete=$(head -n 1 "$fichier" | tr -d '\r')
    [ "$entete" = "$ENTETE" ] \
        || echec "$RC_ERREUR_FONCTIONNELLE" "Entête invalide dans $(basename "$fichier")"
done
[ "$nb_fichiers" -gt 0 ] \
    || echec "$RC_ERREUR_FONCTIONNELLE" "Aucun fichier reçu pour le lot $LOT"

# Les sorties d'un passage précédent sur le même lot sont remplacées.
rm -f "$DIR_VALIDES"/FS_"$DATE_TRAITEMENT"_*.csv "$DIR_REJETS"/FS_"$DATE_TRAITEMENT"_*.rejets

awk -F ';' -v date_lot="$LOT" -v actes="$ACTES_CONNUS" \
    -v rep_valides="$DIR_VALIDES" -v rep_rejets="$DIR_REJETS" \
    -f "$JOB_REP/lib/dates.awk" -f "$JOB_REP/lib/controler.awk" \
    "$DIR_ENTREE"/FS_"$DATE_TRAITEMENT"_*.csv > "$STATS.tmp" \
    || echec "$RC_ERREUR_TECHNIQUE" "Échec du contrôle de format"

lues=$(lire_stat "$STATS.tmp" lues)
valides=$(lire_stat "$STATS.tmp" valides)
rejets=$(lire_stat "$STATS.tmp" rejets)
[ "$lues" -gt 0 ] || echec "$RC_ERREUR_FONCTIONNELLE" "Les fichiers du lot ne contiennent aucune ligne"
taux_rejet=$(awk -v r="$rejets" -v l="$lues" 'BEGIN { printf "%.2f", r * 100 / l }')
printf 'fichiers=%s\ntaux_rejet=%s\n' "$nb_fichiers" "$taux_rejet" >> "$STATS.tmp"
mv "$STATS.tmp" "$STATS" || echec "$RC_ERREUR_TECHNIQUE" "Impossible d'écrire $STATS"

sed -n 's/^motif_//p' "$STATS" | while IFS='=' read -r motif nombre; do
    log_event ALERTE rejets "$nombre ligne(s) rejetée(s) pour le motif $motif" motif="$motif" nombre="$nombre"
done
log_event INFO bilan "Contrôle terminé" fichiers="$nb_fichiers" lues="$lues" \
    valides="$valides" rejets="$rejets" taux_rejet="$taux_rejet"

[ "$rejets" -eq 0 ] && terminer_job "$RC_OK"
if awk -v t="$taux_rejet" -v s="$SEUIL_REJET" 'BEGIN { exit !(t > s) }'; then
    echec "$RC_ERREUR_FONCTIONNELLE" "Taux de rejet de $taux_rejet % supérieur au seuil de $SEUIL_REJET %"
fi
terminer_job "$RC_ALERTE"
