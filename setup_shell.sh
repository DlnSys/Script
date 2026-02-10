#!/usr/bin/env bash
set -euo pipefail

log() { echo -e "\n[+] $*\n"; }

# --- Root obligatoire ---
if [[ "$EUID" -ne 0 ]]; then
  echo "[!] Ce script doit être lancé en root."
  echo "➡ Lance: su -   puis: TARGET_USER=dln bash setup.sh"
  exit 1
fi

# --- Utilisateur cible obligatoire ---
TARGET_USER="${TARGET_USER:-}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
  echo "[!] Tu dois définir TARGET_USER (ex: TARGET_USER=dln bash setup.sh)"
  exit 1
fi

# --- Résolution HOME utilisateur ---
USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
if [[ -z "$USER_HOME" || ! -d "$USER_HOME" ]]; then
  echo "[!] HOME introuvable pour l'utilisateur: $TARGET_USER"
  exit 1
fi

ZSHRC="${USER_HOME}/.zshrc"
TMUXCONF="${USER_HOME}/.tmux.conf"
OHMY_DIR="${USER_HOME}/.oh-my-zsh"
P10K_DIR="${USER_HOME}/.oh-my-zsh/custom/themes/powerlevel10k"
FONT_DIR="${USER_HOME}/.local/share/fonts"

log "Utilisateur cible : $TARGET_USER"
log "HOME cible        : $USER_HOME"

# ---------- 1) sudo ----------
log "Installation de sudo (si nécessaire)"
apt update
apt install -y sudo

log "Ajout de $TARGET_USER au groupe sudo"
usermod -aG sudo "$TARGET_USER"

# ---------- 2) Paquets ----------
log "Installation des paquets de base (remplacement de neofetch par fastfetch)"
apt install -y zsh git curl wget fastfetch htop fontconfig lsd tmux

# ---------- 3) Oh My Zsh ----------
log "Installation Oh My Zsh (si absent) pour $TARGET_USER"
if [[ ! -d "$OHMY_DIR" ]]; then
  su - "$TARGET_USER" -c 'RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
else
  log "Oh My Zsh déjà présent"
fi

# ---------- 4) Powerlevel10k ----------
log "Installation/MàJ de Powerlevel10k"
if [[ ! -d "$P10K_DIR" ]]; then
  su - "$TARGET_USER" -c "git clone --depth=1 https://github.com/romkatv/powerlevel10k.git '$P10K_DIR'"
else
  su - "$TARGET_USER" -c "git -C '$P10K_DIR' pull --ff-only || true"
fi

# ---------- 5) .zshrc ----------
log "Configuration de $ZSHRC"
touch "$ZSHRC"
chown "$TARGET_USER:$TARGET_USER" "$ZSHRC"

# Nettoyage des anciens blocs Neofetch si présents
sed -i '/# >>> DLN: NEOFETCH >>>/,/# <<< DLN: NEOFETCH <<</d' "$ZSHRC"

# Thème p10k
if grep -q '^ZSH_THEME=' "$ZSHRC"; then
  sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$ZSHRC"
else
  echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> "$ZSHRC"
fi

# Alias ufull
if ! grep -q 'alias ufull=' "$ZSHRC"; then
  echo 'alias ufull="sudo apt update && sudo apt full-upgrade"' >> "$ZSHRC"
fi

# Bloc LS_COLORS + aliases
BLOCK_BEGIN="# >>> DLN: LS COLORS + LSD ALIASES >>>"
BLOCK_END="# <<< DLN: LS COLORS + LSD ALIASES <<<"

if grep -qF "$BLOCK_BEGIN" "$ZSHRC"; then
  awk -v begin="$BLOCK_BEGIN" -v end="$BLOCK_END" '
    $0==begin {inblock=1; next}
    $0==end {inblock=0; next}
    !inblock {print}
  ' "$ZSHRC" > "${ZSHRC}.tmp" && mv "${ZSHRC}.tmp" "$ZSHRC"
fi

