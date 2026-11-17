# Calcul de dates en awk, sans dépendre des options non portables de date(1).
# Conversion date civile <-> nombre de jours depuis le 1970-01-01 (algorithme de H. Hinnant).

function jours_depuis_epoque(a, m, j,    ere, annee_ere, jour_annee, jour_ere) {
    a -= (m <= 2)
    ere = int((a >= 0 ? a : a - 399) / 400)
    annee_ere = a - ere * 400
    jour_annee = int((153 * (m > 2 ? m - 3 : m + 9) + 2) / 5) + j - 1
    jour_ere = annee_ere * 365 + int(annee_ere / 4) - int(annee_ere / 100) + jour_annee
    return ere * 146097 + jour_ere - 719468
}

function date_iso(n,    ere, jour_ere, annee_ere, a, jour_annee, mp, j, m) {
    n += 719468
    ere = int((n >= 0 ? n : n - 146096) / 146097)
    jour_ere = n - ere * 146097
    annee_ere = int((jour_ere - int(jour_ere / 1460) + int(jour_ere / 36524) - int(jour_ere / 146096)) / 365)
    a = annee_ere + ere * 400
    jour_annee = jour_ere - (365 * annee_ere + int(annee_ere / 4) - int(annee_ere / 100))
    mp = int((5 * jour_annee + 2) / 153)
    j = jour_annee - int((153 * mp + 2) / 5) + 1
    m = mp < 10 ? mp + 3 : mp - 9
    return sprintf("%04d-%02d-%02d", a + (m <= 2), m, j)
}

# Vrai si la chaîne est une date AAAA-MM-JJ qui existe : l'aller-retour rejette un 30 février.
function date_valide(d,    p) {
    if (d !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/)
        return 0
    split(d, p, "-")
    if (p[2] < 1 || p[2] > 12 || p[3] < 1 || p[3] > 31)
        return 0
    return date_iso(jours_depuis_epoque(p[1] + 0, p[2] + 0, p[3] + 0)) == d
}
