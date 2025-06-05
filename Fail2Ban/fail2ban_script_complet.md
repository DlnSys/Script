
# 🛡️ Script interactif Fail2ban – version complète

Ce script Bash vous permet de configurer **Fail2ban** de manière **interactive et modulaire**.

## ✅ Fonctionnalités

- Installation automatique de `fail2ban`.
- Affichage et sélection des **services à protéger**.
- Possibilité d’indiquer un **port personnalisé** par service.
- Création automatique de **filtres personnalisés** (WordPress, MySQL, Webmin, Ejabberd).
- Configuration d’une **durée de ban personnalisée** (1h, 1d, 1w, 1y ou permanente).
- Génération d’un fichier `.local` par service dans `/etc/fail2ban/jail.d/`.

---

## 🔧 Script Bash

```bash
#!/bin/bash

# Vérifie que l'utilisateur est root
if [[ $EUID -ne 0 ]]; then
    echo "[!] Ce script doit être exécuté en tant que root."
    exit 1
fi

echo "[+] Mise à jour et installation de fail2ban..."
apt update && apt install -y fail2ban

# Liste des services avec ports par défaut
declare -A SERVICES_PORTS=(
    [ssh]=22
    [apache]=80
    [apache-auth]=80
    [nginx]=80
    [nginx-http-auth]=80
    [postfix]=25
    [dovecot]=143
    [vsftpd]=21
    [proftpd]=21
    [webmin]=10000
    [asterisk]=5060
    [named-refused]=53
    [exim]=25
    [ejabberd]=5222
    [sshd-ddos]=22
    [recidive]=22
    [wordpress]=80
    [mysql-auth]=3306
)

mkdir -p /etc/fail2ban/filter.d /etc/fail2ban/jail.d

# Création automatique des filtres personnalisés
declare -A CUSTOM_FILTERS_CONTENT=(
    [wordpress]='[Definition]\nfailregex = <HOST> -.*"(GET|POST).*/wp-login.php.*\n            <HOST> -.*"(GET|POST).*/xmlrpc.php.*\nignoreregex ='
    [mysql-auth]='[Definition]\nfailregex = Access denied for user .* from \'<HOST>\'\nignoreregex ='
    [webmin]='[Definition]\nfailregex = <HOST> -.*POST /session_login.cgi\nignoreregex ='
    [ejabberd]='[Definition]\nfailregex = Failed .* authentication for .* from <HOST>\nignoreregex ='
)

for FILTER in "${!CUSTOM_FILTERS_CONTENT[@]}"; do
    if [[ ! -f "/etc/fail2ban/filter.d/${FILTER}.conf" ]]; then
        echo -e "${CUSTOM_FILTERS_CONTENT[$FILTER]}" > "/etc/fail2ban/filter.d/${FILTER}.conf"
        echo "[+] Filtre personnalisé créé : $FILTER"
    fi
done

echo "=== Liste des services disponibles ==="
for service in "${!SERVICES_PORTS[@]}"; do
    echo "- $service (port ${SERVICES_PORTS[$service]})"
done

read -rp "Entrez les services à configurer (séparés par virgules) : " INPUT_SERVICES
IFS=',' read -ra SELECTED_SERVICES <<< "$INPUT_SERVICES"

for SERVICE in "${SELECTED_SERVICES[@]}"; do
    SERVICE_TRIM=$(echo "$SERVICE" | xargs)

    if [[ -z "${SERVICES_PORTS[$SERVICE_TRIM]}" ]]; then
        echo "[!] Service non reconnu : $SERVICE_TRIM. Ignoré."
        continue
    fi

    FILTER_FILE="/etc/fail2ban/filter.d/${SERVICE_TRIM}.conf"
    if [[ ! -f "$FILTER_FILE" ]]; then
        echo "[!] Le filtre '${SERVICE_TRIM}.conf' est manquant. Création d'un filtre vide à compléter."
        echo -e "[Definition]\nfailregex = \nignoreregex =" > "$FILTER_FILE"
    fi

    DEFAULT_PORT=${SERVICES_PORTS[$SERVICE_TRIM]}
    read -rp "Souhaitez-vous un port personnalisé pour $SERVICE_TRIM ? [y/N] : " CUSTOM_PORT_CHOICE

    if [[ "$CUSTOM_PORT_CHOICE" =~ ^[Yy]$ ]]; then
        read -rp "Entrez le port personnalisé pour $SERVICE_TRIM : " PORT
    else
        PORT=$DEFAULT_PORT
    fi

    read -rp "Voulez-vous une durée de ban définie (1h,1d,1w,1y) ? Laisser vide pour permanent : " BANTIME_INPUT
    if [[ -z "$BANTIME_INPUT" ]]; then
        BANTIME="-1"
    else
        BANTIME=$BANTIME_INPUT
    fi

    cat > "/etc/fail2ban/jail.d/${SERVICE_TRIM}.local" <<EOF
[${SERVICE_TRIM}]
enabled = true
port = $PORT
filter = ${SERVICE_TRIM}
logpath = /var/log/auth.log
banaction = ufw
maxretry = 5
findtime = 600
bantime = $BANTIME
EOF

    echo "[✓] Jail configurée pour $SERVICE_TRIM (port $PORT, bantime $BANTIME)"
done

systemctl restart fail2ban
echo "[✓] Configuration Fail2ban appliquée."
```

---

## 🔎 Vérifier les filtres

Vous pouvez tester les filtres avec :

```bash
fail2ban-regex /chemin/vers/log /etc/fail2ban/filter.d/wordpress.conf
```

---

## ✅ Remarques

- Aucun changement n'est effectué dans `jail.local`, tout est fait proprement dans `jail.d/`.
- Les filtres personnalisés sont automatiquement créés s'ils sont absents.