cat >> "$ZSHRC" <<'EOF'

# >>> DLN: LS COLORS + LSD ALIASES >>>
export LS_OPTIONS='--color=auto'
export CLICOLOR=1
export LS_COLORS="di=01;34:fi=00:ln=01;36:so=01;35:pi=01;33:ex=01;32:bd=40;33;01:cd=40;33;01:su=0;31:sg=0;35:tw=0;33:ow=0;34:or=01;31:mi=01;41:*.txt=01;33:*.conf=01;35:*.sh=01;32:*.exe=01;31:*.deb=01;34:*.tar=01;31:*.gz=01;36:*.zip=01;36"

if command -v lsd >/dev/null 2>&1; then
  alias ls='lsd --group-dirs first --icon always'
  alias ll='lsd -l --icon always'
  alias la='lsd -la --icon always'
  alias lt='lsd --tree --icon always'
else
  alias ls='ls --color=auto'
  alias ll='ls -lah --color=auto'
  alias la='ls -A --color=auto'
fi
# <<< DLN: LS COLORS + LSD ALIASES <<<
EOF

# Ajout du bloc FASTFETCH à la toute fin
log "Ajout de la configuration Fastfetch"
# On nettoie d'abord l'ancien bloc Fastfetch s'il existe pour éviter les doublons
sed -i '/# >>> DLN: FASTFETCH >>>/,/# <<< DLN: FASTFETCH <<</d' "$ZSHRC"

cat >> "$ZSHRC" <<'EOF'

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# >>> DLN: FASTFETCH >>>
autoload -Uz add-zsh-hook
run_fastfetch_once() {
  if command -v fastfetch >/dev/null 2>&1; then
    fastfetch --color-keys green --color-title cyan --bright-color true --pipe false
  fi
  add-zsh-hook -d precmd run_fastfetch_once
}
add-zsh-hook precmd run_fastfetch_once
# <<< DLN: FASTFETCH <<<
EOF

chown "$TARGET_USER:$TARGET_USER" "$ZSHRC"

# ---------- 6) Polices ----------
log "Installation des polices MesloLGS NF"
mkdir -p "$FONT_DIR"
chown -R "$TARGET_USER:$TARGET_USER" "$(dirname "$FONT_DIR")"

declare -a fonts=(
  "MesloLGS NF Regular.ttf"
  "MesloLGS NF Bold.ttf"
  "MesloLGS NF Italic.ttf"
  "MesloLGS NF Bold Italic.ttf"
)

for f in "${fonts[@]}"; do
  url="https://github.com/romkatv/powerlevel10k-media/raw/master/$(echo "$f" | sed 's/ /%20/g')"
  if [[ ! -f "$FONT_DIR/$f" ]]; then
    su - "$TARGET_USER" -c "wget -qO '$FONT_DIR/$f' '$url'"
  fi
done
su - "$TARGET_USER" -c "fc-cache -f >/dev/null 2>&1 || true"

# ---------- 7) tmux ----------
log "Écriture de $TMUXCONF"
cat > "$TMUXCONF" <<'EOF'
unbind C-b
set -g prefix M-a
bind M-a send-prefix
set -s escape-time 0
set -g mouse on
set -g base-index 1
setw -g pane-base-index 1
bind v split-window -h
unbind '"'
bind h split-window -v
unbind %
bind r source-file ~/.tmux.conf \; display "Config rechargée !"
set -g default-terminal "screen-256color"
EOF
chown "$TARGET_USER:$TARGET_USER" "$TMUXCONF"

# ---------- 8) Shell par défaut ----------
log "Définition de zsh comme shell par défaut"
chsh -s "$(command -v zsh)" "$TARGET_USER" || true

log "Terminé ✅"
echo "➡ Déconnecte-toi / reconnecte-toi avec $TARGET_USER (important pour le groupe sudo)."
echo "➡ Puis lance : p10k configure"
echo "➡ Rappel: les icônes s'affichent selon la police Nerd Font côté terminal client (Konsole)."
