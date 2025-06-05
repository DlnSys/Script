
# Scripts de Sécurisation SSH – Documentation

Ce dépôt contient deux scripts Bash indépendants et interactifs pour renforcer la sécurité des accès SSH sur un système Linux (Debian-based).

---

## 1. `deploy_ssh_key.sh`

### 🎯 Objectif :
Déployer une ou plusieurs clés SSH Ed25519 sur des serveurs cibles.

### ✅ Fonctionnalités :
- Génération sécurisée de clé SSH (`ed25519`) avec commentaire personnalisé.
- Sélection d'une clé existante si déjà présente.
- Validation de format `user@host`.
- Connexion testée avec `ssh -o BatchMode`.
- Déploiement via `ssh-copy-id`.
- Journalisation dans `/var/log/ssh_deployment_YYYYMMDD_HHMMSS.log`.

### 💬 Utilisation :
```bash
bash deploy_ssh_key.sh
```

### 📜 Contenu du script :
```bash
#!/bin/bash

deploy_ssh_key_interactive() {
    set -euo pipefail  # Mode strict
    
    # Configuration
    readonly SCRIPT_NAME="$(basename "$0")"
    readonly LOG_FILE="/var/log/ssh_deployment_$(date +%Y%m%d_%H%M%S).log"
    readonly DEFAULT_KEY="$HOME/.ssh/id_ed25519.pub"
    
    # Couleurs pour l'affichage
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly NC='\033[0m' # No Color
    
    # Fonction de logging
    log() {
        local level="$1"
        shift
        local message="$*"
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
    }
    
    # Affichage coloré
    print_status() {
        local status="$1"
        local message="$2"
        case "$status" in
            "INFO")  echo -e "${BLUE}[ℹ]${NC} $message" ;;
            "SUCCESS") echo -e "${GREEN}[✓]${NC} $message" ;;
            "WARNING") echo -e "${YELLOW}[⚠]${NC} $message" ;;
            "ERROR")   echo -e "${RED}[✗]${NC} $message" ;;
        esac
        log "$status" "$message"
    }
    
    # Validation d'une adresse IP
    validate_ip() {
        local ip="$1"
        if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            local IFS='.'
            local -a octets=($ip)
            for octet in "${octets[@]}"; do
                if ((octet > 255)); then
                    return 1
                fi
            done
            return 0
        fi
        return 1
    }
    
    # Validation du format utilisateur@serveur
    validate_server_format() {
        local server="$1"
        
        # Format: utilisateur@ip ou utilisateur@hostname
        if [[ ! $server =~ ^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+$ ]]; then
            return 1
        fi
        
        local user="${server%@*}"
        local host="${server#*@}"
        
        # Validation utilisateur (pas de caractères dangereux)
        if [[ $user =~ [[:space:]$\`\'\"] ]]; then
            return 1
        fi
        
        # Validation hostname/IP
        if validate_ip "$host" || [[ $host =~ ^[a-zA-Z0-9.-]+$ ]]; then
            return 0
        fi
        
        return 1
    }
    
    # 📡 Test de connectivité SSH avec timeout
    test_ssh_connectivity() {
        local server="$1"
        local timeout=10
        
        print_status "INFO" "Test de connectivité vers $server..."
        
        if timeout "$timeout" ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no "$server" exit 2>/dev/null; then
            return 0
        else
            return 1
        fi
    }
    
    # 🔑 Génération automatique d'une paire de clés SSH Ed25519
    generate_ssh_key_pair() {
        local private_key_path="$HOME/.ssh/id_ed25519"
        local public_key_path="$HOME/.ssh/id_ed25519.pub"
        
        print_status "INFO" "Génération d'une nouvelle paire de clés SSH Ed25519"
        
        # Création du répertoire .ssh si nécessaire
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        
        # Proposition de commentaires personnalisés avec exemples
        local hostname
        hostname=$(hostname 2>/dev/null || echo "unknown")
        local default_comment="$USER@$hostname-$(date +%Y%m%d)"
        
        echo ""
        print_status "INFO" "Configuration du commentaire de la clé SSH (option -C)"
        echo "Le commentaire permet d'identifier facilement la clé dans les logs et authorized_keys"
        echo ""
        echo "Exemples de commentaires :"
        echo "  • admin@neologix                    (utilisateur@entreprise)"
        echo "  • admin@neologix-$(date +%Y%m%d)              (avec date)"
        echo "  • neologix-prod-servers             (par usage)"
        echo "  • deploy-key-$(date +%Y%m%d)                (clé de déploiement)"
        echo "  • $default_comment        (proposition par défaut)"
        echo ""
        
        read -rp "Commentaire pour la clé SSH (-C) : " key_comment
        
        # Si vide, utiliser le défaut
        if [[ -z "$key_comment" ]]; then
            key_comment="$default_comment"
            print_status "INFO" "Utilisation du commentaire par défaut : $key_comment"
        fi
        
        # Validation du commentaire (pas de caractères dangereux)
        if [[ "$key_comment" =~ [\"\'\\] ]]; then
            print_status "ERROR" "Le commentaire ne peut pas contenir de guillemets ou antislash"
            return 1
        fi
        
        print_status "INFO" "Génération avec commentaire : $key_comment"
        
        # Génération de la paire de clés avec le commentaire personnalisé
        if ssh-keygen -t ed25519 -f "$private_key_path" -C "$key_comment" -N ""; then
            print_status "SUCCESS" "Paire de clés générée avec succès"
            print_status "INFO" "Clé privée : $private_key_path"
            print_status "INFO" "Clé publique : $public_key_path"
            print_status "INFO" "Commentaire : $key_comment"
            
            # Sécurisation des permissions
            chmod 600 "$private_key_path"
            chmod 644 "$public_key_path"
            
            # Affichage de la clé publique pour vérification
            echo ""
            print_status "SUCCESS" "Aperçu de la clé publique générée :"
            echo "$(head -c 80 "$public_key_path")... $key_comment"
            
            echo "$public_key_path"
        else
            print_status "ERROR" "Échec de la génération de la clé SSH"
            exit 1
        fi
    }
    
    # 🔍 Sélection ou création interactive de la clé SSH publique
    select_or_create_ssh_key() {
        local key_path=""
        
        print_status "INFO" "=== Gestion de la clé SSH publique ==="
        
        # Vérification de l'existence de la clé par défaut
        if [[ -f "$DEFAULT_KEY" ]]; then
            echo ""
            print_status "SUCCESS" "Clé par défaut trouvée : $DEFAULT_KEY"
            
            # Affichage des informations de la clé
            local key_info
            key_info=$(ssh-keygen -l -f "$DEFAULT_KEY" 2>/dev/null || echo "Clé invalide")
            echo "Informations : $key_info"
            
            read -rp "Utiliser cette clé existante ? [O/n] : " use_default
            if [[ ${use_default,,} != "n" ]]; then
                key_path="$DEFAULT_KEY"
            fi
        else
            print_status "INFO" "Aucune clé par défaut trouvée ($DEFAULT_KEY)"
        fi
        
        # Si pas de clé sélectionnée, proposer les options
        if [[ -z "$key_path" ]]; then
            echo ""
            echo "Options disponibles :"
            echo "1. Générer une nouvelle paire de clés Ed25519 (recommandé)"
            echo "2. Spécifier le chemin d'une clé existante"
            echo ""
            
            read -rp "Votre choix [1-2] : " key_choice
            
            case "$key_choice" in
                1)
                    # Génération automatique d'une nouvelle clé
                    key_path=$(generate_ssh_key_pair)
                    ;;
                2)
                    # Sélection manuelle d'une clé existante
                    while true; do
                        read -rp "Chemin vers votre clé publique SSH : " key_input
                        key_path="${key_input/#\~/$HOME}"  # Expansion du tilde
                        
                        if [[ -f "$key_path" ]]; then
                            break
                        else
                            print_status "ERROR" "Fichier introuvable : $key_path"
                            read -rp "Réessayer ? [O/n] : " retry
                            if [[ "${retry,,}" == "n" ]]; then
                                exit 1
                            fi
                        fi
                    done
                    ;;
                *)
                    print_status "ERROR" "Choix invalide"
                    exit 1
                    ;;
            esac
        fi
        
        # 🔒 Validation finale du contenu de la clé
        if ! ssh-keygen -l -f "$key_path" &>/dev/null; then
            print_status "ERROR" "Fichier de clé SSH invalide : $key_path"
            exit 1
        fi
        
        # Affichage des informations finales de la clé sélectionnée
        local final_key_info
        final_key_info=$(ssh-keygen -l -f "$key_path" 2>/dev/null || echo "Informations indisponibles")
        print_status "SUCCESS" "Clé SSH validée : $final_key_info"
        
        echo "$key_path"
    }
    
    # Collecte interactive des serveurs
    collect_servers() {
        local -a servers=()
        
        print_status "INFO" "Collecte des serveurs cibles"
        echo "Format attendu : utilisateur@ip ou utilisateur@hostname"
        echo "Exemple : admin@192.168.1.100 ou user@server.domain.com"
        echo ""
        
        while true; do
            read -rp "Quelle id@serveur voulez-vous renseigner (répondez 'non' pour arrêter) : " server_input
            
            if [[ "${server_input,,}" == "non" ]]; then
                break
            fi
            
            if [[ -z "$server_input" ]]; then
                continue
            fi
            
            if validate_server_format "$server_input"; then
                # Vérifier si déjà ajouté
                local already_added=false
                for existing_server in "${servers[@]}"; do
                    if [[ "$existing_server" == "$server_input" ]]; then
                        already_added=true
                        break
                    fi
                done
                
                if [[ "$already_added" == "true" ]]; then
                    print_status "WARNING" "Serveur déjà ajouté : $server_input"
                else
                    servers+=("$server_input")
                    print_status "SUCCESS" "Serveur ajouté : $server_input"
                fi
            else
                print_status "ERROR" "Format invalide. Utilisez : utilisateur@ip ou utilisateur@hostname"
            fi
        done
        
        if [[ ${#servers[@]} -eq 0 ]]; then
            print_status "ERROR" "Aucun serveur spécifié"
            exit 1
        fi
        
        printf '%s\n' "${servers[@]}"
    }
    
    # 🚀 Déploiement de la clé SSH sur un serveur
    deploy_key_to_server() {
        local key_path="$1"
        local server="$2"
        
        print_status "INFO" "Déploiement vers $server"
        
        # Test de connectivité préalable
        if ! test_ssh_connectivity "$server"; then
            print_status "ERROR" "Impossible de se connecter à $server"
            return 1
        fi
        
        # Déploiement avec gestion d'erreur
        if ssh-copy-id -i "$key_path" "$server" 2>&1 | tee -a "$LOG_FILE"; then
            print_status "SUCCESS" "Clé déployée avec succès sur $server"
            return 0
        else
            print_status "ERROR" "Échec du déploiement sur $server"
            return 1
        fi
    }
    
    # Fonction principale
    main_deploy() {
        print_status "INFO" "=== Déploiement de clés SSH - Version Sécurisée ==="
        
        # Vérifications préalables
        if ! command -v ssh-copy-id &>/dev/null; then
            print_status "ERROR" "ssh-copy-id n'est pas installé"
            exit 1
        fi
        
        if ! command -v ssh-keygen &>/dev/null; then
            print_status "ERROR" "ssh-keygen n'est pas installé"
            exit 1
        fi
        
        # 🔑 Sélection ou création de la clé SSH
        local key_path
        key_path=$(select_or_create_ssh_key)
        print_status "SUCCESS" "Clé SSH prête : $key_path"
        
        # Collecte des serveurs
        local -a servers
        readarray -t servers < <(collect_servers)
        
        print_status "INFO" "Serveurs à traiter : ${#servers[@]}"
        
        # Confirmation
        echo ""
        echo "=== RÉCAPITULATIF ==="
        echo "Clé SSH : $key_path"
        echo "Serveurs :"
        printf '  - %s\n' "${servers[@]}"
        echo ""
        
        read -rp "Confirmer le déploiement ? [o/N] : " confirm
        if [[ "${confirm,,}" != "o" ]]; then
            print_status "INFO" "Déploiement annulé"
            exit 0
        fi
        
        # Déploiement
        local success_count=0
        local total_count=${#servers[@]}
        
        for server in "${servers[@]}"; do
            if deploy_key_to_server "$key_path" "$server"; then
                ((success_count++))
            fi
            echo ""
        done
        
        # Rapport final
        print_status "INFO" "=== RAPPORT FINAL ==="
        print_status "SUCCESS" "Déploiements réussis : $success_count/$total_count"
        
        if [[ $success_count -eq $total_count ]]; then
            print_status "SUCCESS" "Tous les déploiements ont réussi !"
        else
            print_status "WARNING" "Certains déploiements ont échoué. Consultez $LOG_FILE"
        fi
    }
    
    # Point d'entrée
    main_deploy "$@"
}

# =============================================================================
# 🔧 2. SÉCURISATION SSH DEBIAN INTERACTIVE
# =============================================================================

deploy_ssh_key_interactive "$@"
```

