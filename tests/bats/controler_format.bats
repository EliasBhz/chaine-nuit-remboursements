#!/usr/bin/env bats
# Job controler_format : motifs de rejet, seuil, fichiers inexploitables, rejouabilité.

load aide

setup() {
    preparer_environnement
    ENTREE=$CHAINE_DONNEES/entree
    mkdir -p "$ENTREE"
}

# ecrire_fichier NN : dépose un fichier du lot avec l'entête puis les lignes lues sur l'entrée standard.
ecrire_fichier() {
    { printf '%s\n' "$ENTETE"; cat; } > "$ENTREE/FS_${DATE_TRAITEMENT}_$1.csv"
}

ligne_valide() {
    printf 'FS-20250115-%06d;ASSURE-FICTIF-000001;PS-FICTIF-0001;2025-01-10;CONS;30.00;N\n' "$1"
}

@test "fichier conforme : code 0, toutes les lignes valides, aucun rejet" {
    { ligne_valide 1; ligne_valide 2; } | ecrire_fichier 01
    lancer_job controler_format
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$CHAINE_DONNEES/valides/FS_20250115_01.csv")" -eq 2 ]
    [ ! -s "$CHAINE_DONNEES/rejets/FS_20250115_01.csv.rejets" ]
}

@test "chaque anomalie est rejetée avec son motif" {
    export SEUIL_REJET=100
    ecrire_fichier 01 <<'EOF'
FS-20250115-000001;ASSURE-FICTIF-000001;PS-FICTIF-0001;2025-01-10;CONS;30.00;N
FS-20250115-000002;ASSURE-FICTIF-000001;PS-FICTIF-0001;2025-01-10;CONS;30.00
FS-2025-000003;ASSURE-FICTIF-000001;PS-FICTIF-0001;2025-01-10;CONS;30.00;N
FS-20250115-000001;ASSURE-FICTIF-000002;PS-FICTIF-0001;2025-01-10;CONS;30.00;N
FS-20250115-000005;ASSURE-123;PS-FICTIF-0001;2025-01-10;CONS;30.00;N
FS-20250115-000006;ASSURE-FICTIF-000001;PS-1;2025-01-10;CONS;30.00;N
FS-20250115-000007;ASSURE-FICTIF-000001;PS-FICTIF-0001;2025-02-30;CONS;30.00;N
FS-20250115-000008;ASSURE-FICTIF-000001;PS-FICTIF-0001;2025-01-20;CONS;30.00;N
FS-20250115-000009;ASSURE-FICTIF-000001;PS-FICTIF-0001;2025-01-10;XXXX;30.00;N
FS-20250115-000010;ASSURE-FICTIF-000001;PS-FICTIF-0001;2025-01-10;CONS;30,00;N
FS-20250115-000011;ASSURE-FICTIF-000001;PS-FICTIF-0001;2025-01-10;CONS;30.00;X
EOF
    lancer_job controler_format
    [ "$status" -eq 1 ]
    rejets=$CHAINE_DONNEES/rejets/FS_20250115_01.csv.rejets
    [ "$(wc -l < "$CHAINE_DONNEES/valides/FS_20250115_01.csv")" -eq 1 ]
    [ "$(wc -l < "$rejets")" -eq 10 ]
    for motif in nombre_champs id_feuille doublon id_assure id_professionnel \
        date_soins date_future code_acte montant ald; do
        [ "$(grep -c "^[0-9]*;$motif;" "$rejets")" -eq 1 ]
    done
}

@test "taux de rejet au-delà du seuil : erreur fonctionnelle" {
    export SEUIL_REJET=10
    { ligne_valide 1; echo "ligne illisible"; } | ecrire_fichier 01
    lancer_job controler_format
    [ "$status" -eq 2 ]
    grep -q '^taux_rejet=50.00$' "$CHAINE_DONNEES/travail/controle_20250115.stats"
}

@test "entête invalide : erreur fonctionnelle, aucune ligne traitée" {
    { echo "autre;format"; ligne_valide 1; } > "$ENTREE/FS_20250115_01.csv"
    lancer_job controler_format
    [ "$status" -eq 2 ]
    [ ! -f "$CHAINE_DONNEES/valides/FS_20250115_01.csv" ]
}

@test "aucun fichier reçu : erreur fonctionnelle" {
    lancer_job controler_format
    [ "$status" -eq 2 ]
}

@test "un doublon entre deux fichiers du lot est rejeté" {
    export SEUIL_REJET=100
    ligne_valide 1 | ecrire_fichier 01
    ligne_valide 1 | ecrire_fichier 02
    lancer_job controler_format
    [ "$status" -eq 1 ]
    grep -q '^2;doublon;' "$CHAINE_DONNEES/rejets/FS_20250115_02.csv.rejets"
}

@test "deux passages sur le même lot donnent le même résultat" {
    export SEUIL_REJET=100
    { ligne_valide 1; ligne_valide 2; echo "ligne illisible"; } | ecrire_fichier 01
    lancer_job controler_format
    avant=$(cat "$CHAINE_DONNEES/valides/FS_20250115_01.csv" "$CHAINE_DONNEES/rejets/FS_20250115_01.csv.rejets" | cksum)
    lancer_job controler_format
    [ "$status" -eq 1 ]
    apres=$(cat "$CHAINE_DONNEES/valides/FS_20250115_01.csv" "$CHAINE_DONNEES/rejets/FS_20250115_01.csv.rejets" | cksum)
    [ "$avant" = "$apres" ]
}

@test "les fins de ligne Windows sont tolérées" {
    printf '%s\r\n%s\r\n' "$ENTETE" "$(ligne_valide 1)" > "$ENTREE/FS_20250115_01.csv"
    lancer_job controler_format
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$CHAINE_DONNEES/valides/FS_20250115_01.csv")" -eq 1 ]
}
