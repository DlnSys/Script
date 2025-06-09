# ============================================================================
# SCRIPT POWERSHELL - ADMINISTRATION ACTIVE DIRECTORY
# ============================================================================
# Description : Script interactif pour créer des OU, groupes et utilisateurs AD
# Auteur : DlnSys
# Version : 3.0 - Workflow optimisé
# ============================================================================

# Import du module Active Directory
Import-Module ActiveDirectory

# ============================================================================
# VARIABLES GLOBALES ET CONFIGURATION
# ============================================================================

# Variables globales pour stocker les informations saisies
$Global:DomainInfo = @{}
$Global:OUPrincipale = ""
$Global:OUList = @()
$Global:GroupesList = @()
$Global:MotDePasseGenerique = ""
$Global:FormatEmail = ""
$Global:LogFile = ""
$Global:ServicesList = @()

# ============================================================================
# FONCTIONS UTILITAIRES
# ============================================================================

function Write-Log {
    param(
        [string]$Message,
        [string]$Type = "INFO"
    )
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$TimeStamp] [$Type] $Message"
    
    # Affichage console avec couleurs
    switch ($Type) {
        "ERROR" { Write-Host $LogEntry -ForegroundColor Red }
        "SUCCESS" { Write-Host $LogEntry -ForegroundColor Green }
        "WARNING" { Write-Host $LogEntry -ForegroundColor Yellow }
        default { Write-Host $LogEntry -ForegroundColor Cyan }
    }
    
    # Écriture dans le fichier de log
    if (![string]::IsNullOrEmpty($Global:LogFile)) {
        Add-Content -Path $Global:LogFile -Value $LogEntry
    }
}

function Show-Banner {
    Clear-Host
    Write-Host "============================================================================" -ForegroundColor Magenta
    Write-Host "           SCRIPT D'ADMINISTRATION ACTIVE DIRECTORY v2.0" -ForegroundColor Magenta
    Write-Host "============================================================================" -ForegroundColor Magenta
    Write-Host ""
}

