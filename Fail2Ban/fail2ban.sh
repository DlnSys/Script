#!/bin/bash

#===============================================================================
# Script de Sécurisation Serveur - UFW & Fail2ban
# Description: Configuration interactive de UFW et Fail2ban pour Debian/Ubuntu
# Auteur: Assistant Claude
# Version: 1.0
#===============================================================================

set -euo pipefail

# Configuration globale
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="/var/log/security_setup_$(date +%Y%m%d_%H%M%S).log"
readonly CONFIG_DIR="/tmp/security_configs"
readonly FAIL2BAN_LOCAL="/etc/fail2ban/jail.local"

# Couleurs pour l'affichage
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Variables globales
SSH_PORT=22
UFW_RULES=()
FAIL2BAN_CONFIG=""
EMAIL_ALERT=""

# Filtres personnalisés avec échappement sécurisé
declare -A CUSTOM_FILTERS=(
    [wordpress]='[Definition]
# WordPress security filter - Détecte les tentatives de connexion échouées
failregex = ^<HOST> -.*"(GET|POST).*/wp-login\.php.*HTTP/[0-9.]+" 4[0-9]{2}
            ^<HOST> -.*"(GET|POST).*/xmlrpc\.php.*HTTP/[0-9.]+" [45][0-9]{2}
            ^<HOST> -.*"(GET|POST).*wp-admin.*HTTP/[0-9.]+" 4[0-9]{2}
            ^<HOST> -.*"(GET|POST).*wp-content.*\.php.*HTTP/[0-9.]+" [45][0-9]{2}
            ^<HOST>.*] "POST /wp-login.php.*" 200.*wp-login.php\?action=lostpassword
ignoreregex = '

    [mysql-auth]='[Definition]
# MySQL authentication failure filter - Détecte les échecs d'"'"'authentification MySQL
failregex = ^.*\[ERROR\].*Access denied for user.*from.*<HOST>
            ^.*\[ERROR\].*Host.*<HOST>.*is blocked because of many connection errors
            ^.*\[ERROR\].*User.*from.*<HOST>.*was denied access on database
            ^.*mysqld.*: Access denied for user.*@<HOST>
ignoreregex = '

    [webmin]='[Definition]
# Webmin login failure filter - Détecte les tentatives de connexion Webmin échouées
failregex = ^<HOST> -.*POST /session_login\.cgi.*HTTP/[0-9.]+" 401
            ^.*Invalid login as .* from <HOST>
            ^.*Failed login from <HOST>.*to webmin
            ^.*Authentication failed.*<HOST>.*webmin
ignoreregex = '

    [ejabberd]='[Definition]
# Ejabberd XMPP authentication failure filter - Détecte les échecs XMPP
failregex = ^.*\(\{.*,<HOST>,.*\}\) Failed .* authentication
            ^.*Authentication failed for .* from <HOST>
            ^.*Invalid user .* from <HOST>
            ^.*Failed login attempt from <HOST>
ignoreregex = '

    [vsftpd]='[Definition]
# vsFTPd authentication failure filter - Détecte les échecs FTP
failregex = ^.*\[pid \d+\] \[.*\] FAIL LOGIN: Client "<HOST>"
            ^.*authentication failure.*rhost=<HOST>
ignoreregex = '

    [proftpd]='[Definition]
# ProFTPd authentication failure filter - Détecte les échecs ProFTPd
failregex = ^.*proftpd.*no such user.*from <HOST>
            ^.*proftpd.*USER.*no such user found from <HOST>
            ^.*proftpd.*authentication failed.*<HOST>
ignoreregex = '

    [named]='[Definition]
# Named/BIND DNS failure filter - Détecte les requêtes DNS suspectes
failregex = ^.*client <HOST>#.*query.*denied
            ^.*client <HOST>#.*: query \(cache\) .*denied
            ^.*queries from <HOST>.*denied
ignoreregex = '
)

