#!/bin/bash

# Script de sécurisation SSH interactif pour Debian/Ubuntu
# Version: 1.0

set -euo pipefail

# Variables globales
SCRIPT_NAME="SSH Security Hardening"
SSH_CONFIG="/etc/ssh/sshd_config"
BACKUP_DIR="/root/ssh_backups"
LOG_FILE="/var/log/ssh_security_$(date +%Y%m%d_%H%M%S).log"
TIMESTAMP=$(date '+%Y-%m-%d_%H:%M:%S')

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Fonction de logging et affichage
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    case "$level" in
        "INFO")  echo -e "${BLUE}[INFO]${NC} $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        "WARNING") echo -e "${YELLOW}[WARNING]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "QUESTION") echo -e "${CYAN}[?]${NC} $message" ;;
    esac
}

# Fonction de confirmation utilisateur
confirm_action() {
    local prompt="$1"
    local response
    
    while true; do
        log_message "QUESTION" "$prompt (o/n): "
        read -r response
        case "$response" in
            [oO]|[oO][uU][iI]) return 0 ;;
            [nN]|[nN][oO][nN]) return 1 ;;
            *) log_message "WARNING" "Réponse invalide. Veuillez saisir 'o' pour oui ou 'n' pour non." ;;
        esac
    done
}

# Contrôles initiaux
check_prerequisites() {
    log_message "INFO" "Démarrage du $SCRIPT_NAME"
    
    # Vérification root
    if [[ $EUID -ne 0 ]]; then
        log_message "ERROR" "Ce script doit être exécuté en tant que root"
        exit 1
    fi
    
    # Vérification fichier SSH config
    if [[ ! -f "$SSH_CONFIG" ]]; then
        log_message "ERROR" "Fichier $SSH_CONFIG introuvable"
        exit 1
    fi
    
    # Création du répertoire de log
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    
    log_message "SUCCESS" "Contrôles initiaux réussis"
}

# Sauvegarde de la configuration SSH
backup_ssh_config() {
    log_message "INFO" "Création de la sauvegarde SSH"
    
    mkdir -p "$BACKUP_DIR"
    local backup_file="$BACKUP_DIR/sshd_config_backup_$(date +%Y%m%d_%H%M%S)"
    
    if cp "$SSH_CONFIG" "$backup_file"; then
        log_message "SUCCESS" "Sauvegarde créée: $backup_file"
        echo "$backup_file"
    else
        log_message "ERROR" "Échec de la sauvegarde"
        exit 1
    fi
}

# Validation du port SSH
validate_ssh_port() {
    local port="$1"
    
    # Vérifier que c'est un nombre
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    
    # Vérifier la plage valide
    if [[ $port -lt 1024 || $port -gt 65535 ]]; then
        return 1
    fi
    
    # Vérifier que le port n'est pas déjà utilisé
    if ss -tlnp | grep -q ":$port "; then
        return 1
    fi
    
    return 0
}

# Collecte des choix utilisateur
collect_user_preferences() {
    log_message "INFO" "Configuration des paramètres de sécurité"
    
    declare -g DISABLE_ROOT_LOGIN=false
    declare -g DISABLE_PASSWORD_AUTH=false
    declare -g CHANGE_SSH_PORT=false
    declare -g NEW_SSH_PORT=""
    
    # Désactiver l'accès root
    if confirm_action "Désactiver l'accès root via SSH ?"; then
        DISABLE_ROOT_LOGIN=true
        log_message "INFO" "Accès root SSH sera désactivé"
    fi
    
    # Désactiver l'authentification par mot de passe
    if confirm_action "Désactiver l'authentification par mot de passe (clés SSH uniquement) ?"; then
        DISABLE_PASSWORD_AUTH=true
        log_message "WARNING" "Assurez-vous d'avoir configuré vos clés SSH avant d'appliquer ce changement !"
    fi
    
    # Changer le port SSH
    if confirm_action "Modifier le port SSH par défaut (22) ?"; then
        CHANGE_SSH_PORT=true
        
        while true; do
            log_message "QUESTION" "Entrez le nouveau port SSH (1024-65535): "
            read -r NEW_SSH_PORT
            
            if validate_ssh_port "$NEW_SSH_PORT"; then
                log_message "SUCCESS" "Port $NEW_SSH_PORT validé"
                break
            else
                log_message "ERROR" "Port invalide ou déjà utilisé. Réessayez."
            fi
        done
    fi
}

