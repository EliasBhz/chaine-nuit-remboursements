# Fonctions communes aux tests bats.
# SHELL_TEST choisit l'interpréteur des jobs (ksh ou bash) ; tests/lancer_tests.sh enchaîne les deux.

RACINE=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
export RACINE
SHELL_TEST=${SHELL_TEST:-sh}

ENTETE='id_feuille;id_assure;id_professionnel;date_soins;code_acte;montant;ald'

# preparer_environnement [AAAAMMJJ] : répertoires de données propres au test et date de traitement.
preparer_environnement() {
    export CHAINE_DONNEES="$BATS_TEST_TMPDIR/donnees"
    export CHAINE_LOGS="$CHAINE_DONNEES/logs"
    export CHAINE_ETAT="$CHAINE_DONNEES/etat"
    export DATE_TRAITEMENT="${1:-20250115}"
    LOT=$(echo "$DATE_TRAITEMENT" | sed 's/^\(....\)\(..\)\(..\)$/\1-\2-\3/')
    mkdir -p "$CHAINE_DONNEES"
}

lancer_job() {
    run "$SHELL_TEST" "$RACINE/jobs/$1.sh"
}