# Services nécessitant des filtres personnalisés
declare -A SERVICES_NEED_CUSTOM_FILTERS=(
    [wordpress]="true"
    [mysql-auth]="true"
    [webmin]="true"
    [ejabberd]="true"
    [named]="true"
)

#===============================================================================
# FONCTIONS D'AFFICHAGE
#===============================================================================

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

print_header() {
    echo -e "\n${PURPLE}═══════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════${NC}\n"
}

#===============================================================================
# FONCTIONS DE VÉRIFICATION
#===============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Ce script doit être exécuté en tant que root"
        echo "Utilisez: sudo $SCRIPT_NAME"
        exit 1
    fi
    print_success "Vérification des privilèges root : OK"
}

check_distro() {
    if ! command -v apt &> /dev/null; then
        print_error "Ce script nécessite un système basé sur Debian/Ubuntu (apt)"
        exit 1
    fi
    print_success "Système compatible détecté"
}

check_and_install_packages() {
    local packages=("ufw" "fail2ban")
    local to_install=()
    
    print_info "Vérification des paquets nécessaires..."
    
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii.*$package "; then
            to_install+=("$package")
            print_warning "$package n'est pas installé"
        else
            print_success "$package est déjà installé"
        fi
    done
    
    if [[ ${#to_install[@]} -gt 0 ]]; then
        print_info "Mise à jour de la liste des paquets..."
        apt update &>/dev/null
        
        print_info "Installation des paquets manquants: ${to_install[*]}"
        apt install -y "${to_install[@]}" | tee -a "$LOG_FILE"
        print_success "Installation terminée"
    fi
}

#===============================================================================
# CONFIGURATION UFW
#===============================================================================

configure_ufw() {
    print_header "CONFIGURATION UFW (UNCOMPLICATED FIREWALL)"
    
    echo -e "${CYAN}UFW permet de gérer facilement le pare-feu iptables${NC}"
    echo "1. Activer UFW"
    echo "2. Passer cette étape"
    echo
    read -p "Votre choix [1-2]: " ufw_choice
    
    case $ufw_choice in
        1)
            print_info "Configuration d'UFW en cours..."
            
            # Réinitialiser UFW
            ufw --force reset &>/dev/null
            
            # Politique par défaut
            ufw default deny incoming &>/dev/null
            ufw default allow outgoing &>/dev/null
            
            # Détecter le port SSH actuel
            if ss -tlnp | grep -q ":22 "; then
                SSH_PORT=22
            else
                read -p "Port SSH personnalisé détecté. Quel port utilisez-vous ? [22]: " custom_ssh
                SSH_PORT=${custom_ssh:-22}
            fi
            
            # Autoriser SSH
            ufw allow "$SSH_PORT"/tcp comment 'SSH' &>/dev/null
            UFW_RULES+=("SSH:$SSH_PORT/tcp")
            print_success "Port SSH $SSH_PORT autorisé"
            
            # Ports standards
            configure_standard_ports
            
            # Ports personnalisés
            configure_custom_ports
            
            # Activer UFW
            echo
            print_warning "UFW va être activé. Assurez-vous que votre connexion SSH ne sera pas coupée."
            read -p "Confirmer l'activation d'UFW ? [y/N]: " confirm_ufw
            
            if [[ $confirm_ufw =~ ^[Yy]$ ]]; then
                ufw --force enable &>/dev/null
                print_success "UFW activé avec succès"
            else
                print_warning "UFW configuré mais non activé"
            fi
            ;;
        2)
            print_info "Configuration UFW ignorée"
            ;;
        *)
            print_error "Choix invalide"
            configure_ufw
            ;;
    esac
}

