# Jeu de données de référence

`FS_20250401_01.csv` contient 10 lignes dont les résultats sont calculés à la main.

| Ligne | Contenu | Résultat attendu |
|-------|---------|------------------|
| 1 | CONS 30.00 | 21.00 (70 %) |
| 2 | INFI 10.00 en ALD | 10.00 (100 %) |
| 3 | PHAR 15.33 | 9.96 (65 %, 9.9645 arrondi) |
| 4 | KINE 16.13 | 9.68 (60 %, 9.678 arrondi) |
| 5 | VISI 40.00, même assuré que la ligne 1 | 28.00 (70 %) |
| 6 | 30 février | rejet `date_soins` |
| 7 | Acte `XXXX` | rejet `code_acte` |
| 8 | Montant négatif | rejet `montant` |
| 9 | Identifiant de la ligne 1 | rejet `doublon` |
| 10 | Soins le lendemain de la date de traitement | rejet `date_future` |

Bilan attendu : 5 feuilles chargées, 5 rejets (50 %), 111.46 présentés, 78.64 remboursés,
4 paiements (l'assuré 000001 reçoit 49.00 pour ses deux feuilles).

Avec 50 % de rejets, le test de bout en bout relève le seuil à 60 % : la chaîne se termine
en alerte, comme elle le ferait en production avec des rejets tolérés.
