#!/usr/bin/env bats
# Job exporter_paiements : contenu du fichier, empreinte, compte rendu, bilan en base, rejouabilité.

load aide

setup() {
    preparer_environnement 20250203
    exiger_base
    nettoyer_lot
    ecrire_lignes_reference
    mkdir -p "$CHAINE_DONNEES/travail"
    cat > "$CHAINE_DONNEES/travail/controle_20250203.stats" <<'EOF'
lues=6
valides=5
rejets=1
motif_montant=1
fichiers=1
taux_rejet=16.67
EOF
    lancer_job charger_base
    [ "$status" -eq 0 ]
    lancer_job calculer_remboursements
    [ "$status" -eq 0 ]
    PAIEMENTS=$CHAINE_DONNEES/sortie/PAI_20250203.csv
}

@test "un paiement par assuré, montants regroupés" {
    lancer_job exporter_paiements
    [ "$status" -eq 0 ]
    [ "$(head -n 1 "$PAIEMENTS")" = "id_paiement;id_assure;nb_feuilles;montant" ]
    [ "$(sed -n 2p "$PAIEMENTS")" = "PAI-20250203-000001;ASSURE-FICTIF-000001;2;49.00" ]
    [ "$(($(wc -l < "$PAIEMENTS") - 1))" -eq 4 ]
}

@test "l'empreinte SHA-256 du fichier est vérifiable" {
    lancer_job exporter_paiements
    cd "$CHAINE_DONNEES/sortie"
    sha256sum -c PAI_20250203.csv.sha256
}

@test "compte rendu et bilan du lot en base" {
    lancer_job exporter_paiements
    [ "$status" -eq 0 ]
    grep -q '^Montant remboursé      : 78.64$' "$CHAINE_DONNEES/sortie/CR_20250203.txt"
    grep -q '^  dont montant : 1$' "$CHAINE_DONNEES/sortie/CR_20250203.txt"
    bilan=$(psql -X -t -A -F ';' -c "SELECT nb_lignes_lues, nb_rejets, nb_feuilles, montant_presente, nb_paiements FROM lot_traitement WHERE lot = DATE '$LOT'")
    [ "$bilan" = "6;1;5;111.46;4" ]
}

@test "rejouer l'export produit le même fichier de paiements" {
    lancer_job exporter_paiements
    premier=$(cksum < "$PAIEMENTS")
    lancer_job exporter_paiements
    [ "$status" -eq 0 ]
    [ "$(cksum < "$PAIEMENTS")" = "$premier" ]
}

@test "sans bilan de contrôle : erreur fonctionnelle" {
    rm "$CHAINE_DONNEES/travail/controle_20250203.stats"
    lancer_job exporter_paiements
    [ "$status" -eq 2 ]
}
