#!/usr/bin/env bats
# Job generer_fichiers : volumes, format, reproductibilité, contrôle des paramètres.

load aide

setup() {
    preparer_environnement
    ENTREE=$CHAINE_DONNEES/entree
}

@test "produit le nombre de fichiers et de lignes demandés" {
    export NB_FICHIERS=2 NB_LIGNES=50
    lancer_job generer_fichiers
    [ "$status" -eq 0 ]
    [ -f "$ENTREE/FS_20250115_01.csv" ]
    [ -f "$ENTREE/FS_20250115_02.csv" ]
    [ "$(wc -l < "$ENTREE/FS_20250115_01.csv")" -eq 51 ]
    [ "$(head -n 1 "$ENTREE/FS_20250115_02.csv")" = "$ENTETE" ]
}

@test "une même graine produit des fichiers identiques" {
    export NB_FICHIERS=1 NB_LIGNES=100 GRAINE=42
    lancer_job generer_fichiers
    premier=$(cksum < "$ENTREE/FS_20250115_01.csv")
    lancer_job generer_fichiers
    [ "$status" -eq 0 ]
    [ "$(cksum < "$ENTREE/FS_20250115_01.csv")" = "$premier" ]
}

@test "sans taux d'invalides, toutes les lignes respectent le format" {
    export NB_FICHIERS=1 NB_LIGNES=200 TAUX_INVALIDES=0
    lancer_job generer_fichiers
    [ "$status" -eq 0 ]
    conformes=$(grep -cE '^FS-20250115-[0-9]{6};ASSURE-FICTIF-[0-9]{6};PS-FICTIF-[0-9]{4};20(24|25)-[0-9]{2}-[0-9]{2};(CONS|VISI|INFI|KINE|PHAR);[0-9]+\.[0-9]{2};[ON]$' \
        "$ENTREE/FS_20250115_01.csv")
    [ "$conformes" -eq 200 ]
}

@test "aucun fichier temporaire ne reste dans entree" {
    export NB_FICHIERS=2 NB_LIGNES=10
    lancer_job generer_fichiers
    [ "$(find "$ENTREE" -name '*.tmp' | wc -l)" -eq 0 ]
}

@test "un paramètre non entier est refusé en erreur technique" {
    export NB_LIGNES=abc
    lancer_job generer_fichiers
    [ "$status" -eq 3 ]
}

@test "un taux d'invalides supérieur à 100 est refusé" {
    export TAUX_INVALIDES=150
    lancer_job generer_fichiers
    [ "$status" -eq 3 ]
}
