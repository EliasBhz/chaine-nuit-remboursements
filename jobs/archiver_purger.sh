#!/bin/sh
# shellcheck source-path=SCRIPTDIR
# Job 6 : archive les fichiers du lot, puis purge ce qui dépasse la durée de rétention.
# Rien n'est supprimé avant relecture de l'archive. Les fichiers de sortie (paiements, compte rendu)
# restent dans sortie/ pour leur transfert et ne disparaissent qu'avec la rétention.
# Paramètres : RETENTION_JOURS (30) pour archives et sorties, RETENTION_LOGS_JOURS (90) pour les logs.
set -u
JOB_REP=$(dirname "$0")
# shellcheck source=lib/commun.sh
. "$JOB_REP/lib/commun.sh"
initialiser_job archiver_purger

RETENTION_JOURS=${RETENTION_JOURS:-30}
RETENTION_LOGS_JOURS=${RETENTION_LOGS_JOURS:-90}
for parametre in "RETENTION_JOURS=$RETENTION_JOURS" "RETENTION_LOGS_JOURS=$RETENTION_LOGS_JOURS"; do
    case ${parametre#*=} in
        ''|*[!0-9]*) echec "$RC_ERREUR_TECHNIQUE" "Paramètre invalide, entier attendu : $parametre" ;;
    esac
done

D=$DATE_TRAITEMENT
ARCHIVE=archive/lot_$D.tar.gz
code=$RC_OK
cd "$CHAINE_DONNEES" || echec "$RC_ERREUR_TECHNIQUE" "Répertoire $CHAINE_DONNEES inaccessible"

# Chemins relatifs à CHAINE_DONNEES, pour une archive restaurable n'importe où.
set --
nb_recus=0
for fichier in entree/FS_"$D"_*.csv valides/FS_"$D"_*.csv rejets/FS_"$D"_*.rejets \
    travail/controle_"$D".stats travail/charge_"$D".csv \
    sortie/PAI_"$D".csv sortie/PAI_"$D".csv.sha256 sortie/CR_"$D".txt; do
    [ -f "$fichier" ] || continue
    set -- "$@" "$fichier"
    case $fichier in entree/*) nb_recus=$((nb_recus + 1)) ;; esac
done

# Sans fichier reçu, le lot a déjà été archivé (rejeu) ou n'a jamais rien reçu.
if [ "$nb_recus" -eq 0 ]; then
    if [ -f "$ARCHIVE" ]; then
        log_event INFO deja_archive "Lot déjà archivé, rien à faire" archive="$ARCHIVE"
    else
        log_event ALERTE rien_a_archiver "Aucun fichier reçu à archiver pour le lot $LOT"
        code=$RC_ALERTE
    fi
else
    # tar -z n'existe pas partout (AIX notamment) : compression par gzip dans un tube.
    tar -cf - "$@" | gzip -c > "$ARCHIVE.tmp" \
        || echec "$RC_ERREUR_TECHNIQUE" "Échec de l'écriture de l'archive"
    # Sans pipefail en POSIX, un échec de tar passerait inaperçu : l'archive est relue avant toute suppression.
    contenu=$(gzip -dc "$ARCHIVE.tmp" | tar -tf - | wc -l | tr -d ' ')
    [ "$contenu" -eq "$#" ] \
        || echec "$RC_ERREUR_TECHNIQUE" "Archive incomplète : $contenu fichier(s) sur $#"
    mv "$ARCHIVE.tmp" "$ARCHIVE" || echec "$RC_ERREUR_TECHNIQUE" "Impossible de publier $ARCHIVE"

    for fichier in "$@"; do
        case $fichier in
            sortie/*) ;;
            *) rm -f "$fichier" || echec "$RC_ERREUR_TECHNIQUE" "Suppression impossible : $fichier" ;;
        esac
    done
    log_event INFO archive "Lot archivé" archive="$ARCHIVE" fichiers="$#"
fi

# purger REPERTOIRE MOTIF JOURS : supprime les fichiers plus anciens que la rétention.
purger() {
    _nb=$(find "$1" -type f -name "$2" -mtime +"$3" | wc -l | tr -d ' ')
    if [ "$_nb" -gt 0 ]; then
        find "$1" -type f -name "$2" -mtime +"$3" -exec rm -f {} + \
            || echec "$RC_ERREUR_TECHNIQUE" "Échec de la purge de $1"
    fi
    log_event INFO purge "Purge de $1 ($2)" motif="$2" retention_jours="$3" supprimes="$_nb"
}

purger archive 'lot_*.tar.gz' "$RETENTION_JOURS"
purger sortie 'PAI_*' "$RETENTION_JOURS"
purger sortie 'CR_*' "$RETENTION_JOURS"
purger "$CHAINE_LOGS" 'chaine-*.jsonl' "$RETENTION_LOGS_JOURS"
purger "$CHAINE_LOGS" '*.out' "$RETENTION_LOGS_JOURS"

terminer_job "$code"
