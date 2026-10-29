# Sécurité et bonnes pratiques

Documentation technique pour la **Partie 5** du projet de conteneurisation.

---

## 1. Scan de vulnérabilités statique (Trivy)

Conformément aux exigences du sujet, les images produites ont été auditées à l'aide de l'outil de référence **Trivy** (Aqua Security) afin d'identifier les failles connues (CVE) dans les couches de base et les paquets logiciels.

### 1.1 Scan de l'image applicative `articles-web:dev`

```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image --severity HIGH,CRITICAL articles-web:dev
```

#### Synthèse des résultats :
- **OS détecté** : Debian 13.7 (Trixie)
- **Total vulnérabilités** : 120 (117 HIGH, 3 CRITICAL)

| Bibliothèque | Réf. CVE | Sévérité | Statut | Description & Risque |
| :--- | :--- | :--- | :--- | :--- |
| `libxml2` | CVE-2026-6653 | **CRITICAL** | En attente de correctif | Déni de service par parsing de documents XML malformés |
| `linux-libc-dev` | CVE-2026-93221 | **CRITICAL** | En attente de correctif | Faille bas niveau au sein des headers du noyau Linux Debian |
| `bsdutils` | CVE-2026-76642 | **HIGH** | Affecté | Risque d'exécution de scripts post-hooks de montage |
| `perl` | CVE-2026-9538 | **HIGH** | Fix différé | Déni de service par extraction d'en-têtes tar forgés |

**Analyse & Recommandation :**
Ces vulnérabilités proviennent de la distribution Debian de base embarquée dans `php:8.2-apache`. Pour la mise en production, une bascule vers une variante alpine (`php:8.2-fpm-alpine`) ou l'intégration d'un scanner bloquant dans la chaîne CI/CD (`--exit-code 1 --severity CRITICAL`) garantit le rejet des images non conformes.

---

### 1.2 Scan de l'image de base de données `articles-db:dev`

```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image --severity HIGH,CRITICAL articles-db:dev
```

#### Synthèse des résultats :
- **Base** : Image officielle `mysql:8.4`
- **Total vulnérabilités** : 35 (33 HIGH, 2 CRITICAL)
  - 1 CRITICAL (`certifi` GHSA-6q48-6c7w-9gw2) dans les packages Python d'administration.
  - 1 CRITICAL (`stdlib` CVE-2025-68121) dans le binaire Go `gosu` utilisé par l'entrypoint pour rétrograder les privilèges root vers le compte `mysql`.

---

## 2. Gestion des secrets et absence de fuites d'identifiants

La sécurité des identifiants repose sur une stricte séparation entre le code, la configuration et les secrets :

1. **Variables externalisées dans `.env` :**
   Aucun mot de passe (root MySQL ou compte applicatif) n'est inscrit en dur dans le `Dockerfile`, `docker/mysql/Dockerfile` ou `docker-compose.yml`.
2. **Validation stricte au démarrage :**
   Dans `docker-compose.yml`, les variables sensibles utilisent la syntaxe d'interpolation avec erreur bloquante :
   ```yaml
   DB_PASS: ${DB_PASS:?Definir DB_PASS dans .env}
   MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD:?Definir MYSQL_ROOT_PASSWORD dans .env}
   MYSQL_PASSWORD: ${MYSQL_PASSWORD:?Definir MYSQL_PASSWORD dans .env}
   ```
   Si le fichier `.env` est manquant ou incomplet, Docker Compose refuse catégoriquement d'instancier les conteneurs.
3. **Protection contre les fuites Git et Docker :**
   - `.gitignore` ignore systématiquement `.env`.
   - `.dockerignore` exclut `.env` et `.git` du contexte de build pour empêcher toute incorporation accidentelle dans une couche de l'image.

---

## 3. Limitation stricte des privilèges et durcissement à l'exécution

Le service `web` a été durci dans `docker-compose.yml` en appliquant les recommandations de sécurité les plus strictes :

```yaml
web:
  read_only: true
  security_opt:
    - no-new-privileges:true
  cap_drop:
    - ALL
  cap_add:
    - NET_BIND_SERVICE
  tmpfs:
    - /var/run/apache2:rw,noexec,nosuid,size=16m
    - /var/lock/apache2:rw,noexec,nosuid,size=16m
    - /var/log/apache2:rw,noexec,nosuid,size=32m
    - /tmp:rw,noexec,nosuid,size=32m
```

### Justification technique de chaque mesure :

| Directive | Mécanisme technique | Objectif de sécurité |
| :--- | :--- | :--- |
| `USER www-data` | Conteneur exécuté sous UID 33 (non-root). | Bloque l'élévation de privilèges sur le noyau de l'hôte en cas de faille applicative. |
| `read_only: true` | Système de fichiers racine (`/`) monté en lecture seule. | Empêche tout attaquant de déposer un webshell ou de modifier les sources PHP. |
| `security_opt: no-new-privileges` | Empêche l'acquisition de privilèges via binaires SetUID/SetGID. | Neutralise les attaques d'évasion exploitant des exécutables privilégiés. |
| `cap_drop: ALL` | Révocation intégrale des Linux Capabilities. | Supprime les droits noyau superflus (`CAP_SYS_ADMIN`, `CAP_RAW_NET`, etc.). |
| `cap_add: NET_BIND_SERVICE` | Attribution de la seule capacité indispensable. | Autorise le processus non-root `www-data` à écouter sur le port 80. |
| `tmpfs` | Systèmes de fichiers éphémères en mémoire RAM. | Fournit des espaces d'écriture temporaires non exécutables (`noexec,nosuid`) pour Apache. |

### Preuve du confinement `read_only` :
Une tentative d'écriture dans le dossier web est immédiatement rejetée par le système de fichiers du conteneur :
```bash
docker exec web touch /var/www/html/test.txt
# Résultat : touch: cannot touch '/var/www/html/test.txt': Read-only file system
```

---

## 4. Bannissement du `chmod 777`

Le mode `777` accorde les permissions totales de lecture, écriture et exécution à n'importe quel utilisateur (`rwxrwxrwx`). 
- **Danger critique :** Si un script ou dossier web est configuré en 777, n'importe quel processus compromis ou utilisateur invité peut écraser `index.php`, injecter du code malveillant ou modifier la logique de l'application.
- **Règle appliquée :** Les fichiers appartiennent à `www-data:www-data` avec des droits restreints de lecture (`644` pour les fichiers PHP et `755` pour les répertoires). L'application n'ayant pas de mécanisme de téléversement (upload), Apache n'a nul besoin d'écrire sur le disque.
