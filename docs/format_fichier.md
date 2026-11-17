# Format des fichiers échangés

Toutes les données sont fictives et générées. Les identifiants suivent volontairement un format
sans rapport avec des identifiants réels.

## Feuilles de soins reçues

- Emplacement : `entree/`
- Nom : `FS_AAAAMMJJ_NN.csv` (date de traitement, numéro de fichier dans le lot)
- Encodage UTF-8, séparateur `;`, une ligne d'entête, fins de ligne LF (CRLF toléré)

Entête attendu, à l'identique :

```
id_feuille;id_assure;id_professionnel;date_soins;code_acte;montant;ald
```

| Champ | Format | Règle |
|-------|--------|-------|
| `id_feuille` | `FS-AAAAMMJJ-NNNNNN` | Unique dans le lot |
| `id_assure` | `ASSURE-FICTIF-NNNNNN` | |
| `id_professionnel` | `PS-FICTIF-NNNN` | |
| `date_soins` | `AAAA-MM-JJ` | Date existante, pas postérieure à la date de traitement |
| `code_acte` | `CONS`, `VISI`, `INFI`, `KINE` ou `PHAR` | Voir la table des taux |
| `montant` | Décimal, point et deux décimales (`30.00`) | Strictement positif |
| `ald` | `O` ou `N` | Affection longue durée : prise en charge à 100 % |

Codes d'acte (libellés et taux simplifiés, sans valeur réglementaire) :

| Code | Libellé | Taux |
|------|---------|------|
| `CONS` | Consultation | 70 % |
| `VISI` | Visite à domicile | 70 % |
| `INFI` | Acte infirmier | 60 % |
| `KINE` | Séance de kinésithérapie | 60 % |
| `PHAR` | Délivrance en pharmacie | 65 % |
