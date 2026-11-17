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

## Contrôle de format

Le job `controler_format` vérifie d'abord l'entête de chaque fichier : un entête différent
arrête le job en erreur fonctionnelle, sans traiter aucune ligne du lot.

Chaque ligne est ensuite contrôlée dans l'ordre suivant ; le premier contrôle en échec donne
le motif de rejet.

| Motif | Contrôle |
|-------|----------|
| `nombre_champs` | 7 champs exactement |
| `id_feuille` | Format `FS-AAAAMMJJ-NNNNNN` |
| `doublon` | Identifiant déjà vu dans le lot, tous fichiers confondus |
| `id_assure` | Format `ASSURE-FICTIF-NNNNNN` |
| `id_professionnel` | Format `PS-FICTIF-NNNN` |
| `date_soins` | Date au format attendu et existante |
| `date_future` | Date postérieure à la date de traitement |
| `code_acte` | Code connu |
| `montant` | Format `NNN.NN`, strictement positif |
| `ald` | `O` ou `N` |

Sorties :

- `valides/FS_AAAAMMJJ_NN.csv` : lignes valides, sans entête ;
- `rejets/FS_AAAAMMJJ_NN.csv.rejets` : une ligne par rejet, `numero_de_ligne;motif;ligne_d_origine` ;
- `travail/controle_AAAAMMJJ.stats` : bilan `cle=valeur` (lignes lues, valides, rejets, taux, détail par motif).

## Fichier de paiements

- Emplacement : `sortie/PAI_AAAAMMJJ.csv`, accompagné de `PAI_AAAAMMJJ.csv.sha256`
- Un paiement par assuré et par lot, trié par assuré

```
id_paiement;id_assure;nb_feuilles;montant
PAI-20250115-000001;ASSURE-FICTIF-000001;2;49.00
```

Avant publication, le total du fichier est comparé au total des remboursements en base ;
un écart arrête le job en erreur fonctionnelle et le fichier n'est pas publié.

## Compte rendu de traitement

`sortie/CR_AAAAMMJJ.txt` : volumes reçus, rejets par motif, montants présentés et remboursés,
nombre de paiements et empreinte du fichier de paiements.
