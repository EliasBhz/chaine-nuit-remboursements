#!/bin/sh
# shellcheck source-path=SCRIPTDIR
# Job 1 : génère les feuilles de soins fictives du lot (simule la réception des fichiers).
# Paramètres : NB_FICHIERS (3), NB_LIGNES par fichier (1000), TAUX_INVALIDES en % (2),
# GRAINE (date de traitement par défaut). Même graine, mêmes fichiers : le job est rejouable.
set -u
JOB_REP=$(dirname "$0")
# shellcheck source=lib/commun.sh
. "$JOB_REP/lib/commun.sh"
initialiser_job generer_fichiers

NB_FICHIERS=${NB_FICHIERS:-3}
NB_LIGNES=${NB_LIGNES:-1000}
TAUX_INVALIDES=${TAUX_INVALIDES:-2}
GRAINE=${GRAINE:-$DATE_TRAITEMENT}

for parametre in "NB_FICHIERS=$NB_FICHIERS" "NB_LIGNES=$NB_LIGNES" \
    "TAUX_INVALIDES=$TAUX_INVALIDES" "GRAINE=$GRAINE"; do
    case ${parametre#*=} in
        ''|*[!0-9]*|0[0-9]*) echec "$RC_ERREUR_TECHNIQUE" "Paramètre invalide, entier attendu : $parametre" ;;
    esac
done
[ "$TAUX_INVALIDES" -le 100 ] \
    || echec "$RC_ERREUR_TECHNIQUE" "TAUX_INVALIDES doit être compris entre 0 et 100"
# Le numéro de feuille tient sur 6 chiffres.
[ $((NB_FICHIERS * NB_LIGNES)) -le 999999 ] \
    || echec "$RC_ERREUR_TECHNIQUE" "Volume demandé trop grand : 999999 lignes au plus par lot"

numero=1
while [ "$numero" -le "$NB_FICHIERS" ]; do
    nom=$(printf 'FS_%s_%02d.csv' "$DATE_TRAITEMENT" "$numero")
    temporaire=$DIR_ENTREE/.$nom.tmp
    awk -v graine="$GRAINE" -v fichier="$numero" -v nb_lignes="$NB_LIGNES" \
        -v taux_invalides="$TAUX_INVALIDES" -v date_lot="$LOT" \
        -f "$JOB_REP/lib/dates.awk" -f "$JOB_REP/lib/generer.awk" > "$temporaire" \
        || echec "$RC_ERREUR_TECHNIQUE" "Échec de la génération de $nom"
    # Renommage atomique : un fichier visible dans entree/ est toujours complet.
    mv "$temporaire" "$DIR_ENTREE/$nom" \
        || echec "$RC_ERREUR_TECHNIQUE" "Impossible de déposer $nom"
    log_event INFO fichier_genere "Fichier $nom généré" fichier="$nom" lignes="$NB_LIGNES"
    numero=$((numero + 1))
done

log_event INFO bilan "Génération terminée" fichiers="$NB_FICHIERS" lignes=$((NB_FICHIERS * NB_LIGNES))
terminer_job "$RC_OK"
