#!/usr/bin/env bats
# Chaîne complète lancée par l'ordonnanceur, avec la base : jeu de référence, rejeu, reprise après panne.

load aide

setup() {
    export CHAINE_SHELL=$SHELL_TEST
    # Pas d'attente entre deux essais pendant les tests.
    sed 's/delai_relance: [0-9]*/delai_relance: 0/' "$RACINE/ordonnanceur/chaine.yaml" \
        > "$BATS_TEST_TMPDIR/chaine.yaml"
}

chaine() {
    run python3 "$RACINE/ordonnanceur/ordonnanceur.py" \
        --definition "$BATS_TEST_TMPDIR/chaine.yaml" --forcer-fenetre "$@"
}

bilan() {
    psql -X -t -A -c "SELECT $1 FROM lot_traitement WHERE lot = DATE '$LOT'"
}

@test "jeu de données de référence : montants attendus au centime" {
    preparer_environnement 20250401
    exiger_base
    nettoyer_lot
    mkdir -p "$CHAINE_DONNEES/entree"
    cp "$RACINE/tests/donnees/FS_20250401_01.csv" "$CHAINE_DONNEES/entree/"
    export NB_FICHIERS=0 SEUIL_REJET=60

    chaine
    [ "$status" -eq 1 ]
    [ "$(bilan nb_feuilles)" -eq 5 ]
    [ "$(bilan nb_rejets)" -eq 5 ]
    [ "$(bilan montant_presente)" = "111.46" ]
    [ "$(bilan montant_rembourse)" = "78.64" ]
    [ "$(bilan nb_paiements)" -eq 4 ]
    grep -q '^PAI-20250401-000001;ASSURE-FICTIF-000001;2;49.00$' "$CHAINE_DONNEES/sortie/PAI_20250401.csv"
    grep -q '^Lignes rejetées        : 5 (50.00 %)$' "$CHAINE_DONNEES/sortie/CR_20250401.txt"
    [ -f "$CHAINE_DONNEES/archive/lot_20250401.tar.gz" ]
    [ ! -f "$CHAINE_DONNEES/entree/FS_20250401_01.csv" ]
}

@test "chaîne générée de bout en bout, rejouable à l'identique" {
    preparer_environnement 20250402
    exiger_base
    nettoyer_lot
    export NB_FICHIERS=2 NB_LIGNES=300 TAUX_INVALIDES=2 GRAINE=7

    chaine
    [ "$status" -le 1 ]
    empreinte=$(cut -d ' ' -f 1 "$CHAINE_DONNEES/sortie/PAI_20250402.csv.sha256")
    [ "$(bilan nb_lignes_lues)" -eq 600 ]

    chaine
    [ "$status" -eq 0 ]
    [[ "$output" == *deja_terminee* ]]

    chaine --depuis-debut
    [ "$status" -le 1 ]
    [ "$(cut -d ' ' -f 1 "$CHAINE_DONNEES/sortie/PAI_20250402.csv.sha256")" = "$empreinte" ]
    [ "$(psql -X -t -A -c "SELECT COUNT(*) FROM feuille_soins WHERE lot = DATE '$LOT'")" -eq "$(bilan nb_feuilles)" ]
}

@test "reprise après une panne de base au chargement" {
    preparer_environnement 20250403
    exiger_base
    nettoyer_lot
    export NB_FICHIERS=1 NB_LIGNES=100 TAUX_INVALIDES=0
    hote=$PGHOST
    journal=$CHAINE_LOGS/chaine-20250403.jsonl

    export PGHOST=hote-inexistant.invalid
    chaine
    [ "$status" -eq 3 ]
    [ "$(grep -c '"evenement":"relance","message":"Relance de charger_base' "$journal")" -eq 2 ]
    statut=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["jobs"]["charger_base"]["statut"])' \
        "$CHAINE_ETAT/etat-20250403.json")
    [ "$statut" = "ECHEC" ]

    export PGHOST=$hote
    chaine --reprise
    [ "$status" -eq 0 ]
    # Les jobs terminés avant la panne n'ont tourné qu'une fois.
    [ "$(grep -c '"job":"generer_fichiers","lot":"2025-04-03","evenement":"debut"' "$journal")" -eq 1 ]
    [ "$(grep -c '"job":"controler_format","lot":"2025-04-03","evenement":"debut"' "$journal")" -eq 1 ]
    [ "$(bilan nb_feuilles)" -eq 100 ]
}