function Confirm-Action {
    param(
        [string]$Message,
        [string]$DefaultChoice = "O"
    )
    
    try {
        $prompt = if ($DefaultChoice -eq "O") { "$Message (O/N) [O]" } else { "$Message (O/N) [N]" }
        $response = Read-Host $prompt
        
        # Si aucune réponse, utiliser le choix par défaut
        if ([string]::IsNullOrWhiteSpace($response)) {
            $response = $DefaultChoice
        }
        
        # Retourner true si O ou o, false sinon
        return ($response -match '^[Oo]$')
    }
    catch {
        Write-Log "Erreur dans Confirm-Action : $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# ============================================================================
# ÉTAPE 1 : CONFIGURATION INITIALE
# ============================================================================

function Initialize-Configuration {
    Show-Banner
    Write-Host "ÉTAPE 1 : CONFIGURATION INITIALE" -ForegroundColor Yellow
    Write-Host "=================================" -ForegroundColor Yellow
    Write-Host ""
    
    # Configuration automatique des logs
    $Global:LogFile = "C:\AD_Administration_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    Write-Host "Les logs seront automatiquement enregistrés dans : $Global:LogFile" -ForegroundColor Cyan
    Write-Log "Démarrage du script d'administration Active Directory v2.0"
    
    # Configuration du domaine
    Write-Host ""
    Write-Host "Configuration du domaine :" -ForegroundColor Cyan
    
    # Détection des domaines existants
    try {
        $currentDomain = Get-ADDomain -ErrorAction Stop
        $availableDomains = @($currentDomain)
        
        # Tentative de récupération d'autres domaines dans la forêt
        try {
            $forest = Get-ADForest -ErrorAction SilentlyContinue
            if ($forest) {
                $availableDomains = $forest.Domains | ForEach-Object {
                    try {
                        Get-ADDomain -Identity $_ -ErrorAction SilentlyContinue
                    } catch { 
                        # Ignorer les erreurs de domaines inaccessibles
                    }
                } | Where-Object { $_ -ne $null }
            }
        } catch { 
            # Continuer avec le domaine courant uniquement
        }
        
        if ($availableDomains.Count -gt 0) {
            Write-Host "Domaines Active Directory détectés :" -ForegroundColor Green
            for ($i = 0; $i -lt $availableDomains.Count; $i++) {
                Write-Host "  $($i + 1). $($availableDomains[$i].DNSRoot)" -ForegroundColor Green
            }
            Write-Host "  $($availableDomains.Count + 1). Spécifier un nouveau domaine" -ForegroundColor Yellow
            Write-Host ""
            
            do {
                $choixDomain = Read-Host "Choisissez un domaine (1-$($availableDomains.Count + 1))"
            } while ($choixDomain -notmatch '^\d+$' -or [int]$choixDomain -lt 1 -or [int]$choixDomain -gt ($availableDomains.Count + 1))
            
            if ([int]$choixDomain -le $availableDomains.Count) {
                # Utilisation d'un domaine existant
                $selectedDomain = $availableDomains[[int]$choixDomain - 1]
                $Global:DomainInfo = @{
                    Name = $selectedDomain.DNSRoot
                    DN = $selectedDomain.DistinguishedName
                }
                Write-Log "Domaine existant sélectionné : $($Global:DomainInfo.Name)" "SUCCESS"
            } else {
                # Spécification d'un nouveau domaine
                $domainName = Read-Host "Entrez le nom du domaine (ex: entreprise.local)"
                $domainParts = $domainName.Split('.')
                
                $Global:DomainInfo = @{
                    Name = $domainName
                    DN = ($domainParts | ForEach-Object { "DC=$_" }) -join ","
                }
                Write-Log "Nouveau domaine configuré : $($Global:DomainInfo.Name)" "SUCCESS"
            }
        }
    }
    catch {
        # Erreur lors de la détection, saisie manuelle
        Write-Host "Configuration manuelle du domaine requise." -ForegroundColor Yellow
        $domainName = Read-Host "Entrez le nom du domaine (ex: entreprise.local)"
        $domainParts = $domainName.Split('.')
        
        $Global:DomainInfo = @{
            Name = $domainName
            DN = ($domainParts | ForEach-Object { "DC=$_" }) -join ","
        }
        Write-Log "Domaine configuré manuellement : $($Global:DomainInfo.Name)" "SUCCESS"
    }
    
    # Configuration de l'OU principale
    Write-Host ""
    Write-Host "Configuration de l'OU principale :" -ForegroundColor Cyan
    $ouName = Read-Host "Entrez le nom de l'OU principale (sans le préfixe OU_)"
    $Global:OUPrincipale = "OU_$ouName"
    Write-Log "OU principale configurée : $Global:OUPrincipale"
    
    # Configuration du mot de passe générique
    Write-Host ""
    Write-Host "Configuration du mot de passe générique :" -ForegroundColor Cyan
    do {
        $Global:MotDePasseGenerique = Read-Host "Entrez le mot de passe générique pour tous les utilisateurs" -AsSecureString
        $confirmPassword = Read-Host "Confirmez le mot de passe" -AsSecureString
        
        $pwd1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Global:MotDePasseGenerique))
        $pwd2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($confirmPassword))
        
        if ($pwd1 -ne $pwd2) {
            Write-Host "Les mots de passe ne correspondent pas. Recommencez." -ForegroundColor Red
        }
    } while ($pwd1 -ne $pwd2)
    
    Write-Log "Mot de passe générique configuré"
    
    # Configuration du format d'email
    Write-Host ""
    Write-Host "Configuration du format d'email :" -ForegroundColor Cyan
    Write-Host "1. P.nom@domain (ex: J.dupont@entreprise.local)"
    Write-Host "2. prenom.nom@domain (ex: jean.dupont@entreprise.local)"
    Write-Host "3. nom.prenom@domain (ex: dupont.jean@entreprise.local)"
    
    do {
        $choixFormat = Read-Host "Choisissez le format (1, 2 ou 3)"
    } while ($choixFormat -notmatch '^[123]$')
    
    switch ($choixFormat) {
        "1" { $Global:FormatEmail = "P.nom@$($Global:DomainInfo.Name)" }
        "2" { $Global:FormatEmail = "prenom.nom@$($Global:DomainInfo.Name)" }
        "3" { $Global:FormatEmail = "nom.prenom@$($Global:DomainInfo.Name)" }
    }
    
    Write-Log "Format d'email configuré : $Global:FormatEmail"
    
    Write-Host ""
    Write-Host "Configuration terminée !" -ForegroundColor Green
    Read-Host "Appuyez sur Entrée pour continuer"
}

# ============================================================================
# ÉTAPE 2 : CRÉATION DES UNITÉS D'ORGANISATION
# ============================================================================

