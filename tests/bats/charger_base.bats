#!/usr/bin/env bats
# Job charger_base : chargement, rejeu sans doublon, remplacement du lot, pannes.

load aide

setup() {
    preparer_environnement 20250201
    exiger_base
    nettoyer_lot
    ecrire_lignes_reference
}

compter_lot() {
    psql -X -t -A -c "SELECT COUNT(*) FROM feuille_soins WHERE lot = DATE '$LOT'"
}

@test "charge les lignes valides du lot" {
    lancer_job charger_base
    [ "$status" -eq 0 ]
    [ "$(compter_lot)" -eq 5 ]
}

@test "rejouer le chargement ne crée pas de doublon" {
    lancer_job charger_base
    lancer_job charger_base
    [ "$status" -eq 0 ]
    [ "$(compter_lot)" -eq 5 ]
}

@test "un nouveau chargement remplace le contenu du lot" {
    lancer_job charger_base
    head -n 2 "$CHAINE_DONNEES/valides/FS_20250201_01.csv" > "$BATS_TEST_TMPDIR/deux_lignes"
    mv "$BATS_TEST_TMPDIR/deux_lignes" "$CHAINE_DONNEES/valides/FS_20250201_01.csv"
    lancer_job charger_base
    [ "$status" -eq 0 ]
    [ "$(compter_lot)" -eq 2 ]
}

@test "base injoignable : erreur technique" {
    export PGHOST=hote-inexistant.invalid
    lancer_job charger_base
    [ "$status" -eq 3 ]
    [[ "$output" == *"injoignable"* ]]
}

@test "aucun fichier contrôlé pour le lot : erreur fonctionnelle" {
    rm "$CHAINE_DONNEES/valides/FS_20250201_01.csv"
    lancer_job charger_base
    [ "$status" -eq 2 ]
}
