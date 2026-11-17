# shellcheck shell=sh
# Les variables définies ici sont lues par les jobs qui sourcent ce fichier :
# analysé seul, ShellCheck les signalerait à tort comme inutilisées.
# shellcheck disable=SC2034
# Bibliothèque commune aux jobs : codes retour, répertoires, logs JSON, accès à la base.
# Le job positionne JOB_REP (répertoire du script), source ce fichier puis appelle initialiser_job.
# Shell POSIX strict (ni local, ni tableaux, ni pipefail) pour tourner à l'identique sous ksh et bash.

RC_OK=0
RC_ALERTE=1
RC_ERREUR_FONCTIONNELLE=2
RC_ERREUR_TECHNIQUE=3

# Secondes depuis l'epoch sans date +%s, absent de POSIX et d'AIX :
# srand() sans argument prend l'heure courante comme graine, le second appel la renvoie.
epoch() {
    awk 'BEGIN { srand(); print srand() }'
}

# Échappe une chaîne pour une valeur JSON (sauts de ligne et tabulations ramenés à des espaces).
json_texte() {
    printf '%s' "$1" | tr '\n\r\t' '   ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# log_event NIVEAU EVENEMENT MESSAGE [cle=valeur ...]
# Une ligne JSON par événement, sur la sortie standard et dans le journal du lot.
# Les valeurs numériques restent des nombres pour être agrégées par Elasticsearch ou Grafana.
log_event() {
    _niveau=$1 _evenement=$2 _message=$(json_texte "$3")
    shift 3
    _ligne=$(printf '{"horodatage":"%s","niveau":"%s","chaine":"%s","execution":"%s","job":"%s","lot":"%s","evenement":"%s","message":"%s"' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$_niveau" "$CHAINE_NOM" "$CHAINE_EXECUTION" \
        "$JOB_NOM" "$LOT" "$_evenement" "$_message")
    for _paire in "$@"; do
        _cle=${_paire%%=*}
        _valeur=${_paire#*=}
        case $_valeur in
            ''|*[!0-9.]*|*.*.*|.*|*.|0[0-9]*)
                _ligne="$_ligne,\"$_cle\":\"$(json_texte "$_valeur")\"" ;;
            *)
                _ligne="$_ligne,\"$_cle\":$_valeur" ;;
        esac
    done
    printf '%s}\n' "$_ligne"
    printf '%s}\n' "$_ligne" >> "$CHAINE_LOGS/chaine-$DATE_TRAITEMENT.jsonl"
}

# initialiser_job NOM : contrôle l'environnement, crée les répertoires d'échange, trace le début.
initialiser_job() {
    JOB_NOM=$1
    : "${CHAINE_NOM:=nuit_remboursements}"
    : "${CHAINE_EXECUTION:=manuelle}"
    : "${CHAINE_DONNEES:=/data}"
    : "${CHAINE_LOGS:=$CHAINE_DONNEES/logs}"
    : "${DATE_TRAITEMENT:=$(date +%Y%m%d)}"
    export PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-5}"

    case $DATE_TRAITEMENT in
        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;;
        *)
            printf '%s : DATE_TRAITEMENT invalide (%s), format attendu AAAAMMJJ\n' \
                "$JOB_NOM" "$DATE_TRAITEMENT" >&2
            exit "$RC_ERREUR_TECHNIQUE"
            ;;
    esac
    LOT=$(printf '%s' "$DATE_TRAITEMENT" | sed 's/^\(....\)\(..\)\(..\)$/\1-\2-\3/')

    CHAINE_RACINE=$(cd "$JOB_REP/.." && pwd)
    DIR_ENTREE=$CHAINE_DONNEES/entree
    DIR_VALIDES=$CHAINE_DONNEES/valides
    DIR_REJETS=$CHAINE_DONNEES/rejets
    DIR_SORTIE=$CHAINE_DONNEES/sortie
    DIR_ARCHIVE=$CHAINE_DONNEES/archive
    DIR_TRAVAIL=$CHAINE_DONNEES/travail

    if ! mkdir -p "$DIR_ENTREE" "$DIR_VALIDES" "$DIR_REJETS" "$DIR_SORTIE" \
        "$DIR_ARCHIVE" "$DIR_TRAVAIL" "$CHAINE_LOGS"; then
        printf '%s : impossible de créer les répertoires sous %s\n' "$JOB_NOM" "$CHAINE_DONNEES" >&2
        exit "$RC_ERREUR_TECHNIQUE"
    fi

    JOB_DEBUT=$(epoch)
    # Arrêt demandé par l'ordonnanceur (dépassement de durée) ou par un opérateur.
    trap 'echec "$RC_ERREUR_TECHNIQUE" "Job interrompu par un signal"' INT TERM
    log_event INFO debut "Début du job"
}

# terminer_job CODE : trace la fin du job avec sa durée et sort avec le code retour.
terminer_job() {
    trap - INT TERM
    _rc=$1
    case $_rc in
        0) _niveau=INFO ;;
        1) _niveau=ALERTE ;;
        *) _niveau=ERREUR ;;
    esac
    log_event "$_niveau" fin "Fin du job" code_retour="$_rc" duree_s=$(($(epoch) - JOB_DEBUT))
    exit "$_rc"
}

# echec CODE MESSAGE : trace l'erreur puis termine le job avec ce code.
echec() {
    log_event ERREUR erreur "$2"
    terminer_job "$1"
}

# Client PostgreSQL en mode script : pas de .psqlrc, arrêt à la première erreur.
sql() {
    psql -X -q -v ON_ERROR_STOP=1 -v lot="$LOT" -v date_traitement="$DATE_TRAITEMENT" "$@"
}

# sql_valeur REQUETE : renvoie le résultat brut, sans entête ni alignement.
sql_valeur() {
    sql -t -A -c "$1"
}

verifier_base() {
    sql_valeur 'SELECT 1' > /dev/null 2>&1 \
        || echec "$RC_ERREUR_TECHNIQUE" "Base de données injoignable (${PGHOST:-socket locale})"
}

# lire_stat FICHIER CLE : lit une valeur dans un fichier cle=valeur produit par un job précédent.
lire_stat() {
    sed -n "s/^$2=//p" "$1"
}