function Create-OrganizationalUnits {
    Show-Banner
    Write-Host "ÉTAPE 2 : CRÉATION DES UNITÉS D'ORGANISATION" -ForegroundColor Yellow
    Write-Host "=============================================" -ForegroundColor Yellow
    Write-Host ""
    
    # Création de l'OU principale
    Write-Host "Création de l'OU principale : $Global:OUPrincipale" -ForegroundColor Cyan
    
    if (Confirm-Action "Confirmer la création de l'OU principale '$Global:OUPrincipale'") {
        try {
            New-ADOrganizationalUnit -Name $Global:OUPrincipale -Path $Global:DomainInfo.DN -ErrorAction Stop
            Write-Log "OU principale créée avec succès : $Global:OUPrincipale" "SUCCESS"
        }
        catch {
            if ($_.Exception.Message -like "*already exists*" -or $_.Exception.Message -like "*existe déjà*") {
                Write-Log "OU principale existe déjà : $Global:OUPrincipale" "WARNING"
            } else {
                Write-Log "Erreur lors de la création de l'OU principale : $($_.Exception.Message)" "ERROR"
                Write-Host "Voulez-vous continuer malgré cette erreur ? (O/N)" -ForegroundColor Yellow
                $continueChoice = Read-Host
                if ($continueChoice -notmatch '^[Oo]$') {
                    return $false
                }
            }
        }
    } else {
        Write-Log "Création de l'OU principale annulée par l'utilisateur" "WARNING"
        Write-Host "Le script ne peut pas continuer sans l'OU principale." -ForegroundColor Red
        Read-Host "Appuyez sur Entrée pour retourner au menu"
        return $false
    }
    
    # Création de l'OU pour les Domain Local
    $OUDomainLocal = "OU_DomainLocal"
    Write-Host ""
    Write-Host "Création de l'OU pour les groupes Domain Local : $OUDomainLocal" -ForegroundColor Cyan
    
    if (Confirm-Action "Confirmer la création de l'OU '$OUDomainLocal'") {
        try {
            New-ADOrganizationalUnit -Name $OUDomainLocal -Path "OU=$Global:OUPrincipale,$($Global:DomainInfo.DN)" -ErrorAction Stop
            Write-Log "OU Domain Local créée avec succès : $OUDomainLocal" "SUCCESS"
        }
        catch {
            if ($_.Exception.Message -like "*already exists*" -or $_.Exception.Message -like "*existe déjà*") {
                Write-Log "OU Domain Local existe déjà : $OUDomainLocal" "WARNING"
            } else {
                Write-Log "Erreur lors de la création de l'OU Domain Local : $($_.Exception.Message)" "ERROR"
            }
        }
    }
    
    # Saisie des OU de services
    Write-Host ""
    Write-Host "Saisie des unités d'organisation de services :" -ForegroundColor Cyan
    Write-Host "Entrez les noms des services/départements (le préfixe OU_ sera ajouté automatiquement)"
    Write-Host "Tapez 'fin' ou laissez vide pour terminer la saisie"
    Write-Host ""
    
    do {
        $serviceName = Read-Host "Nom du service"
        
        if (![string]::IsNullOrWhiteSpace($serviceName) -and $serviceName -ne "fin") {
            $ouName = "OU_$serviceName"
            
            if (Confirm-Action "Confirmer la création de l'OU '$ouName'") {
                try {
                    New-ADOrganizationalUnit -Name $ouName -Path "OU=$Global:OUPrincipale,$($Global:DomainInfo.DN)" -ErrorAction Stop
                    $Global:OUList += $ouName
                    $Global:ServicesList += $serviceName
                    Write-Log "OU de service créée avec succès : $ouName" "SUCCESS"
                }
                catch {
                    Write-Log "Erreur lors de la création de l'OU '$ouName' : $($_.Exception.Message)" "ERROR"
                }
            }
        }
    } while (![string]::IsNullOrWhiteSpace($serviceName) -and $serviceName -ne "fin")
    
    Write-Host ""
    Write-Host "OU créées :" -ForegroundColor Green
    $Global:OUList | ForEach-Object { Write-Host "  - $_" -ForegroundColor Green }
    
    Read-Host "Appuyez sur Entrée pour continuer"
    return $true
}

# ============================================================================
# ÉTAPE 3 : CRÉATION OPTIMISÉE DES GROUPES
# ============================================================================