---

## 2. `secure_ssh_debian.sh`

### 🎯 Objectif :
Configurer le serveur SSH de manière sécurisée.

### ✅ Fonctionnalités :
- Changement du port SSH (hors ports sensibles).
- Restriction à un seul utilisateur autorisé.
- Désactivation du root login et de l’authentification par mot de passe.
- Limitation du nombre de tentatives SSH.
- Sauvegarde automatique de `/etc/ssh/sshd_config`.
- Redémarrage contrôlé du service SSH.
- Configuration automatique du pare-feu (`ufw` ou `iptables`).
- Journalisation dans `/var/log/ssh_security_YYYYMMDD_HHMMSS.log`.

### ⚠ Prérequis :
Ce script **doit être exécuté en tant que root**.

### 💬 Utilisation :
```bash
sudo bash secure_ssh_debian.sh
```

### 📜 Contenu du script :
```bash
#!/bin/bash

secure_ssh_debian() {
    set -euo pipefail  # Mode strict
    
    # Configuration
    readonly SCRIPT_NAME="$(basename "$0")"
    readonly SSH_CONFIG="/etc/ssh/sshd_config"
    readonly LOG_FILE="/var/log/ssh_security_$(date +%Y%m%d_%H%M%S).log"
    readonly BACKUP_DIR="/root/ssh_backups"
    readonly AUDIT_REPORT="/var/log/ssh_audit_$(date +%Y%m%d_%H%M%S).txt"
    
    # Couleurs
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly PURPLE='\033[0;35m'
    readonly NC='\033[0m'
    
    # Variable globale pour l'option d'audit
    GENERATE_AUDIT_REPORT="n"
    
    # Fonction de logging
    log() {
        local level="$1"
        shift
        local message="$*"
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
    }
    
    # Affichage coloré
    print_status() {
        local status="$1"
        local message="$2"
        case "$status" in
            "INFO")    echo -e "${BLUE}[ℹ]${NC} $message" ;;
            "SUCCESS") echo -e "${GREEN}[✓]${NC} $message" ;;
            "WARNING") echo -e "${YELLOW}[⚠]${NC} $message" ;;
            "ERROR")   echo -e "${RED}[✗]${NC} $message" ;;
            "AUDIT")   echo -e "${PURPLE}[📋]${NC} $message" ;;
        esac
        log "$status" "$message"
    }
    
    # Vérification des prérequis
    check_prerequisites() {
        if [[ $EUID -ne 0 ]]; then
            print_status "ERROR" "Ce script doit être exécuté en tant que root"
            exit 1
        fi
        
        if [[ ! -f "$SSH_CONFIG" ]]; then
            print_status "ERROR" "Configuration SSH introuvable : $SSH_CONFIG"
            exit 1
        fi
        
        # Création du répertoire de sauvegarde
        mkdir -p "$BACKUP_DIR"
    }
    
    # Validation du port SSH
    validate_ssh_port() {
        local port="$1"
        
        # Vérification numérique
        if ! [[ "$port" =~ ^[0-9]+$ ]]; then
            return 1
        fi
        
        # Plage valide (éviter les ports réservés critiques)
        if ((port < 1024 || port > 65535)); then
            return 1
        fi
        
        # Ports à éviter (services critiques)
        local -a forbidden_ports=(80 443 21 25 53 110 143 993 995)
        for forbidden in "${forbidden_ports[@]}"; do
            if [[ "$port" -eq "$forbidden" ]]; then
                return 1
            fi
        done
        
        return 0
    }
    
    # Validation du nom d'utilisateur
    validate_username() {
        local username="$1"
        
        # Format Unix standard
        if [[ $username =~ ^[a-z][a-z0-9_-]{0,31}$ ]]; then
            # Vérifier que l'utilisateur existe
            if id "$username" &>/dev/null; then
                return 0
            fi
        fi
        return 1
    }
    
    # Sauvegarde de la configuration
    backup_config() {
        local backup_file="$BACKUP_DIR/sshd_config_$(date +%Y%m%d_%H%M%S)"
        
        if cp "$SSH_CONFIG" "$backup_file"; then
            print_status "SUCCESS" "Configuration sauvegardée : $backup_file"
            echo "$backup_file"
        else
            print_status "ERROR" "Échec de la sauvegarde"
            exit 1
        fi
    }
    
    # Test de la configuration SSH
    test_ssh_config() {
        if sshd -t 2>&1 | tee -a "$LOG_FILE"; then
            return 0
        else
            return 1
        fi
    }
    
    # Restauration de la configuration
    restore_config() {
        local backup_file="$1"
        
        print_status "WARNING" "Restauration de la configuration depuis $backup_file"
        if cp "$backup_file" "$SSH_CONFIG"; then
            print_status "SUCCESS" "Configuration restaurée avec succès"
        else
            print_status "ERROR" "Échec de la restauration"
        fi
    }
    
    # =============================================================================
    # 📋 FONCTION D'AUDIT SSH
    # =============================================================================
    
    generate_ssh_audit_report() {
        print_status "AUDIT" "Génération du rapport d'audit SSH"
        
        # En-tête du rapport
        cat > "$AUDIT_REPORT" << EOF
================================================================================
🔐 RAPPORT D'AUDIT SSH - $(date '+%Y-%m-%d %H:%M:%S')
================================================================================

Serveur : $(hostname)
IP : $(hostname -I | awk '{print $1}' 2>/dev/null || echo "Non disponible")
Utilisateur d'audit : $(whoami)
Version SSH : $(ssh -V 2>&1 | head -n1)

================================================================================
📊 CONFIGURATION ACTUELLE
================================================================================

EOF
        
        # Configuration SSH actuelle
        echo "Configuration SSH (/etc/ssh/sshd_config) :" >> "$AUDIT_REPORT"
        echo "-------------------------------------------" >> "$AUDIT_REPORT"
        
        # Analyse des paramètres critiques
        {
            echo ""
            echo "🔧 PARAMÈTRES DE SÉCURITÉ PRINCIPAUX :"
            echo ""
            
            # Port
            local current_port
            current_port=$(grep -E "^Port " "$SSH_CONFIG" 2>/dev/null | awk '{print $2}' || echo "22 (défaut)")
            echo "Port SSH : $current_port"
            
            # Root login
            local root_login
            root_login=$(grep -E "^PermitRootLogin " "$SSH_CONFIG" 2>/dev/null | awk '{print $2}' || echo "yes (défaut)")
            echo "Connexion root : $root_login"
            
            # Authentification par mot de passe
            local password_auth
            password_auth=$(grep -E "^PasswordAuthentication " "$SSH_CONFIG" 2>/dev/null | awk '{print $2}' || echo "yes (défaut)")
            echo "Authentification par mot de passe : $password_auth"
            
            # Utilisateurs autorisés
            local allowed_users
            allowed_users=$(grep -E "^AllowUsers " "$SSH_CONFIG" 2>/dev/null | sed 's/AllowUsers //' || echo "Tous (non restreint)")
            echo "Utilisateurs autorisés : $allowed_users"
            
            # Tentatives maximum
            local max_auth_tries
            max_auth_tries=$(grep -E "^MaxAuthTries " "$SSH_CONFIG" 2>/dev/null | awk '{print $2}' || echo "6 (défaut)")
            echo "Tentatives d'authentification max : $max_auth_tries"
            
            # Délai de grâce
            local login_grace_time
            login_grace_time=$(grep -E "^LoginGraceTime " "$SSH_CONFIG" 2>/dev/null | awk '{print $2}' || echo "120 (défaut)")
            echo "Délai de grâce de connexion : $login_grace_time secondes"
            
            # X11 Forwarding
            local x11_forward
            x11_forward=$(grep -E "^X11Forwarding " "$SSH_CONFIG" 2>/dev/null | awk '{print $2}' || echo "yes (défaut)")
            echo "Redirection X11 : $x11_forward"
            
            # Protocol
            local protocol
            protocol=$(grep -E "^Protocol " "$SSH_CONFIG" 2>/dev/null | awk '{print $2}' || echo "2 (implicite)")
            echo "Version du protocole : $protocol"
            
        } >> "$AUDIT_REPORT"
        
        # Analyse des connexions actives
        {
            echo ""
            echo "🌐 CONNEXIONS SSH ACTIVES :"
            echo "-------------------------"
            
            if command -v ss &>/dev/null; then
                ss -tuln | grep :22 || echo "Aucune écoute SSH détectée sur le port 22"
                if [[ "$current_port" != "22" ]] && [[ "$current_port" != "22 (défaut)" ]]; then
                    echo ""
                    echo "Écoute sur le port configuré ($current_port) :"
                    ss -tuln | grep ":$current_port " || echo "Aucune écoute détectée sur le port $current_port"
                fi
            else
                netstat -tuln 2>/dev/null | grep :22 || echo "Aucune écoute SSH détectée"
            fi
            
            echo ""
            echo "Sessions SSH actives :"
            who | grep -E "(pts|tty)" || echo "Aucune session SSH active détectée"
            
        } >> "$AUDIT_REPORT"
        
        # Analyse des clés SSH
        {
            echo ""
            echo "🔑 CLÉS SSH DU SYSTÈME :"
            echo "----------------------"
            
            echo "Clés d'hôte disponibles :"
            for key_file in /etc/ssh/ssh_host_*_key.pub; do
                if [[ -f "$key_file" ]]; then
                    local key_info
                    key_info=$(ssh-keygen -l -f "$key_file" 2>/dev/null || echo "Non lisible")
                    echo "  $(basename "$key_file") : $key_info"
                fi
            done
            
            echo ""
            echo "Clés autorisées pour root :"
            if [[ -f "/root/.ssh/authorized_keys" ]]; then
                local key_count
                key_count=$(wc -l < "/root/.ssh/authorized_keys" 2>/dev/null || echo "0")
                echo "  Nombre de clés : $key_count"
                if [[ "$key_count" -gt 0 ]]; then
                    echo "  Détail des clés :"
                    while IFS= read -r key_line; do
                        if [[ -n "$key_line" ]] && [[ ! "$key_line" =~ ^# ]]; then
                            local key_fingerprint
                            key_fingerprint=$(echo "$key_line" | ssh-keygen -l -f - 2>/dev/null || echo "Format invalide")
                            echo "    $key_fingerprint"
                        fi
                    done < "/root/.ssh/authorized_keys"
                fi
            else
                echo "  Aucun fichier authorized_keys pour root"
            fi
            
        } >> "$AUDIT_REPORT"
        
        # Analyse des logs SSH récents
        {
            echo ""
            echo "📜 ANALYSE DES LOGS SSH (24 dernières heures) :"
            echo "---------------------------------------------"
            
            if [[ -f "/var/log/auth.log" ]]; then
                echo "Tentatives de connexion réussies :"
                grep "$(date -d '1 day ago' '+%b %d')" /var/log/auth.log 2>/dev/null | grep "Accepted" | tail -10 || echo "Aucune connexion réussie récente"
                
                echo ""
                echo "Tentatives de connexion échouées (dernières 10) :"
                grep "$(date -d '1 day ago' '+%b %d')" /var/log/auth.log 2>/dev/null | grep "Failed" | tail -10 || echo "Aucune tentative échouée récente"
                
            elif [[ -f "/var/log/secure" ]]; then
                echo "Tentatives de connexion réussies :"
                grep "$(date -d '1 day ago' '+%b %d')" /var/log/secure 2>/dev/null | grep "Accepted" | tail -10 || echo "Aucune connexion réussie récente"
                
                echo ""
                echo "Tentatives de connexion échouées (dernières 10) :"
                grep "$(date -d '1 day ago' '+%b %d')" /var/log/secure 2>/dev/null | grep "Failed" | tail -10 || echo "Aucune tentative échouée récente"
            else
                echo "Logs SSH non trouvés dans les emplacements standards"
            fi
            
        } >> "$AUDIT_REPORT"
        
        # Recommandations de sécurité
        {
            echo ""
            echo "💡 RECOMMANDATIONS DE SÉCURITÉ :"
            echo "------------------------------"
            
            # Vérification du port
            if [[ "$current_port" == "22" ]] || [[ "$current_port" == "22 (défaut)" ]]; then
                echo "⚠️  Changer le port SSH par défaut (22) vers un port non standard"
            else
                echo "✅ Port SSH modifié : $current_port"
            fi
            
            # Vérification de l'accès root
            if [[ "$root_login" == "yes" ]]; then
                echo "⚠️  Désactiver l'accès SSH direct pour root (PermitRootLogin no)"
            else
                echo "✅ Accès root SSH désactivé"
            fi
            
            # Vérification de l'authentification par mot de passe
            if [[ "$password_auth" == "yes" ]]; then
                echo "⚠️  Désactiver l'authentification par mot de passe (PasswordAuthentication no)"
            else
                echo "✅ Authentification par mot de passe désactivée"
            fi
            
            # Vérification des utilisateurs autorisés
            if [[ "$allowed_users" == "Tous (non restreint)" ]]; then
                echo "⚠️  Restreindre l'accès SSH à des utilisateurs spécifiques (AllowUsers)"
            else
                echo "✅ Accès SSH restreint aux utilisateurs : $allowed_users"
            fi
            
            # Vérification des tentatives maximum
            if [[ "$max_auth_tries" -gt 3 ]]; then
                echo "⚠️  Réduire le nombre de tentatives d'authentification (MaxAuthTries 3)"
            else
                echo "✅ Nombre de tentatives d'authentification limité : $max_auth_tries"
            fi
            
            # Vérification

secure_ssh_debian "$@"
```

---

## 📝 Bonnes pratiques
- Testez votre connexion SSH avant de fermer une session après modification.
- Intégrez `fail2ban` après le script de sécurisation pour surveiller et bannir les IP hostiles.
