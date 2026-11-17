# Contrôle ligne à ligne des feuilles de soins (règles dans docs/format_fichier.md).
# Variables attendues : date_lot, actes (codes connus séparés par des espaces), rep_valides, rep_rejets.
# Les lignes valides sont recopiées sans entête ; un rejet s'écrit numero_de_ligne;motif;ligne_d_origine.
# Le bilan cle=valeur sort sur la sortie standard.

BEGIN {
    n = split(actes, liste, " ")
    for (i = 1; i <= n; i++)
        acte_connu[liste[i]] = 1
}

FNR == 1 {
    if (sortie_valides != "") {
        close(sortie_valides)
        close(sortie_rejets)
    }
    nom = FILENAME
    sub(/.*\//, "", nom)
    sortie_valides = rep_valides "/" nom
    sortie_rejets = rep_rejets "/" nom ".rejets"
    printf "" > sortie_valides
    printf "" > sortie_rejets
    next
}

{
    sub(/\r$/, "")
    lues++
    motif = motif_rejet()
    if (motif == "") {
        print > sortie_valides
        deja_vu[$1] = 1
        valides++
    } else {
        print FNR ";" motif ";" $0 > sortie_rejets
        rejets++
        par_motif[motif]++
    }
}

END {
    printf "lues=%d\nvalides=%d\nrejets=%d\n", lues, valides, rejets
    for (m in par_motif)
        printf "motif_%s=%d\n", m, par_motif[m]
}

# Renvoie le motif de rejet de la ligne courante, ou une chaîne vide si elle est valide.
function motif_rejet() {
    if (NF != 7) return "nombre_champs"
    if ($1 !~ /^FS-[0-9]{8}-[0-9]{6}$/) return "id_feuille"
    if ($1 in deja_vu) return "doublon"
    if ($2 !~ /^ASSURE-FICTIF-[0-9]{6}$/) return "id_assure"
    if ($3 !~ /^PS-FICTIF-[0-9]{4}$/) return "id_professionnel"
    if (!date_valide($4)) return "date_soins"
    if ($4 > date_lot) return "date_future"
    if (!($5 in acte_connu)) return "code_acte"
    if ($6 !~ /^[0-9]+\.[0-9][0-9]$/ || $6 + 0 <= 0 || $6 + 0 > 99999999.99) return "montant"
    if ($7 != "O" && $7 != "N") return "ald"
    return ""
}