function Create-SecurityGroups {
    Show-Banner
    Write-Host "ÉTAPE 3 : CRÉATION DES GROUPES DE SÉCURITÉ" -ForegroundColor Yellow
    Write-Host "===========================================" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host "Création des groupes Globaux (GG_) puis proposition automatique des Domain Local (DL_)" -ForegroundColor Cyan
    Write-Host ""
    
    do {
        # Saisie du type de groupe
        $typeGroupe = Read-Host "Type de groupe (GG_, fin pour terminer)"
        
        if ($typeGroupe -eq "fin" -or [string]::IsNullOrWhiteSpace($typeGroupe)) {
            break
        }
        
        if ($typeGroupe -match '^GG_?$|^1$') {
            # Sélection du service depuis la liste des OU
            Write-Host ""
            Write-Host "Services disponibles :" -ForegroundColor Cyan
            for ($i = 0; $i -lt $Global:ServicesList.Count; $i++) {
                Write-Host "  $($i + 1). $($Global:ServicesList[$i])" -ForegroundColor Cyan
            }
            Write-Host "  $($Global:ServicesList.Count + 1). Autre service" -ForegroundColor Yellow
            
            do {
                $choixService = Read-Host "Choisissez un service (1-$($Global:ServicesList.Count + 1))"
            } while ($choixService -notmatch '^\d+$' -or [int]$choixService -lt 1 -or [int]$choixService -gt ($Global:ServicesList.Count + 1))
            
            if ([int]$choixService -le $Global:ServicesList.Count) {
                $nomService = $Global:ServicesList[[int]$choixService - 1]
            } else {
                $nomService = Read-Host "Entrez le nom du nouveau service"
                if (![string]::IsNullOrWhiteSpace($nomService)) {
                    $Global:ServicesList += $nomService
                }
            }
            
            # Saisie de la fonction
            $nomFonction = Read-Host "Nom de la fonction"
            
            if (![string]::IsNullOrWhiteSpace($nomService) -and ![string]::IsNullOrWhiteSpace($nomFonction)) {
                $groupName = "GG_$($nomService)_$($nomFonction)"
                
                # Confirmation avec O par défaut
                if (Confirm-Action "Confirmer la création du groupe '$groupName'") {
                    $groupInfo = @{
                        Name = $groupName
                        Type = "Global"
                        Service = $nomService
                        Fonction = $nomFonction
                        Path = "OU=OU_$nomService,OU=$Global:OUPrincipale,$($Global:DomainInfo.DN)"
                    }
                    $Global:GroupesList += $groupInfo
                    Write-Log "Groupe global ajouté : $groupName" "SUCCESS"
                    
                    # Proposition automatique de création des DL correspondants
                    Write-Host ""
                    Write-Host "Création des groupes Domain Local pour le groupe '$groupName' :" -ForegroundColor Yellow
                    Write-Host "Quel type d'accès souhaitez-vous ?" -ForegroundColor Cyan
                    Write-Host "1. Un DL_ de chaque type (CT, RW, R)"
                    Write-Host "2. CT (Contrôle total) uniquement"
                    Write-Host "3. RW (ReadWrite) uniquement"
                    Write-Host "4. R (Read) uniquement"
                    Write-Host "5. Aucun (passer)"
                    
                    do {
                        $choixDL = Read-Host "Votre choix (1-5)"
                    } while ($choixDL -notmatch '^[12345]$')
                    
                    $typesAcces = @()
                    switch ($choixDL) {
                        "1" { $typesAcces = @("CT", "RW", "R") }
                        "2" { $typesAcces = @("CT") }
                        "3" { $typesAcces = @("RW") }
                        "4" { $typesAcces = @("R") }
                        "5" { $typesAcces = @() }
                    }
                    
                    foreach ($typeAcces in $typesAcces) {
                        $dlGroupName = "DL_$($nomService)_$($nomFonction)_$($typeAcces)"
                        $description = switch ($typeAcces) {
                            "CT" { "Contrôle total pour le service $nomService" }
                            "RW" { "Lecture/Écriture pour le service $nomService" }
                            "R" { "Lecture seule pour le service $nomService" }
                        }
                        
                        $dlGroupInfo = @{
                            Name = $dlGroupName
                            Type = "DomainLocal"
                            Service = $nomService
                            Fonction = $nomFonction
                            TypeAcces = $typeAcces
                            Description = $description
                            Path = "OU=OU_DomainLocal,OU=$Global:OUPrincipale,$($Global:DomainInfo.DN)"
                            AssociatedGG = $groupName
                        }
                        $Global:GroupesList += $dlGroupInfo
                        Write-Log "Groupe domain local ajouté : $dlGroupName" "SUCCESS"
                    }
                }
            }
        }
        Write-Host ""
    } while ($true)
    
    Write-Host ""
    Write-Host "Résumé des groupes à créer :" -ForegroundColor Green
    $Global:GroupesList | ForEach-Object {
        $color = if ($_.Type -eq "Global") { "Green" } else { "Yellow" }
        Write-Host "  - $($_.Name) ($($_.Type))" -ForegroundColor $color
    }
    
    Read-Host "Appuyez sur Entrée pour continuer"
}

# ============================================================================
# ÉTAPE 4 : CRÉATION EFFECTIVE DES GROUPES (AUTOMATIQUE)
# ============================================================================

function Create-Groups {
    Show-Banner
    Write-Host "ÉTAPE 4 : CRÉATION EFFECTIVE DES GROUPES" -ForegroundColor Yellow
    Write-Host "=========================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Association automatique et création des groupes..." -ForegroundColor Cyan
    Write-Host ""
    
    foreach ($group in $Global:GroupesList) {
        try {
            $groupParams = @{
                Name = $group.Name
                Path = $group.Path
                GroupScope = if ($group.Type -eq "Global") { "Global" } else { "DomainLocal" }
                GroupCategory = "Security"
            }
            
            if ($group.Type -eq "DomainLocal" -and $group.Description) {
                $groupParams.Description = $group.Description
            }
            
            New-ADGroup @groupParams -ErrorAction Stop
            Write-Log "Groupe créé avec succès : $($group.Name)" "SUCCESS"
        }
        catch {
            Write-Log "Erreur lors de la création du groupe '$($group.Name)' : $($_.Exception.Message)" "ERROR"
        }
    }
    
    Write-Host ""
    Write-Host "Tous les groupes ont été créés !" -ForegroundColor Green
    Read-Host "Appuyez sur Entrée pour continuer"
}

# ============================================================================
# ÉTAPE 5 : ASSOCIATION INTELLIGENTE DES GROUPES
# ============================================================================

