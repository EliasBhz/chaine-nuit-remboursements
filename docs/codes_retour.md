# Codes retour et logs

## Codes retour des jobs

| Code | Signification | Conséquence dans la chaîne |
|------|---------------|----------------------------|
| 0 | Succès | Le job suivant est lancé. |
| 1 | Succès avec alerte (par exemple des rejets sous le seuil toléré) | La chaîne continue, l'alerte est tracée et remontée en fin de chaîne. |
| 2 | Erreur fonctionnelle : données absentes, illisibles ou incohérentes | Arrêt sans relance automatique : relancer ne changerait rien, il faut analyser. |
| 3 | Erreur technique : base injoignable, disque, interruption par signal | Relance automatique selon le nombre d'essais prévu, puis arrêt. |

La distinction entre 2 et 3 est la règle d'exploitation centrale : seule une erreur technique
a une chance de disparaître d'elle-même (base redémarrée, réseau rétabli).

## Format des logs

Chaque job écrit une ligne JSON par événement, sur sa sortie standard et dans
`$CHAINE_LOGS/chaine-AAAAMMJJ.jsonl` (un fichier par date de traitement).

| Champ | Contenu |
|-------|---------|
| `horodatage` | Date et heure UTC, ISO 8601 |
| `niveau` | `INFO`, `ALERTE` ou `ERREUR` |
| `chaine` | Nom de la chaîne |
| `execution` | Identifiant de l'exécution fourni par l'ordonnanceur (`manuelle` hors ordonnanceur) |
| `job` | Nom du job |
| `lot` | Date de traitement, format `AAAA-MM-JJ` |
| `evenement` | Type d'événement : `debut`, `fin`, `erreur`, `bilan`… |
| `message` | Texte lisible par un opérateur |

Les champs supplémentaires dépendent de l'événement (`code_retour`, `duree_s`, `lignes`…).
Les valeurs numériques sont écrites comme des nombres pour pouvoir être agrégées.

Exemple :

```json
{"horodatage":"2025-01-15T01:12:03Z","niveau":"INFO","chaine":"nuit_remboursements","execution":"20250115T010000","job":"charger_base","lot":"2025-01-15","evenement":"fin","message":"Fin du job","code_retour":0,"duree_s":2}
```
