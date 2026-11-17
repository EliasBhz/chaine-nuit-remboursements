#!/bin/sh
# shellcheck source-path=SCRIPTDIR
# Job 5 : produit le fichier de paiements du lot, son empreinte SHA-256 et le compte rendu de traitement.
# Le fichier n'est publié dans sortie/ qu'après contrôle de son total par rapport à la base.
set -u
JOB_REP=$(dirname "$0")
# shellcheck source=lib/commun.sh
. "$JOB_REP/lib/commun.sh"
initialiser_job exporter_paiements
verifier_base

STATS=$DIR_TRAVAIL/controle_$DATE_TRAITEMENT.stats
PAIEMENTS=PAI_$DATE_TRAITEMENT.csv
COMPTE_RENDU=CR_$DATE_TRAITEMENT.txt

[ -f "$STATS" ] || echec "$RC_ERREUR_FONCTIONNELLE" "Bilan du contrôle introuvable pour le lot $LOT"
calcules=$(sql_valeur "SELECT COUNT(*) FROM remboursement WHERE lot = DATE '$LOT'") \
    || echec "$RC_ERREUR_TECHNIQUE" "Impossible de compter les remboursements du lot"
[ "$calcules" -gt 0 ] || echec "$RC_ERREUR_FONCTIONNELLE" "Aucun remboursement calculé pour le lot $LOT"

{
    printf 'id_paiement;id_assure;nb_feuilles;montant\n'
    sql -t -A -F ';' -f "$CHAINE_RACINE/sql/export_paiements.sql"
} > "$DIR_SORTIE/$PAIEMENTS.tmp" || echec "$RC_ERREUR_TECHNIQUE" "Échec de l'extraction des paiements"

# Contrôle de cohérence en centimes, pour comparer des entiers et non des flottants.
total_fichier=$(awk -F ';' 'NR > 1 { s += sprintf("%.0f", $4 * 100) } END { printf "%.0f", s }' \
    "$DIR_SORTIE/$PAIEMENTS.tmp")
total_base=$(sql_valeur "SELECT CAST(SUM(montant_rembourse) * 100 AS NUMERIC(14,0)) FROM remboursement WHERE lot = DATE '$LOT'") \
    || echec "$RC_ERREUR_TECHNIQUE" "Impossible de totaliser les remboursements du lot"
[ "$total_fichier" = "$total_base" ] \
    || echec "$RC_ERREUR_FONCTIONNELLE" "Total du fichier ($total_fichier centimes) différent de la base ($total_base centimes)"

mv "$DIR_SORTIE/$PAIEMENTS.tmp" "$DIR_SORTIE/$PAIEMENTS" \
    || echec "$RC_ERREUR_TECHNIQUE" "Impossible de publier $PAIEMENTS"
(cd "$DIR_SORTIE" && sha256sum "$PAIEMENTS" > "$PAIEMENTS.sha256") \
    || echec "$RC_ERREUR_TECHNIQUE" "Impossible de calculer l'empreinte de $PAIEMENTS"
nb_paiements=$(($(wc -l < "$DIR_SORTIE/$PAIEMENTS") - 1))

lues=$(lire_stat "$STATS" lues)
rejets=$(lire_stat "$STATS" rejets)
sql -v lues="$lues" -v rejets="$rejets" -f "$CHAINE_RACINE/sql/bilan_lot.sql" \
    || echec "$RC_ERREUR_TECHNIQUE" "Échec de l'enregistrement du bilan du lot"
ligne=$(sql -t -A -F ';' -c "SELECT nb_feuilles, montant_presente, montant_rembourse FROM lot_traitement WHERE lot = DATE '$LOT'") \
    || echec "$RC_ERREUR_TECHNIQUE" "Impossible de relire le bilan du lot"
IFS=';' read -r feuilles presente rembourse <<EOF
$ligne
EOF

{
    printf 'Compte rendu de traitement - lot %s\n\n' "$LOT"
    printf 'Exécution              : %s\n' "$CHAINE_EXECUTION"
    printf 'Fichiers reçus         : %s\n' "$(lire_stat "$STATS" fichiers)"
    printf 'Lignes lues            : %s\n' "$lues"
    printf 'Lignes rejetées        : %s (%s %%)\n' "$rejets" "$(lire_stat "$STATS" taux_rejet)"
    sed -n 's/^motif_\(.*\)=\(.*\)$/  dont \1 : \2/p' "$STATS"
    printf 'Feuilles chargées      : %s\n' "$feuilles"
    printf 'Montant présenté       : %s\n' "$presente"
    printf 'Montant remboursé      : %s\n' "$rembourse"
    printf 'Paiements émis         : %s\n' "$nb_paiements"
    printf 'Fichier de paiements   : %s\n' "$PAIEMENTS"
    printf 'Empreinte SHA-256      : %s\n' "$(cut -d ' ' -f 1 "$DIR_SORTIE/$PAIEMENTS.sha256")"
} > "$DIR_SORTIE/$COMPTE_RENDU.tmp" || echec "$RC_ERREUR_TECHNIQUE" "Impossible d'écrire le compte rendu"
mv "$DIR_SORTIE/$COMPTE_RENDU.tmp" "$DIR_SORTIE/$COMPTE_RENDU" \
    || echec "$RC_ERREUR_TECHNIQUE" "Impossible de publier $COMPTE_RENDU"

log_event INFO bilan "Paiements exportés" paiements="$nb_paiements" montant_rembourse="$rembourse" \
    fichier="$PAIEMENTS"
terminer_job "$RC_OK"
