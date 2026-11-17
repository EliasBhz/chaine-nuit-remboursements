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

# Les tests qui touchent PostgreSQL sont sautés si la base est absente,
# sauf avec EXIGER_BASE=1 (CI) où l'absence de base fait échouer le test.
exiger_base() {
    if psql -X -q -c 'SELECT 1' > /dev/null 2>&1; then
        return 0
    fi
    if [ "${EXIGER_BASE:-0}" = 1 ]; then
        echo "base PostgreSQL injoignable" >&2
        return 1
    fi
    skip "base PostgreSQL injoignable"
}

# Efface le lot en base pour que chaque test parte d'un état connu.
nettoyer_lot() {
    psql -X -q -v ON_ERROR_STOP=1 \
        -c "DELETE FROM lot_traitement WHERE lot = DATE '$LOT'" \
        -c "DELETE FROM remboursement WHERE lot = DATE '$LOT'" \
        -c "DELETE FROM feuille_soins WHERE lot = DATE '$LOT'"
}

# Lignes valides de référence, choisies pour vérifier les calculs à la main :
#   000001  CONS 30.00         70 %  -> 21.00
#   000002  INFI 10.00 en ALD  100 % -> 10.00
#   000003  PHAR 15.33         65 %  ->  9.96 (9.9645 arrondi)
#   000004  KINE 16.13         60 %  ->  9.68 (9.678 arrondi)
#   000005  VISI 40.00         70 %  -> 28.00, même assuré que 000001
# Total présenté 111.46, total remboursé 78.64, 4 assurés donc 4 paiements.
ecrire_lignes_reference() {
    mkdir -p "$CHAINE_DONNEES/valides"
    cat > "$CHAINE_DONNEES/valides/FS_${DATE_TRAITEMENT}_01.csv" <<EOF
FS-${DATE_TRAITEMENT}-000001;ASSURE-FICTIF-000001;PS-FICTIF-0001;${LOT};CONS;30.00;N
FS-${DATE_TRAITEMENT}-000002;ASSURE-FICTIF-000002;PS-FICTIF-0002;${LOT};INFI;10.00;O
FS-${DATE_TRAITEMENT}-000003;ASSURE-FICTIF-000003;PS-FICTIF-0003;${LOT};PHAR;15.33;N
FS-${DATE_TRAITEMENT}-000004;ASSURE-FICTIF-000004;PS-FICTIF-0004;${LOT};KINE;16.13;N
FS-${DATE_TRAITEMENT}-000005;ASSURE-FICTIF-000001;PS-FICTIF-0001;${LOT};VISI;40.00;N
EOF
}
