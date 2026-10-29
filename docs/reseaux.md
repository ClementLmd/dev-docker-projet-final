# Réseaux et communication inter-conteneurs

Documentation technique pour la **Partie 4** du projet de conteneurisation.

---

## 1. Topologie et configuration réseau

La pile applicative repose sur un réseau bridge utilisateur dédié, nommé `app-network`, déclaré dans `docker-compose.yml` :

```yaml
networks:
  app-network:
    name: app-network
    driver: bridge
```

### Inspection du réseau (`docker network inspect app-network`)

L'exécution de la commande d'inspection met en évidence la configuration IPAM et les conteneurs connectés :

- **Driver** : `bridge`
- **Sous-réseau (Subnet)** : `172.26.0.0/16`
- **Passerelle (Gateway)** : `172.26.0.1`

#### Baux IP attribués aux conteneurs

| Conteneur | Service Compose | Adresse IPv4 | Port(s) interne(s) | Publication hôte |
| :--- | :--- | :--- | :--- | :--- |
| `db` | `db` | `172.26.0.2` | 3306/tcp, 33060/tcp | Aucun (sécurisé) |
| `web` | `web` | `172.26.0.3` | 80/tcp | `127.0.0.1:8080->80/tcp` |
| `adminer` | `adminer` | `172.26.0.4` | 8080/tcp | `127.0.0.1:8081->8080/tcp` |

---

## 2. Résolution DNS interne (Service Discovery)

Sur les réseaux bridge personnalisés, Docker intègre un résolveur DNS interne (`127.0.0.11`) qui associe automatiquement les noms des services Compose à leur adresse IP dynamique sur le réseau.

### Validation de la résolution

Depuis le conteneur `web`, la résolution du nom `db` est immédiate :

```bash
docker exec web getent hosts db
# Sortie : 172.26.0.2 db
```

L'application PHP utilise directement ce nom d'hôte (`DB_HOST=db`) dans `sources/app/db-config.php`, éliminant toute dépendance à une adresse IP fixe.

---

## 3. Tests de connectivité inter-conteneurs

Conformément aux consignes du sujet, la connectivité entre le service `web` et le service `db` a été testée aux niveaux réseau (couche 3) et transport/application (couche 4 & 7).

### 3.1 Test ICMP (`ping db`)

Le paquet `iputils-ping` est installé dans le conteneur `web`. La commande suivante valide l'échange de paquets ICMP :

```bash
docker exec -it web ping -c 3 db
```

**Sortie obtenue :**
```text
PING db (172.26.0.2) 56(84) bytes of data.
64 bytes from db.app-network (172.26.0.2): icmp_seq=1 ttl=64 time=1.11 ms
64 bytes from db.app-network (172.26.0.2): icmp_seq=2 ttl=64 time=0.365 ms
64 bytes from db.app-network (172.26.0.2): icmp_seq=3 ttl=64 time=0.057 ms

--- db ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2033ms
rtt min/avg/max/mdev = 0.057/0.511/1.111/0.442 ms
```
*Constat :* 0 % de perte de paquets et une latence inférieure à 1 ms. Le lien de niveau 3 entre `web` et `db` est optimal.

### 3.2 Test applicatif (`curl http://db:3306`)

La commande `curl` est invoquée depuis `web` vers le port MySQL :

```bash
docker exec -it web curl -v http://db:3306
```

**Sortie obtenue :**
```text
* Host db:3306 was resolved.
* IPv4: 172.26.0.2
* Connected to db (172.26.0.2) port 3306
> GET / HTTP/1.1
> Host: db:3306
> User-Agent: curl/8.14.1
> Accept: */*
> 
* Received HTTP/0.9 when not allowed
* closing connection #0
curl: (1) Received HTTP/0.9 when not allowed
```

**Interprétation technique :**
1. `Host db:3306 was resolved` : confirme la bonne résolution DNS via `127.0.0.11`.
2. `Connected to db (172.26.0.2) port 3306` : confirme l'établissement du Three-Way Handshake TCP sur le port 3306.
3. Le message `Received HTTP/0.9 when not allowed` est normal : curl envoie une requête HTTP à un serveur MySQL qui attend un protocole binaire MySQL. Le serveur renvoie son paquet initial de handshake binaire que curl ne peut parser comme une réponse HTTP valide. Ce test prouve de manière irréfutable que le socket MySQL écoute et répond sur le port 3306.

---

## 4. Isolation réseau et intérêt du bridge personnalisé

L'utilisation d'un réseau bridge utilisateur (`app-network`) apporte trois avantages majeurs par rapport au bridge par défaut de Docker (`bridge`) :

1. **Isolation stricte et étanchéité de sécurité :**
   Les conteneurs d'autres projets ou lancés sans option `--network` sont cantonnés au bridge par défaut et ne peuvent en aucun cas contacter `db`, `web` ou `adminer`.

2. **Résolution DNS automatique par nom de conteneur :**
   Sur le réseau bridge par défaut, Docker ne fournit aucune résolution DNS par nom (nécessiterait l'ancien paramètre déprécié `--link`). Sur un réseau bridge personnalisé, la résolution de noms de services Compose est native et automatique.

3. **Protection de la base de données :**
   Le service `db` ne déclare aucune directive `ports` dans `docker-compose.yml`. Le port 3306 n'est donc **jamais exposé sur l'hôte physique** ni accessible depuis le réseau local d'entreprise. Seuls les conteneurs connectés à `app-network` ont la capacité d'interagir avec la base de données.
