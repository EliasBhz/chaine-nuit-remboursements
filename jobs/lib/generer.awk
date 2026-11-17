# Écrit un fichier de feuilles de soins fictives sur la sortie standard.
# Variables attendues : graine, fichier (rang dans le lot), nb_lignes, taux_invalides (%), date_lot (AAAA-MM-JJ).
# Format décrit dans docs/format_fichier.md.

BEGIN {
    srand(graine * 100 + fichier)
    nb_actes = split("CONS VISI INFI KINE PHAR", acte, " ")
    split("30.00 40.00  6.30 16.13   2.00", mini, " ")
    split("30.00 40.00 31.50 80.65 150.00", maxi, " ")
    split(date_lot, p, "-")
    jour_lot = jours_depuis_epoque(p[1] + 0, p[2] + 0, p[3] + 0)
    date_compacte = p[1] p[2] p[3]

    print "id_feuille;id_assure;id_professionnel;date_soins;code_acte;montant;ald"
    for (n = 1; n <= nb_lignes; n++) {
        i = int(rand() * nb_actes) + 1
        champ[1] = sprintf("FS-%s-%06d", date_compacte, (fichier - 1) * nb_lignes + n)
        champ[2] = sprintf("ASSURE-FICTIF-%06d", int(rand() * 5000) + 1)
        champ[3] = sprintf("PS-FICTIF-%04d", int(rand() * 300) + 1)
        champ[4] = date_iso(jour_lot - int(rand() * 30))
        champ[5] = acte[i]
        champ[6] = sprintf("%.2f", mini[i] + rand() * (maxi[i] - mini[i]))
        champ[7] = rand() < 0.10 ? "O" : "N"
        nb_champs = 7
        if (rand() * 100 < taux_invalides)
            corrompre()

        ligne = champ[1]
        for (c = 2; c <= nb_champs; c++)
            ligne = ligne ";" champ[c]
        print ligne
    }
}

# Introduit une anomalie parmi celles que le contrôle de format doit détecter.
function corrompre(    type) {
    type = int(rand() * 6) + 1
    if (type == 1)
        champ[2] = "ASSURE-" int(rand() * 1000)
    else if (type == 2)
        champ[4] = substr(champ[4], 1, 4) "-02-30"
    else if (type == 3)
        champ[5] = "XXXX"
    else if (type == 4)
        champ[6] = "-" champ[6]
    else if (type == 5)
        nb_champs = 6
    else
        champ[7] = "X"
}