# Application des modifications SSH
apply_ssh_changes() {
    log_message "INFO" "Application des modifications SSH"
    
    local temp_config=$(mktemp)
    cp "$SSH_CONFIG" "$temp_config"
    
    # Désactiver l'accès root
    if [[ "$DISABLE_ROOT_LOGIN" == true ]]; then
        if grep -q "^PermitRootLogin" "$temp_config"; then
            sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' "$temp_config"
        else
            echo "PermitRootLogin no" >> "$temp_config"
        fi
        log_message "SUCCESS" "Accès root désactivé"
    fi
    
    # Désactiver l'authentification par mot de passe
    if [[ "$DISABLE_PASSWORD_AUTH" == true ]]; then
        if grep -q "^PasswordAuthentication" "$temp_config"; then
            sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' "$temp_config"
        else
            echo "PasswordAuthentication no" >> "$temp_config"
        fi
        
        if grep -q "^PubkeyAuthentication" "$temp_config"; then
            sed -i 's/^PubkeyAuthentication.*/PubkeyAuthentication yes/' "$temp_config"
        else
            echo "PubkeyAuthentication yes" >> "$temp_config"
        fi
        log_message "SUCCESS" "Authentification par mot de passe désactivée"
    fi
    
    # Changer le port SSH
    if [[ "$CHANGE_SSH_PORT" == true ]]; then
        if grep -q "^Port" "$temp_config"; then
            sed -i "s/^Port.*/Port $NEW_SSH_PORT/" "$temp_config"
        else
            echo "Port $NEW_SSH_PORT" >> "$temp_config"
        fi
        log_message "SUCCESS" "Port SSH modifié vers $NEW_SSH_PORT"
    fi
    
    # Vérifier la syntaxe de la configuration
    if sshd -t -f "$temp_config"; then
        cp "$temp_config" "$SSH_CONFIG"
        log_message "SUCCESS" "Configuration SSH mise à jour"
    else
        log_message "ERROR" "Erreur de syntaxe dans la configuration SSH"
        rm "$temp_config"
        exit 1
    fi
    
    rm "$temp_config"
}

# Génération du résumé
generate_summary() {
    log_message "INFO" "=== RÉSUMÉ DES MODIFICATIONS ==="
    
    if [[ "$DISABLE_ROOT_LOGIN" == true ]]; then
        log_message "INFO" "✓ Accès root SSH désactivé"
    fi
    
    if [[ "$DISABLE_PASSWORD_AUTH" == true ]]; then
        log_message "INFO" "✓ Authentification par mot de passe désactivée"
        log_message "WARNING" "⚠ Seules les clés SSH seront acceptées"
    fi
    
    if [[ "$CHANGE_SSH_PORT" == true ]]; then
        log_message "INFO" "✓ Port SSH modifié: 22 → $NEW_SSH_PORT"
        log_message "WARNING" "⚠ N'oubliez pas de mettre à jour votre firewall"
    fi
    
    if [[ "$DISABLE_ROOT_LOGIN" == false && "$DISABLE_PASSWORD_AUTH" == false && "$CHANGE_SSH_PORT" == false ]]; then
        log_message "INFO" "Aucune modification sélectionnée"
        return 1
    fi
    
    return 0
}

# Redémarrage du service SSH
restart_ssh_service() {
    log_message "INFO" "Redémarrage du service SSH"
    
    if systemctl is-active --quiet ssh; then
        SERVICE_NAME="ssh"
    elif systemctl is-active --quiet sshd; then
        SERVICE_NAME="sshd"
    else
        log_message "ERROR" "Service SSH introuvable"
        exit 1
    fi
    
    if systemctl reload "$SERVICE_NAME"; then
        log_message "SUCCESS" "Service SSH rechargé avec succès"
    else
        log_message "ERROR" "Échec du rechargement SSH"
        exit 1
    fi
}

# Fonction principale
main() {
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}    SSH Security Hardening      ${NC}"
    echo -e "${CYAN}================================${NC}"
    echo
    
    # Contrôles initiaux
    check_prerequisites
    
    # Sauvegarde
    local backup_file
    backup_file=$(backup_ssh_config)
    
    # Collecte des préférences
    collect_user_preferences
    
    # Génération et confirmation du résumé
    if ! generate_summary; then
        log_message "INFO" "Aucune modification à appliquer. Script terminé."
        exit 0
    fi
    
    echo
    if ! confirm_action "Appliquer ces modifications maintenant ?"; then
        log_message "INFO" "Modifications annulées par l'utilisateur"
        log_message "INFO" "Sauvegarde disponible: $backup_file"
        exit 0
    fi
    
    # Application des modifications
    apply_ssh_changes
    
    # Redémarrage du service
    if confirm_action "Redémarrer le service SSH maintenant ?"; then
        restart_ssh_service
    else
        log_message "WARNING" "N'oubliez pas de redémarrer SSH: systemctl reload ssh"
    fi
    
    # Résumé final
    echo
    log_message "SUCCESS" "=== SÉCURISATION SSH TERMINÉE ==="
    log_message "INFO" "Log complet: $LOG_FILE"
    log_message "INFO" "Sauvegarde: $backup_file"
    
    if [[ "$CHANGE_SSH_PORT" == true ]]; then
        log_message "WARNING" "IMPORTANT: Connectez-vous maintenant avec: ssh -p $NEW_SSH_PORT"
    fi
    
    if [[ "$DISABLE_PASSWORD_AUTH" == true ]]; then
        log_message "WARNING" "IMPORTANT: Testez votre connexion par clé SSH avant de fermer cette session"
    fi
}

# Gestion des signaux pour nettoyage
trap 'log_message "ERROR" "Script interrompu"; exit 1' INT TERM

# Lancement du script principal
main "$@"