function Associate-Groups {
    Show-Banner
    Write-Host "ÉTAPE 5 : ASSOCIATION DES GROUPES" -ForegroundColor Yellow
    Write-Host "==================================" -ForegroundColor Yellow
    Write-Host ""
    
    # Récupération des groupes
    $groupesGlobaux = $Global:GroupesList | Where-Object { $_.Type -eq "Global" }
    $groupesDL = $Global:GroupesList | Where-Object { $_.Type -eq "DomainLocal" }
    
    if ($groupesGlobaux.Count -eq 0 -or $groupesDL.Count -eq 0) {
        Write-Log "Aucune association possible - groupes manquants" "WARNING"
        Read-Host "Appuyez sur Entrée pour continuer"
        return
    }
    
    Write-Host "Groupes Globaux disponibles :" -ForegroundColor Green
    for ($i = 0; $i -lt $groupesGlobaux.Count; $i++) {
        Write-Host "  $($i + 1). $($groupesGlobaux[$i].Name)" -ForegroundColor Green
    }
    Write-Host ""
    
    # Association par groupe DL
    foreach ($dlGroup in $groupesDL) {
        Write-Host "Association pour le groupe Domain Local : $($dlGroup.Name)" -ForegroundColor Yellow
        
        # Association automatique si AssociatedGG existe
        if ($dlGroup.AssociatedGG) {
            try {
                Add-ADGroupMember -Identity $dlGroup.Name -Members $dlGroup.AssociatedGG -ErrorAction Stop
                Write-Log "Association automatique : '$($dlGroup.AssociatedGG)' -> '$($dlGroup.Name)'" "SUCCESS"
                continue
            }
            catch {
                Write-Log "Erreur association automatique : $($_.Exception.Message)" "ERROR"
            }
        }
        
        # Association manuelle si automatique échoue
        Write-Host "Choisissez les groupes globaux à associer :" -ForegroundColor Cyan
        Write-Host "(Numéros séparés par des virgules, 0 pour passer)" -ForegroundColor Gray
        
        $choixGG = Read-Host "Votre choix"
        
        if ($choixGG -ne "0" -and ![string]::IsNullOrWhiteSpace($choixGG)) {
            $selections = $choixGG.Split(',') | ForEach-Object { $_.Trim() }
            
            foreach ($selection in $selections) {
                if ($selection -match '^\d+$' -and [int]$selection -gt 0 -and [int]$selection -le $groupesGlobaux.Count) {
                    $selectedGG = $groupesGlobaux[[int]$selection - 1]
                    
                    try {
                        Add-ADGroupMember -Identity $dlGroup.Name -Members $selectedGG.Name -ErrorAction Stop
                        Write-Log "Association réussie : '$($selectedGG.Name)' -> '$($dlGroup.Name)'" "SUCCESS"
                    }
                    catch {
                        Write-Log "Erreur association : '$($selectedGG.Name)' -> '$($dlGroup.Name)' : $($_.Exception.Message)" "ERROR"
                    }
                }
            }
        }
        Write-Host ""
    }
    
    Write-Host "Associations terminées !" -ForegroundColor Green
    Read-Host "Appuyez sur Entrée pour continuer"
}

# ============================================================================
# ÉTAPE 6 : IMPORTATION DES UTILISATEURS
# ============================================================================