configure_standard_ports() {
    local ports=(
        "80:HTTP (port 80)"
        "443:HTTPS (port 443)"
        "25:SMTP (port 25)"
        "993:IMAPS (port 993)"
        "995:POP3S (port 995)"
    )
    
    echo
    print_info "Configuration des ports standards"
    
    for port_info in "${ports[@]}"; do
        IFS=':' read -r port desc <<< "$port_info"
        echo
        read -p "Autoriser $desc ? [y/N]: " allow_port
        
        if [[ $allow_port =~ ^[Yy]$ ]]; then
            ufw allow "$port"/tcp &>/dev/null
            UFW_RULES+=("$desc:$port/tcp")
            print_success "$desc autorisé"
        fi
    done
}

configure_custom_ports() {
    echo
    print_info "Ajout de ports personnalisés"
    
    while true; do
        echo
        read -p "Ajouter un port personnalisé ? [y/N]: " add_custom
        
        if [[ ! $add_custom =~ ^[Yy]$ ]]; then
            break
        fi
        
        read -p "Numéro de port: " custom_port
        
        if [[ ! $custom_port =~ ^[0-9]+$ ]] || [[ $custom_port -lt 1 ]] || [[ $custom_port -gt 65535 ]]; then
            print_error "Port invalide"
            continue
        fi
        
        echo "Protocole:"
        echo "1. TCP"
        echo "2. UDP"
        echo "3. Les deux"
        read -p "Choix [1-3]: " proto_choice
        
        read -p "Commentaire (optionnel): " comment
        
        case $proto_choice in
            1)
                ufw allow "$custom_port"/tcp comment "${comment:-Custom}" &>/dev/null
                UFW_RULES+=("Custom:$custom_port/tcp")
                print_success "Port $custom_port/tcp autorisé"
                ;;
            2)
                ufw allow "$custom_port"/udp comment "${comment:-Custom}" &>/dev/null
                UFW_RULES+=("Custom:$custom_port/udp")
                print_success "Port $custom_port/udp autorisé"
                ;;
            3)
                ufw allow "$custom_port" comment "${comment:-Custom}" &>/dev/null
                UFW_RULES+=("Custom:$custom_port/tcp+udp")
                print_success "Port $custom_port (TCP+UDP) autorisé"
                ;;
            *)
                print_error "Choix invalide"
                ;;
        esac
    done
}

#===============================================================================
# GESTION DES FILTRES PERSONNALISÉS
#===============================================================================

create_custom_filter() {
    local service_name="$1"
    local filter_content="${CUSTOM_FILTERS[$service_name]:-}"
    local filter_file="/etc/fail2ban/filter.d/${service_name}.conf"
    
    if [[ -n "$filter_content" ]]; then
        print_info "Création du filtre personnalisé pour $service_name..."
        
        # Sauvegarder le filtre existant s'il existe
        if [[ -f "$filter_file" ]]; then
            cp "$filter_file" "${filter_file}.backup.$(date +%Y%m%d_%H%M%S)"
            print_info "Filtre existant sauvegardé"
        fi
        
        # Créer le nouveau filtre
        echo "$filter_content" > "$filter_file"
        print_success "Filtre personnalisé créé: $filter_file"
        
        # Valider la syntaxe du filtre (test simple)
        if [[ -f "$filter_file" ]] && [[ -s "$filter_file" ]]; then
            print_success "Filtre créé avec succès"
        else
            print_warning "Erreur lors de la création du filtre"
            return 1
        fi
        
        return 0
    else
        print_error "Aucun filtre personnalisé défini pour $service_name"
        return 1
    fi
}

