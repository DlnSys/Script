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