function Import-Users {
    Show-Banner
    Write-Host "ÉTAPE 6 : IMPORTATION DES UTILISATEURS" -ForegroundColor Yellow
    Write-Host "=======================================" -ForegroundColor Yellow
    Write-Host ""
    
    # Demande du chemin du fichier CSV
    Write-Host "Format CSV attendu :" -ForegroundColor Cyan
    Write-Host "prenom,nom,fonction,Department_OU,GroupToAdd1,GroupToAdd2" -ForegroundColor Cyan
    Write-Host "Exemple :"
    Write-Host "Jean,Dupont,Administrateur,IT,GG_IT_Admin,DL_IT_Admin_CT" -ForegroundColor Gray
    Write-Host ""
    
    do {
        $csvPath = Read-Host "Entrez le chemin complet du fichier CSV"
        if (!(Test-Path $csvPath)) {
            Write-Host "Fichier introuvable. Vérifiez le chemin." -ForegroundColor Red
        }
    } while (!(Test-Path $csvPath))
    
    try {
        $users = Import-Csv -Path $csvPath -Delimiter "," -ErrorAction Stop
        Write-Log "Fichier CSV importé avec succès : $($users.Count) utilisateurs trouvés" "SUCCESS"
    }
    catch {
        Write-Log "Erreur lors de l'importation du CSV : $($_.Exception.Message)" "ERROR"
        return
    }
    
    # Traitement de chaque utilisateur
    foreach ($user in $users) {
        Write-Host ""
        Write-Host "Traitement de l'utilisateur : $($user.prenom) $($user.nom)" -ForegroundColor Yellow
        
        # Génération de l'email selon le format choisi
        $email = switch ($Global:FormatEmail) {
            { $_.StartsWith("P.nom") } { 
                "$($user.prenom.Substring(0,1)).$($user.nom)@$($Global:DomainInfo.Name)".ToLower()
            }
            { $_.StartsWith("prenom.nom") } { 
                "$($user.prenom).$($user.nom)@$($Global:DomainInfo.Name)".ToLower()
            }
            { $_.StartsWith("nom.prenom") } { 
                "$($user.nom).$($user.prenom)@$($Global:DomainInfo.Name)".ToLower()
            }
        }
        
        # Nettoyage de l'email
        $email = $email -replace '[àáâãäå]', 'a' -replace '[èéêë]', 'e' -replace '[ìíîï]', 'i' -replace '[òóôõö]', 'o' -replace '[ùúûü]', 'u' -replace '[ç]', 'c' -replace '[ñ]', 'n' -replace '[^a-z0-9@.]', ''
        
        # Détermination automatique de l'OU
        $ouDestination = ""
        if (![string]::IsNullOrWhiteSpace($user.Department_OU)) {
            $ouName = "OU_$($user.Department_OU)"
            if ($Global:OUList -contains $ouName) {
                $ouDestination = "OU=$ouName,OU=$Global:OUPrincipale,$($Global:DomainInfo.DN)"
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($ouDestination)) {
            Write-Host "OU non trouvée pour $($user.Department_OU), utilisation de l'OU principale" -ForegroundColor Yellow
            $ouDestination = "OU=$Global:OUPrincipale,$($Global:DomainInfo.DN)"
        }
        
        # Création de l'utilisateur
        try {
            $userParams = @{
                Name = "$($user.prenom) $($user.nom)"
                GivenName = $user.prenom
                Surname = $user.nom
                SamAccountName = "$($user.prenom).$($user.nom)".ToLower()
                UserPrincipalName = $email
                EmailAddress = $email
                Title = $user.fonction
                Path = $ouDestination
                AccountPassword = $Global:MotDePasseGenerique
                ChangePasswordAtLogon = $true
                Enabled = $true
            }
            
            New-ADUser @userParams -ErrorAction Stop
            Write-Log "Utilisateur créé avec succès : $($userParams.Name) | Email : $email" "SUCCESS"
            
            # Ajout aux groupes
            $groupsToAdd = @()
            if (![string]::IsNullOrWhiteSpace($user.GroupToAdd1)) { $groupsToAdd += $user.GroupToAdd1 }
            if (![string]::IsNullOrWhiteSpace($user.GroupToAdd2)) { $groupsToAdd += $user.GroupToAdd2 }
            
            foreach ($groupName in $groupsToAdd) {
                try {
                    Add-ADGroupMember -Identity $groupName -Members $userParams.SamAccountName -ErrorAction Stop
                    Write-Log "Utilisateur '$($userParams.SamAccountName)' ajouté au groupe '$groupName'" "SUCCESS"
                }
                catch {
                    Write-Log "Erreur ajout au groupe '$groupName' : $($_.Exception.Message)" "ERROR"
                }
            }
        }
        catch {
            Write-Log "Erreur création utilisateur '$($user.prenom) $($user.nom)' : $($_.Exception.Message)" "ERROR"
        }
    }
    
    Write-Host ""
    Write-Host "Importation des utilisateurs terminée !" -ForegroundColor Green
    Read-Host "Appuyez sur Entrée pour continuer"
}

# ============================================================================
# FONCTION PRINCIPALE
# ============================================================================

function Start-ADAdministration {
    try {
        Write-Log "=== DÉBUT DU SCRIPT D'ADMINISTRATION AD ===" "INFO"
        
        # Vérification des prérequis
        if (!(Get-Module -Name ActiveDirectory -ListAvailable)) {
            Write-Host "Le module Active Directory n'est pas disponible. Veuillez l'installer." -ForegroundColor Red
            Read-Host "Appuyez sur Entrée pour retourner au menu"
            return
        }
        
        Write-Log "Module Active Directory disponible" "SUCCESS"
        
        # Exécution des étapes optimisées
        Write-Log "Démarrage de l'étape 1 : Initialize-Configuration" "INFO"
        Initialize-Configuration
        
        Write-Log "Démarrage de l'étape 2 : Create-OrganizationalUnits" "INFO"
        $ouResult = Create-OrganizationalUnits
        
        if ($ouResult -eq $false) {
            Write-Log "Arrêt du script : échec de création des OU" "ERROR"
            Write-Host "Le script s'arrête en raison d'un problème avec les OU." -ForegroundColor Red
            Read-Host "Appuyez sur Entrée pour retourner au menu"
            return
        }
        
        Write-Log "Démarrage de l'étape 3 : Create-SecurityGroups" "INFO"
        Create-SecurityGroups
        
        Write-Log "Démarrage de l'étape 4 : Create-Groups" "INFO"
        Create-Groups
        
        Write-Log "Démarrage de l'étape 5 : Associate-Groups" "INFO"
        Associate-Groups
        
        Write-Log "Démarrage de l'étape 6 : Import-Users" "INFO"
        Import-Users
        
        # Résumé final
        Show-Banner
        Write-Host "SCRIPT TERMINÉ AVEC SUCCÈS !" -ForegroundColor Green
        Write-Host "============================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Résumé des actions :" -ForegroundColor Cyan
        Write-Host "- OU principale créée : $Global:OUPrincipale" -ForegroundColor White
        Write-Host "- OU de services créées : $($Global:OUList.Count)" -ForegroundColor White
        Write-Host "- Groupes créés : $($Global:GroupesList.Count)" -ForegroundColor White
        Write-Host "- Fichier de logs : $Global:LogFile" -ForegroundColor White
        Write-Host ""
        Write-Log "=== SCRIPT TERMINÉ AVEC SUCCÈS ===" "SUCCESS"
        
        Read-Host "Appuyez sur Entrée pour retourner au menu"
        
    }
    catch {
        Write-Log "Erreur critique dans le script principal : $($_.Exception.Message)" "ERROR"
        Write-Host "Erreur critique détectée. Consultez les logs pour plus d'informations." -ForegroundColor Red
        Read-Host "Appuyez sur Entrée pour retourner au menu"
    }
}

# ============================================================================
# FONCTIONS BONUS - GESTION AVANCÉE
# ============================================================================

function Get-ADSummary {
    Show-Banner
    Write-Host "RÉSUMÉ DE L'ACTIVE DIRECTORY" -ForegroundColor Yellow
    Write-Host "=============================" -ForegroundColor Yellow
    Write-Host ""
    
    try {
        # Informations du domaine
        $domain = Get-ADDomain
        Write-Host "Domaine : $($domain.DNSRoot)" -ForegroundColor Cyan
        Write-Host "DN : $($domain.DistinguishedName)" -ForegroundColor Cyan
        
        # Comptage des objets
        $users = (Get-ADUser -Filter *).Count
        $computers = (Get-ADComputer -Filter *).Count
        $groups = (Get-ADGroup -Filter *).Count
        $ous = (Get-ADOrganizationalUnit -Filter *).Count
        
        Write-Host ""
        Write-Host "Statistiques :" -ForegroundColor Green
        Write-Host "  Utilisateurs : $users" -ForegroundColor White
        Write-Host "  Ordinateurs : $computers" -ForegroundColor White
        Write-Host "  Groupes : $groups" -ForegroundColor White
        Write-Host "  Unités d'organisation : $ous" -ForegroundColor White
        
        # Affichage des groupes récemment créés
        Write-Host ""
        Write-Host "Groupes commençant par GG_ ou DL_ :" -ForegroundColor Green
        $customGroups = Get-ADGroup -Filter "Name -like 'GG_*' -or Name -like 'DL_*'" | Sort-Object Name
        foreach ($group in $customGroups) {
            $color = if ($group.Name.StartsWith("GG_")) { "Green" } else { "Yellow" }
            Write-Host "  - $($group.Name)" -ForegroundColor $color
        }
        
    }
    catch {
        Write-Host "Erreur lors de la récupération des informations : $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host ""
    Read-Host "Appuyez sur Entrée pour continuer"
}

function Remove-ADTestObjects {
    Show-Banner
    Write-Host "SUPPRESSION DES OBJETS DE TEST" -ForegroundColor Yellow
    Write-Host "===============================" -ForegroundColor Yellow
    Write-Host ""
    
    $ouPrincipaleName = Read-Host "Entrez le nom de l'OU principale à supprimer (ex: OU_MonEntreprise)"
    
    if (Confirm-Action "ATTENTION : Êtes-vous sûr de vouloir supprimer l'OU '$ouPrincipaleName' et tous ses objets enfants ?" "N") {
        try {
            # Recherche de l'OU
            $ou = Get-ADOrganizationalUnit -Filter "Name -eq '$ouPrincipaleName'" -ErrorAction Stop
            
            if ($ou) {
                # Suppression récursive
                Remove-ADOrganizationalUnit -Identity $ou.DistinguishedName -Recursive -Confirm:$false -ErrorAction Stop
                Write-Host "OU '$ouPrincipaleName' et tous ses objets enfants supprimés avec succès." -ForegroundColor Green
            } else {
                Write-Host "OU '$ouPrincipaleName' introuvable." -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "Erreur lors de la suppression : $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    Read-Host "Appuyez sur Entrée pour continuer"
}

function Create-SampleCSV {
    Show-Banner
    Write-Host "CRÉATION D'UN FICHIER CSV D'EXEMPLE" -ForegroundColor Yellow
    Write-Host "====================================" -ForegroundColor Yellow
    Write-Host ""
    
    $csvContent = @"
prenom,nom,fonction,Department_OU,GroupToAdd1,GroupToAdd2
Jean,Dupont,Administrateur Système,IT,GG_IT_Admin,DL_IT_Admin_CT
Marie,Martin,Développeuse Senior,IT,GG_IT_Dev,DL_IT_Dev_RW
Pierre,Durand,Comptable,Finance,GG_Finance_User,DL_Finance_User_R
Sophie,Bernard,Responsable RH,RH,GG_RH_Manager,DL_RH_Manager_CT
Lucas,Petit,Technicien Support,IT,GG_IT_Tech,DL_IT_Tech_RW
Emma,Moreau,Analyste Financier,Finance,GG_Finance_Analyst,DL_Finance_Analyst_RW
Thomas,Leroy,Chef de Projet,IT,GG_IT_Manager,DL_IT_Manager_CT
Julie,Garcia,Assistante RH,RH,GG_RH_User,DL_RH_User_R
"@
    
    $csvPath = Join-Path $PWD.Path "exemple_utilisateurs_v2.csv"
    $csvContent | Out-File -FilePath $csvPath -Encoding UTF8
    Write-Host "Fichier CSV d'exemple créé : $csvPath" -ForegroundColor Green
    Write-Host ""
    Write-Host "Contenu du fichier :" -ForegroundColor Cyan
    Write-Host $csvContent -ForegroundColor Gray
    
    Write-Host ""
    Write-Host "CONSEILS D'UTILISATION :" -ForegroundColor Yellow
    Write-Host "- Department_OU doit correspondre aux services créés (IT, Finance, RH, etc.)" -ForegroundColor Gray
    Write-Host "- GroupToAdd1/2 : utilisez les noms exacts des groupes créés" -ForegroundColor Gray
    Write-Host "- Format email sera généré automatiquement selon votre choix" -ForegroundColor Gray
    
    Read-Host "Appuyez sur Entrée pour continuer"
}

function Test-Configuration {
    Show-Banner
    Write-Host "TEST DE CONFIGURATION ACTIVE DIRECTORY" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host "Vérification des prérequis..." -ForegroundColor Cyan
    
    # Test module AD
    if (Get-Module -Name ActiveDirectory -ListAvailable) {
        Write-Host "✓ Module Active Directory disponible" -ForegroundColor Green
    } else {
        Write-Host "✗ Module Active Directory manquant" -ForegroundColor Red
    }
    
    # Test privilèges admin
    if ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator") {
        Write-Host "✓ Privilèges administrateur détectés" -ForegroundColor Green
    } else {
        Write-Host "✗ Privilèges administrateur requis" -ForegroundColor Red
    }
    
    # Test connectivité domaine
    try {
        $domain = Get-ADDomain -ErrorAction Stop
        Write-Host "✓ Connexion au domaine réussie : $($domain.DNSRoot)" -ForegroundColor Green
    } catch {
        Write-Host "✗ Impossible de se connecter au domaine" -ForegroundColor Red
    }
    
    # Test droits création OU
    try {
        $testOUName = "OU_Test_$((Get-Date).Ticks)"
        New-ADOrganizationalUnit -Name $testOUName -Path (Get-ADDomain).DistinguishedName -ErrorAction Stop
        Remove-ADOrganizationalUnit -Identity "OU=$testOUName,$((Get-ADDomain).DistinguishedName)" -Confirm:$false -ErrorAction Stop
        Write-Host "✓ Droits de création d'OU confirmés" -ForegroundColor Green
    } catch {
        Write-Host "✗ Droits insuffisants pour créer des OU" -ForegroundColor Red
    }
    
    # Test écriture logs
    try {
        $testLogPath = "C:\test_ad_log_$((Get-Date).Ticks).tmp"
        "Test" | Out-File -FilePath $testLogPath -ErrorAction Stop
        Remove-Item -Path $testLogPath -ErrorAction Stop
        Write-Host "✓ Écriture des logs dans C:\ possible" -ForegroundColor Green
    } catch {
        Write-Host "✗ Impossible d'écrire les logs dans C:\" -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Host "Test de configuration terminé." -ForegroundColor Cyan
    Read-Host "Appuyez sur Entrée pour continuer"
}

function Show-Menu {
    do {
        Show-Banner
        Write-Host "MENU PRINCIPAL - ACTIVE DIRECTORY v2.0" -ForegroundColor Yellow
        Write-Host "=======================================" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "1. Exécuter le script complet d'administration AD" -ForegroundColor Cyan
        Write-Host "2. Afficher le résumé de l'Active Directory" -ForegroundColor Cyan
        Write-Host "3. Supprimer des objets de test" -ForegroundColor Cyan
        Write-Host "4. Créer un fichier CSV d'exemple" -ForegroundColor Cyan
        Write-Host "5. Tester la configuration (vérifications rapides)" -ForegroundColor Cyan
        Write-Host "6. Quitter" -ForegroundColor Cyan
        Write-Host ""
     
        
        $choice = Read-Host "Choisissez une option (1-6)"
        
        switch ($choice) {
            "1" { Start-ADAdministration }
            "2" { Get-ADSummary }
            "3" { Remove-ADTestObjects }
            "4" { Create-SampleCSV }
            "5" { Test-Configuration }
            "6" { 
                Write-Host "Au revoir !" -ForegroundColor Green
                return 
            }
            default { 
                Write-Host "Option invalide. Veuillez choisir entre 1 et 6." -ForegroundColor Red
                Start-Sleep -Seconds 2
            }
        }
    } while ($true)
}

# ============================================================================
# VÉRIFICATIONS ET LANCEMENT
# ============================================================================

# Vérification des privilèges administrateur
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ATTENTION : Ce script nécessite des privilèges administrateur." -ForegroundColor Red
    Write-Host "Veuillez relancer PowerShell en tant qu'administrateur." -ForegroundColor Red
    Read-Host "Appuyez sur Entrée pour quitter"
    exit 1
}

# Vérification du module Active Directory
if (!(Get-Module -Name ActiveDirectory -ListAvailable)) {
    Write-Host "Le module Active Directory n'est pas installé." -ForegroundColor Red
    Write-Host "Pour l'installer, exécutez : Install-WindowsFeature -Name RSAT-AD-PowerShell" -ForegroundColor Yellow
    Read-Host "Appuyez sur Entrée pour quitter"
    exit 1
}

# Message de bienvenue
Show-Banner
Write-Host "Bienvenue dans le script d'administration Active Directory v2.0 !" -ForegroundColor Green
Write-Host "Ce script utilise un workflow optimisé et automatisé." -ForegroundColor White
Write-Host ""


# Lancement du menu principal
Show-Menu