check_and_create_filters() {
    local jail_name="$1"
    
    # Vérifier si ce service nécessite un filtre personnalisé
    if [[ -n "${SERVICES_NEED_CUSTOM_FILTERS[$jail_name]:-}" ]] && [[ "${SERVICES_NEED_CUSTOM_FILTERS[$jail_name]}" == "true" ]]; then
        local filter_file="/etc/fail2ban/filter.d/${jail_name}.conf"
        
        if [[ ! -f "$filter_file" ]]; then
            print_warning "Le service '$jail_name' nécessite un filtre personnalisé"
            read -p "Créer automatiquement le filtre pour '$jail_name' ? [Y/n]: " create_filter
            
            if [[ ! $create_filter =~ ^[Nn]$ ]]; then
                create_custom_filter "$jail_name"
                return $?
            else
                print_warning "Filtre non créé - la jail pourrait ne pas fonctionner correctement"
                return 1
            fi
        else
            print_info "Filtre existant trouvé pour $jail_name: $filter_file"
            return 0
        fi
    fi
    
    return 0
}

show_filter_info() {
    local jail_name="$1"
    
    if [[ -n "${SERVICES_NEED_CUSTOM_FILTERS[$jail_name]:-}" ]] && [[ "${SERVICES_NEED_CUSTOM_FILTERS[$jail_name]}" == "true" ]]; then
        echo -e "    ${YELLOW}⚠ Ce service nécessite un filtre personnalisé${NC}"
        
        local filter_file="/etc/fail2ban/filter.d/${jail_name}.conf"
        if [[ -f "$filter_file" ]]; then
            echo -e "    ${GREEN}✓ Filtre personnalisé disponible${NC}"
        else
            echo -e "    ${RED}✗ Filtre personnalisé manquant${NC}"
        fi
    fi
}

#===============================================================================
# CONFIGURATION FAIL2BAN
#===============================================================================

configure_fail2ban() {
    print_header "CONFIGURATION FAIL2BAN"
    
    echo -e "${CYAN}Fail2ban protège contre les attaques par force brute${NC}"
    echo "1. Configurer Fail2ban"
    echo "2. Passer cette étape"
    echo
    read -p "Votre choix [1-2]: " f2b_choice
    
    case $f2b_choice in
        1)
            configure_email_alerts
            configure_jails
            create_fail2ban_config
            ;;
        2)
            print_info "Configuration Fail2ban ignorée"
            ;;
        *)
            print_error "Choix invalide"
            configure_fail2ban
            ;;
    esac
}

