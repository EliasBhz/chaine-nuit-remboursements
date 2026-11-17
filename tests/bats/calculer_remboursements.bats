#!/usr/bin/env bats
# Job calculer_remboursements : taux, ALD, arrondis, rejouabilité (montants détaillés dans aide.bash).

load aide

setup() {
    preparer_environnement 20250202
    exiger_base
    nettoyer_lot
    ecrire_lignes_reference
    lancer_job charger_base
    [ "$status" -eq 0 ]
}

montant() {
    psql -X -t -A -c "SELECT montant_rembourse FROM remboursement WHERE id_feuille = 'FS-$DATE_TRAITEMENT-$1'"
}

total_lot() {
    psql -X -t -A -c "SELECT SUM(montant_rembourse) FROM remboursement WHERE lot = DATE '$LOT'"
}

@test "applique le taux de l'acte, 100 % en ALD, arrondi au centime" {
    lancer_job calculer_remboursements
    [ "$status" -eq 0 ]
    [ "$(montant 000001)" = "21.00" ]
    [ "$(montant 000002)" = "10.00" ]
    [ "$(montant 000003)" = "9.96" ]
    [ "$(montant 000004)" = "9.68" ]
    [ "$(montant 000005)" = "28.00" ]
    [ "$(total_lot)" = "78.64" ]
}

@test "rejouer le calcul donne le même résultat" {
    lancer_job calculer_remboursements
    lancer_job calculer_remboursements
    [ "$status" -eq 0 ]
    [ "$(psql -X -t -A -c "SELECT COUNT(*) FROM remboursement WHERE lot = DATE '$LOT'")" -eq 5 ]
    [ "$(total_lot)" = "78.64" ]
}

@test "lot sans feuille chargée : erreur fonctionnelle" {
    nettoyer_lot
    lancer_job calculer_remboursements
    [ "$status" -eq 2 ]
}