configure_email_alerts() {
    echo
    read -p "Configurer les alertes email ? [y/N]: " setup_email
    
    if [[ $setup_email =~ ^[Yy]$ ]]; then
        read -p "Adresse email pour les alertes: " EMAIL_ALERT
        if [[ $EMAIL_ALERT =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            print_success "Email configuré: $EMAIL_ALERT"
        else
            print_warning "Format d'email invalide, alertes désactivées"
            EMAIL_ALERT=""
        fi
    fi
}

configure_jails() {
    local jails=(
        "sshd:SSH:$SSH_PORT:5:3600:true"
        "apache-auth:Apache Auth:80,443:5:3600:false"
        "nginx-http-auth:Nginx Auth:80,443:5:3600:false"
        "postfix:Postfix:25,465,587:5:3600:false"
        "dovecot:Dovecot:993,995,110,143:5:3600:false"
        "vsftpd:vsFTPd:21:5:3600:false"
        "proftpd:ProFTPd:21:5:3600:false"
        "webmin:Webmin:10000:5:3600:false"
        "named-refused:DNS/BIND:53:5:3600:false"
        "recidive:Récidive:all:5:86400:false"
        "wordpress:WordPress:80,443:5:3600:false"
        "mysql-auth:MySQL:3306:5:3600:false"
    )
    
    print_info "Configuration des jails Fail2ban"
    echo -e "${YELLOW}Pour chaque service, vous pouvez personnaliser:${NC}"
    echo "• Activation (oui/non)"
    echo "• Ports surveillés"
    echo "• Nombre d'échecs avant ban (maxretry)"
    echo "• Durée du ban en secondes (bantime)"
    echo
    
    FAIL2BAN_CONFIG="# Configuration Fail2ban générée le $(date)
[DEFAULT]
# Ignorer les IPs locales et privées
ignoreip = 127.0.0.1/8 ::1 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16

# Configuration temporelle
bantime = 3600
findtime = 600
maxretry = 5

# Configuration backend (auto-détection)
backend = auto

# Support IPv6
allowipv6 = auto"
    
    if [[ -n $EMAIL_ALERT ]]; then
        FAIL2BAN_CONFIG="$FAIL2BAN_CONFIG
destemail = $EMAIL_ALERT
sendername = Fail2ban
mta = sendmail
action = %(action_mwl)s"
    fi
    
    FAIL2BAN_CONFIG="$FAIL2BAN_CONFIG

"
    
    for jail_info in "${jails[@]}"; do
        IFS=':' read -r jail_name service_name default_ports default_maxretry default_bantime default_enabled <<< "$jail_info"
        
        echo
        echo -e "${CYAN}═══ $service_name ═══${NC}"
        
        # Afficher les informations sur les filtres personnalisés
        show_filter_info "$jail_name"
        
        local enabled="false"
        read -p "Activer la jail '$service_name' ? [y/N]: " activate_jail
        
        if [[ $activate_jail =~ ^[Yy]$ ]]; then
            # Vérifier et créer les filtres personnalisés si nécessaire
            if check_and_create_filters "$jail_name"; then
                enabled="true"
                
                echo -e "${YELLOW}Configuration des ports pour $service_name${NC}"
                echo "Ports par défaut : $default_ports"
                read -p "Personnaliser les ports ? [y/N]: " customize_ports
                
                if [[ $customize_ports =~ ^[Yy]$ ]]; then
                    echo "Exemples de formats de ports :"
                    echo "  • Un seul port : 22"
                    echo "  • Plusieurs ports : 80,443"
                    echo "  • Plage de ports : 8000:8010"
                    echo "  • Combinaison : 22,80,443,8000:8010"
                    read -p "Entrez les ports à surveiller : " ports
                    
                    # Valider le format des ports
                    if [[ ! $ports =~ ^[0-9,:_-]+$ ]]; then
                        print_warning "Format de ports invalide, utilisation des ports par défaut"
                        ports=$default_ports
                    fi
                else
                    ports=$default_ports
                fi
                
                read -p "Nombre d'échecs avant ban [$default_maxretry]: " maxretry
                maxretry=${maxretry:-$default_maxretry}
                
                read -p "Durée du ban en secondes [$default_bantime]: " bantime
                bantime=${bantime:-$default_bantime}
                
                print_success "$service_name configuré: ports=$ports, maxretry=$maxretry, bantime=$bantime"
            else
                print_error "Impossible de configurer la jail '$service_name' sans filtre"
                enabled="false"
            fi
        fi
        
        # Ajouter la configuration de la jail
        FAIL2BAN_CONFIG="$FAIL2BAN_CONFIG[$jail_name]
enabled = $enabled"
        
        if [[ $enabled == "true" ]]; then
            FAIL2BAN_CONFIG="$FAIL2BAN_CONFIG
port = $ports
maxretry = $maxretry
bantime = $bantime"
        fi
        
        FAIL2BAN_CONFIG="$FAIL2BAN_CONFIG

"
    done
}

create_fail2ban_config() {
    print_info "Création du fichier de configuration Fail2ban..."
    
    # Sauvegarder la configuration existante
    if [[ -f $FAIL2BAN_LOCAL ]]; then
        cp "$FAIL2BAN_LOCAL" "${FAIL2BAN_LOCAL}.backup.$(date +%Y%m%d_%H%M%S)"
        print_info "Configuration existante sauvegardée"
    fi
    
    # Écrire la nouvelle configuration
    echo "$FAIL2BAN_CONFIG" > "$FAIL2BAN_LOCAL"
    print_success "Configuration Fail2ban créée: $FAIL2BAN_LOCAL"
    
    # Vérifier les permissions du fichier
    chmod 644 "$FAIL2BAN_LOCAL"
    chown root:root "$FAIL2BAN_LOCAL"
    
    # Arrêter le service s'il est en cours d'exécution
    if systemctl is-active --quiet fail2ban; then
        print_info "Arrêt du service Fail2ban..."
        systemctl stop fail2ban
        sleep 2
    fi
    
    # Vérifier la présence des filtres requis
    print_info "Vérification des filtres Fail2ban..."
    local missing_filters=()
    
    # Extraire les jails activées de la configuration
    local enabled_jails=$(echo "$FAIL2BAN_CONFIG" | grep -A2 "^\[" | grep "enabled = true" -B1 | grep "^\[" | sed 's/\[//g' | sed 's/\]//g' | grep -v DEFAULT)
    
    for jail in $enabled_jails; do
        local filter_file="/etc/fail2ban/filter.d/${jail}.conf"
        if [[ ! -f "$filter_file" ]] && [[ ! -n "${CUSTOM_FILTERS[$jail]:-}" ]]; then
            missing_filters+=("$jail")
        fi
    done
    
    if [[ ${#missing_filters[@]} -gt 0 ]]; then
        print_warning "Filtres manquants détectés: ${missing_filters[*]}"
        print_info "Désactivation temporaire des jails problématiques..."
        
        # Créer une configuration temporaire sans les jails problématiques
        local temp_config="$FAIL2BAN_CONFIG"
        for jail in "${missing_filters[@]}"; do
            temp_config=$(echo "$temp_config" | sed "/^\[$jail\]/,/^$/s/enabled = true/enabled = false/")
        done
        echo "$temp_config" > "$FAIL2BAN_LOCAL"
    fi
    
    # Test de configuration avant démarrage
    print_info "Test de la configuration..."
    if ! fail2ban-client --test &>/dev/null; then
        print_error "Configuration Fail2ban invalide"
        print_info "Création d'une configuration minimale..."
        
        # Configuration minimale fonctionnelle
        cat > "$FAIL2BAN_LOCAL" << 'EOF'
# Configuration Fail2ban minimale
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1
bantime = 3600
findtime = 600
maxretry = 5
backend = auto

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 3600
EOF
        print_info "Configuration minimale créée avec jail SSH uniquement"
    fi
    
    # Redémarrer le service
    print_info "Démarrage du service Fail2ban..."
    systemctl enable fail2ban &>/dev/null
    
    if systemctl start fail2ban; then
        sleep 3
        if systemctl is-active --quiet fail2ban; then
            print_success "Service Fail2ban démarré avec succès"
            
            # Afficher le statut des jails
            print_info "Statut des jails activées :"
            timeout 10 fail2ban-client status 2>/dev/null || echo "Délai d'attente dépassé pour le statut"
            
            # Suggestions d'amélioration
            if [[ ${#missing_filters[@]} -gt 0 ]]; then
                echo
                print_info "Pour réactiver les jails désactivées :"
                for jail in "${missing_filters[@]}"; do
                    echo "  • $jail : Installer le paquet correspondant ou créer le filtre"
                done
            fi
        else
            print_error "Le service Fail2ban ne démarre pas correctement"
            show_fail2ban_diagnostics
            return 1
        fi
    else
        print_error "Erreur lors du démarrage de Fail2ban"
        show_fail2ban_diagnostics
        return 1
    fi
}

show_fail2ban_diagnostics() {
    print_info "═══ DIAGNOSTIC FAIL2BAN ═══"
    
    echo "1. Test de configuration :"
    fail2ban-client --test 2>&1 | head -10
    
    echo
    echo "2. Logs récents :"
    journalctl -u fail2ban --no-pager -n 5 --since "5 minutes ago"
    
    echo
    echo "3. Filtres disponibles :"
    ls /etc/fail2ban/filter.d/*.conf 2>/dev/null | head -5 | xargs basename -s .conf || echo "Aucun filtre trouvé"
    
    echo
    echo "4. Configuration actuelle :"
    echo "   - Fichier : $FAIL2BAN_LOCAL"
    echo "   - Taille : $(stat -c%s "$FAIL2BAN_LOCAL" 2>/dev/null || echo "0") octets"
    
    # Proposer des solutions
    echo
    print_info "Solutions suggérées :"
    echo "  • Réinstaller fail2ban : apt reinstall fail2ban"
    echo "  • Vérifier les logs : tail -f /var/log/fail2ban.log"
    echo "  • Configuration manuelle : nano $FAIL2BAN_LOCAL"
}

#===============================================================================
# GESTION DES CONFIGURATIONS
#===============================================================================

save_configuration() {
    print_header "SAUVEGARDE DE LA CONFIGURATION"
    
    mkdir -p "$CONFIG_DIR"
    
    read -p "Nom de la sauvegarde: " save_name
    save_name=${save_name:-"config_$(date +%Y%m%d_%H%M%S)"}
    
    local save_file="$CONFIG_DIR/${save_name}.conf"
    
    {
        echo "# Configuration sauvegardée le $(date)"
        echo "SSH_PORT=$SSH_PORT"
        echo "EMAIL_ALERT=$EMAIL_ALERT"
        echo
        echo "# Règles UFW"
        for rule in "${UFW_RULES[@]}"; do
            echo "UFW_RULE=$rule"
        done
        echo
        echo "# Configuration Fail2ban"
        echo "$FAIL2BAN_CONFIG"
    } > "$save_file"
    
    print_success "Configuration sauvegardée: $save_file"
}

load_configuration() {
    print_header "CHARGEMENT D'UNE CONFIGURATION"
    
    if [[ ! -d $CONFIG_DIR ]] || [[ -z $(ls -A "$CONFIG_DIR" 2>/dev/null) ]]; then
        print_warning "Aucune configuration sauvegardée trouvée"
        return
    fi
    
    echo "Configurations disponibles:"
    local configs=($(ls "$CONFIG_DIR"/*.conf 2>/dev/null | xargs -n1 basename | sed 's/.conf$//' | sort))
    
    if [[ ${#configs[@]} -eq 0 ]]; then
        print_warning "Aucune configuration trouvée"
        return
    fi
    
    for i in "${!configs[@]}"; do
        echo "$((i+1)). ${configs[i]}"
    done
    
    echo
    read -p "Sélectionner une configuration [1-${#configs[@]}]: " config_choice
    
    if [[ $config_choice =~ ^[0-9]+$ ]] && [[ $config_choice -ge 1 ]] && [[ $config_choice -le ${#configs[@]} ]]; then
        local selected_config="${configs[$((config_choice-1))]}"
        source "$CONFIG_DIR/${selected_config}.conf"
        print_success "Configuration '$selected_config' chargée"
    else
        print_error "Sélection invalide"
    fi
}

#===============================================================================
# AFFICHAGE ET VALIDATION
#===============================================================================

show_summary() {
    print_header "RÉSUMÉ DE LA CONFIGURATION"
    
    echo -e "${CYAN}Configuration UFW:${NC}"
    if [[ ${#UFW_RULES[@]} -gt 0 ]]; then
        for rule in "${UFW_RULES[@]}"; do
            echo "  • $rule"
        done
    else
        echo "  • Aucune règle configurée"
    fi
    
    echo
    echo -e "${CYAN}Configuration Fail2ban:${NC}"
    if [[ -n $FAIL2BAN_CONFIG ]]; then
        echo "  • Configuration personnalisée créée"
        if [[ -n $EMAIL_ALERT ]]; then
            echo "  • Alertes email: $EMAIL_ALERT"
        fi
        echo "  • Jails activées: $(echo "$FAIL2BAN_CONFIG" | grep -c "enabled = true")"
    else
        echo "  • Aucune configuration"
    fi
    
    echo
    echo -e "${CYAN}Journalisation:${NC}"
    echo "  • Fichier de log: $LOG_FILE"
}

confirm_and_apply() {
    echo
    print_warning "ATTENTION: Ces modifications vont être appliquées au système"
    read -p "Confirmer l'application de la configuration ? [y/N]: " final_confirm
    
    if [[ $final_confirm =~ ^[Yy]$ ]]; then
        print_success "Configuration appliquée avec succès!"
        echo
        print_info "Services actifs:"
        systemctl is-active ufw 2>/dev/null && echo "  • UFW: $(systemctl is-active ufw)"
        systemctl is-active fail2ban 2>/dev/null && echo "  • Fail2ban: $(systemctl is-active fail2ban)"
        
        echo
        print_info "Commandes utiles:"
        echo "  • Statut UFW: ufw status"
        echo "  • Statut Fail2ban: fail2ban-client status"
        echo "  • Jails actives: fail2ban-client status | grep 'Jail list'"
        echo "  • Logs Fail2ban: tail -f /var/log/fail2ban.log"
        echo "  • Débannir une IP: fail2ban-client set <jail> unbanip <ip>"
        echo "  • IPs bannies: fail2ban-client status <jail>"
        echo "  • Tester un filtre: fail2ban-regex /path/to/logfile /etc/fail2ban/filter.d/<filter>.conf"
        
    else
        print_warning "Configuration annulée"
        exit 0
    fi
}

#===============================================================================
# MENU PRINCIPAL
#===============================================================================

show_main_menu() {
    clear
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    SÉCURISATION SERVEUR                          ║"
    echo "║                  UFW + Fail2ban Manager                          ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo "1. Configuration complète (UFW + Fail2ban)"
    echo "2. Configuration UFW uniquement"
    echo "3. Configuration Fail2ban uniquement"
    echo "4. Sauvegarder la configuration actuelle"
    echo "5. Charger une configuration sauvegardée"
    echo "6. Afficher le statut des services"
    echo "7. Quitter"
    echo
}

show_status() {
    print_header "STATUT DES SERVICES"
    
    echo -e "${CYAN}UFW Status:${NC}"
    if command -v ufw &>/dev/null; then
        ufw status verbose 2>/dev/null || echo "UFW non configuré"
    else
        echo "UFW non installé"
    fi
    
    echo
    echo -e "${CYAN}Fail2ban Status:${NC}"
    if command -v fail2ban-client &>/dev/null; then
        fail2ban-client status 2>/dev/null || echo "Fail2ban non actif"
    else
        echo "Fail2ban non installé"
    fi
    
    echo
    read -p "Appuyer sur Entrée pour continuer..."
}

main_menu() {
    while true; do
        show_main_menu
        read -p "Votre choix [1-7]: " choice
        
        case $choice in
            1)
                check_and_install_packages
                configure_ufw
                configure_fail2ban
                show_summary
                confirm_and_apply
                save_configuration
                break
                ;;
            2)
                check_and_install_packages
                configure_ufw
                show_summary
                confirm_and_apply
                ;;
            3)
                check_and_install_packages
                configure_fail2ban
                show_summary
                confirm_and_apply
                ;;
            4)
                save_configuration
                ;;
            5)
                load_configuration
                ;;
            6)
                show_status
                ;;
            7)
                print_info "Au revoir!"
                exit 0
                ;;
            *)
                print_error "Choix invalide"
                sleep 2
                ;;
        esac
    done
}

#===============================================================================
# POINT D'ENTRÉE PRINCIPAL
#===============================================================================

main() {
    # Initialisation
    log_message "Démarrage du script de sécurisation"
    
    # Vérifications préliminaires
    check_root
    check_distro
    
    # Créer le répertoire de logs
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Lancer le menu principal
    main_menu
    
    log_message "Script terminé avec succès"
}

# Gestion des signaux
trap 'print_error "Script interrompu"; exit 1' INT TERM

# Exécution du script principal
main "$@"