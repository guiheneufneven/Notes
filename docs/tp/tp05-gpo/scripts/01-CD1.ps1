<#
    ENI - ASR - Administration Windows Server
    TP05 : Les stratégies de groupes (domNG.ad)
    Commandes exécutées sur CD1 (PowerShell administrateur)

    RAPPELS UTILES POUR RELIRE CE SCRIPT
    ------------------------------------
    * Une GPO contient deux moitiés indépendantes :
        - Configuration ORDINATEUR : lue au démarrage de la machine, elle ne
          s'applique qu'aux OU contenant des objets ordinateur.
        - Configuration UTILISATEUR : lue à l'ouverture de session, elle ne
          s'applique qu'aux OU contenant des objets utilisateur.
      Lier une GPO "utilisateur" sur une OU de machines (ou l'inverse) ne
      produit strictement aucun effet : c'est l'erreur classique.
    * Ordre d'application : Local > Site > Domaine > OU parente > OU enfant
      (LSDOU). La dernière appliquée gagne, sauf blocage ou "Appliqué" (Enforced).
    * Set-GPRegistryValue écrit un paramètre de modèle d'administration
      directement dans registry.pol : c'est exactement ce que fait la console,
      en plus rapide et reproductible.
#>

Import-Module GroupPolicy
Import-Module ActiveDirectory

$Dom   = "DC=domNG,DC=ad"
$OUU   = "OU=Utilisateurs,OU=DOMNG,$Dom"
$OUS   = "OU=Stations de travail,OU=DOMNG,$Dom"
$OUSRV = "OU=Serveurs,OU=DOMNG,$Dom"


# =====================================================================
# 1. TOUS LES UTILISATEURS : identifiant masqué + pare-feu
#    -> paramètres ORDINATEUR, donc liaison sur les OU machines
# =====================================================================

New-GPO -Name "GPO-Ordi-Securite" -Comment "Dernier utilisateur masqué + pare-feu entrant"
New-GPLink -Name "GPO-Ordi-Securite" -Target $OUS
New-GPLink -Name "GPO-Ordi-Securite" -Target $OUSRV

# Ne pas afficher le dernier nom d'utilisateur sur l'écran de connexion.
# Intérêt : un identifiant de compte valide n'est plus divulgué à quiconque
# passe devant le poste ; l'utilisateur doit saisir login ET mot de passe.
# GUI : Config ordinateur > Stratégies > Paramètres Windows > Paramètres de
#       sécurité > Stratégies locales > Options de sécurité > "Ouverture de
#       session interactive : ne pas afficher le dernier nom d'utilisateur"
Set-GPRegistryValue -Name "GPO-Ordi-Securite" `
    -Key "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -ValueName "DontDisplayLastUserName" -Type DWord -Value 1

# Pare-feu : activé et blocage des connexions entrantes sur les 3 profils.
# ATTENTION AU NOM DES CLES (piège rencontré pendant le TP) :
#   DomainProfile   = profil Domaine
#   PrivateProfile  = profil Privé      <-- clé lue par le pare-feu moderne
#   PublicProfile   = profil Public
#   StandardProfile = ancien nom hérité de Windows XP, ECRIT MAIS IGNORE par
#                     le pare-feu Windows Defender actuel.
# EnableFirewall = 1        -> pare-feu actif, non désactivable localement
# DefaultInboundAction = 1  -> tout le trafic entrant non autorisé est bloqué
foreach ($Profil in "DomainProfile","PrivateProfile","PublicProfile") {
    Set-GPRegistryValue -Name "GPO-Ordi-Securite" `
        -Key "HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\$Profil" `
        -ValueName "EnableFirewall" -Type DWord -Value 1
    Set-GPRegistryValue -Name "GPO-Ordi-Securite" `
        -Key "HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\$Profil" `
        -ValueName "DefaultInboundAction" -Type DWord -Value 1
}

# Animation de bienvenue à la première connexion (demandée pour les
# intérimaires) : c'est un paramètre ORDINATEUR, impossible à filtrer sur un
# groupe d'utilisateurs sans activer le traitement par bouclage (loopback).
# Choix retenu : désactivation pour toutes les stations.
Set-GPRegistryValue -Name "GPO-Ordi-Securite" `
    -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
    -ValueName "EnableFirstLogonAnimation" -Type DWord -Value 0

# Point and Print : depuis les correctifs PrintNightmare, un utilisateur non
# administrateur ne peut plus installer de pilote d'imprimante, ce qui fait
# échouer les connexions d'imprimantes déployées par GPO (étape 5).
# Valeur 0 = installation de pilote autorisée pour les utilisateurs standard.
Set-GPRegistryValue -Name "GPO-Ordi-Securite" `
    -Key "HKLM\Software\Policies\Microsoft\Windows NT\Printers\PointAndPrint" `
    -ValueName "RestrictDriverInstallationToAdministrators" -Type DWord -Value 0


# =====================================================================
# 2. DIRECTION : restrictions de l'environnement de travail
#    -> paramètres UTILISATEUR, liaison sur l'OU Utilisateurs\DIRECTION
# =====================================================================

New-GPO -Name "GPO-User-Direction" -Comment "Restrictions environnement Direction"
New-GPLink -Name "GPO-User-Direction" -Target "OU=DIRECTION,$OUU"

# Masquer "Propriétés" dans le menu contextuel du Poste de travail
# GUI : Config utilisateur > Modèles d'administration > Bureau
Set-GPRegistryValue -Name "GPO-User-Direction" `
    -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
    -ValueName "NoPropertiesMyComputer" -Type DWord -Value 1

# Interdire regedit et les outils d'édition du registre
# GUI : Config utilisateur > Modèles d'administration > Système
Set-GPRegistryValue -Name "GPO-User-Direction" `
    -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
    -ValueName "DisableRegistryTools" -Type DWord -Value 1

# Interdire le Gestionnaire des tâches
# GUI : Config utilisateur > Modèles d'administration > Système >
#       Options de Ctrl+Alt+Suppr
Set-GPRegistryValue -Name "GPO-User-Direction" `
    -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
    -ValueName "DisableTaskMgr" -Type DWord -Value 1

# Console Certificats interdite dans une MMC : fait EN GRAPHIQUE, le paramètre
# reposant sur le GUID du composant enfichable.
# GUI : Config utilisateur > Modèles d'administration > Composants Windows >
#       Console de gestion Microsoft > Composants logiciels enfichables
#       restreints/autorisés > Certificats = DESACTIVE
#       (logique inversée : Désactivé = composant interdit)


# =====================================================================
# 3. G-INTERIMAIRES : restrictions ciblées par filtrage de sécurité
#    La GPO est liée à l'OU Utilisateurs (les intérimaires sont répartis
#    dans plusieurs OU de service) puis filtrée sur le groupe.
# =====================================================================

New-GPO -Name "GPO-User-Interimaires" -Comment "Restrictions intérimaires"
New-GPLink -Name "GPO-User-Interimaires" -Target $OUU

# Filtrage : seul G-Intérimaires applique la GPO...
Set-GPPermission -Name "GPO-User-Interimaires" -TargetName "G-Intérimaires" `
    -TargetType Group -PermissionLevel GpoApply
# ...mais les Utilisateurs authentifiés doivent conserver la LECTURE.
# Depuis le correctif MS16-072, le traitement des GPO utilisateur se fait dans
# le contexte de l'ORDINATEUR : sans droit de lecture pour les machines, la
# GPO n'est même plus lue et ne s'applique donc à personne.
Set-GPPermission -Name "GPO-User-Interimaires" -TargetName "Utilisateurs authentifiés" `
    -TargetType Group -PermissionLevel GpoRead -Replace

# Masquer la corbeille du bureau (GUID de la corbeille dans NonEnum)
# GUI : Config utilisateur > Modèles d'administration > Bureau
Set-GPRegistryValue -Name "GPO-User-Interimaires" `
    -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\NonEnum" `
    -ValueName "{645FF040-5081-101B-9F08-00AA002F954E}" -Type DWord -Value 1

# Refuser l'accès aux CD/DVD (GUID de la classe de périphériques optiques)
# GUI : Config utilisateur > Modèles d'administration > Système >
#       Accès au stockage amovible
$CD = "HKCU\Software\Policies\Microsoft\Windows\RemovableStorageDevices\{53f56308-b6bf-11d0-94f2-00a0c91efb8b}"
Set-GPRegistryValue -Name "GPO-User-Interimaires" -Key $CD -ValueName "Deny_Read"  -Type DWord -Value 1
Set-GPRegistryValue -Name "GPO-User-Interimaires" -Key $CD -ValueName "Deny_Write" -Type DWord -Value 1

# Vérification du filtrage
Get-GPPermission -Name "GPO-User-Interimaires" -All |
    Format-Table @{n="Compte";e={$_.Trustee.Name}},Permission


# =====================================================================
# 4. STRATEGIE DE MOTS DE PASSE
#
#    Un domaine AD n'accepte qu'UNE SEULE stratégie de comptes, portée par la
#    Default Domain Policy : c'est une limitation d'Active Directory, pas de
#    la console. Pour durcir les règles d'un groupe précis, il faut une
#    stratégie affinée (PSO, Password Settings Object), stockée dans
#    CN=Password Settings Container et appliquée à des utilisateurs ou des
#    groupes. En cas de PSO multiples, la plus petite "Precedence" gagne.
# =====================================================================

Set-ADDefaultDomainPasswordPolicy -Identity "domNG.ad" `
    -MinPasswordLength 10 `
    -ComplexityEnabled $true `
    -PasswordHistoryCount 20 `
    -MaxPasswordAge "30.00:00:00"

# PSO du service informatique : verrouillage au bout de 2 échecs, déverrouillage
# par un administrateur uniquement.
#
# PIEGE RENCONTRE : AD impose LockoutDuration >= LockoutObservationWindow.
#   - LockoutObservationWindow à 0 -> le compteur d'échecs est remis à zéro
#     immédiatement, le seuil n'est JAMAIS atteint (le compte ne se verrouille
#     jamais, symptôme constaté pendant le TP).
#   - LockoutDuration à 0 = "jusqu'à déverrouillage par un administrateur".
# La combinaison (durée 0 / fenêtre 30 min) est refusée par PowerShell
# (erreur 8423) mais acceptée par le Centre d'administration AD, qui écrit les
# deux attributs en une seule opération. La PSO a donc été créée en console :
#   Centre d'administration AD > domNG (local) > System >
#   Password Settings Container > Nouveau > Password Settings
#     Longueur minimale             : 10
#     Historique                    : 20
#     Exigences de complexité       : coché
#     Age maximal                   : 30 jours
#     Tentatives échouées           : 2
#     Réinitialiser le compteur après : 30 minutes
#     [x] Jusqu'à ce qu'un administrateur déverrouille manuellement
#     S'applique directement à      : G-Informatique
#
# Equivalent PowerShell en deux temps (création large puis ajustement) :
New-ADFineGrainedPasswordPolicy -Name "PSO-Informatique" -Precedence 10 `
    -MinPasswordLength 10 -ComplexityEnabled $true `
    -PasswordHistoryCount 20 -MaxPasswordAge "30.00:00:00" `
    -LockoutThreshold 2 -LockoutDuration "00:30:00" -LockoutObservationWindow "00:30:00"
Add-ADFineGrainedPasswordPolicySubject "PSO-Informatique" -Subjects "G-Informatique"

# Vérifications
Get-ADDefaultDomainPasswordPolicy
Get-ADFineGrainedPasswordPolicy -Filter * |
    Format-Table Name,Precedence,LockoutThreshold,LockoutDuration,LockoutObservationWindow
Get-ADUserResultantPasswordPolicy -Identity "ivedere"   # doit renvoyer PSO-Informatique

# Suivi du verrouillage (après le test côté client)
# NOTE : le compteur badPwdCount n'est PAS répliqué immédiatement entre DC.
# Chaque contrôleur tient le sien, d'où des tentatives qui semblent "perdues"
# si le client s'authentifie tantôt sur CD1, tantôt sur CD2. Le verrouillage,
# lui, est répliqué en urgence.
Get-ADUser itard -Properties badPwdCount,LockedOut -Server CD1 | Format-Table Name,badPwdCount,LockedOut
Get-ADUser itard -Properties badPwdCount,LockedOut -Server CD2 | Format-Table Name,badPwdCount,LockedOut
Search-ADAccount -LockedOut | Format-Table Name,SamAccountName
Unlock-ADAccount itard


# =====================================================================
# 5. DEPLOIEMENT DES IMPRIMANTES PAR GPO
#    Une GPO par service : le déploiement "par utilisateur" suit la personne
#    quel que soit le poste sur lequel elle ouvre une session.
# =====================================================================

New-GPO -Name "GPO-Imprimante-Direction"    -Comment "Dell5210 pour la Direction"
New-GPO -Name "GPO-Imprimante-Informatique" -Comment "Dell5210 pour l'Informatique"
New-GPO -Name "GPO-Imprimante-Comptabilite" -Comment "Dell5210-Compta pour la Comptabilité"

New-GPLink -Name "GPO-Imprimante-Direction"    -Target "OU=DIRECTION,$OUU"
New-GPLink -Name "GPO-Imprimante-Informatique" -Target "OU=INFORMATIQUE,$OUU"
New-GPLink -Name "GPO-Imprimante-Comptabilite" -Target "OU=Comptabilité,$OUU"

# L'association imprimante <-> GPO se fait dans la console Gestion de
# l'impression. Celle-ci n'étant pas installée sur CD1 :
Install-WindowsFeature RSAT-Print-Services
#   printmanagement.msc > clic droit sur Serveurs d'impression >
#   Ajouter/Supprimer des serveurs > SRV1
#   puis clic droit sur l'imprimante > Déployer avec une stratégie de groupe >
#   Parcourir (onglet "Tous" si l'arborescence reste vide) > cocher
#   "Les utilisateurs auxquels cette GPO s'applique (par utilisateur)" > Ajouter
#
#   Dell5210        -> GPO-Imprimante-Direction + GPO-Imprimante-Informatique
#   Dell5210-Compta -> GPO-Imprimante-Comptabilite


# =====================================================================
# 6. MAGASIN CENTRAL DES MODELES D'ADMINISTRATION
#    Sans magasin central, chaque console GPMC lit les ADMX locaux de SA
#    machine : les paramètres visibles varient donc selon le poste utilisé.
#    Copiés dans SYSVOL (répliqué sur tous les DC), les modèles deviennent
#    communs à tout le domaine, y compris depuis W11CL1 via les RSAT.
#    C'est aussi ainsi qu'on ajoute des modèles tiers (Chrome, Firefox, Office).
# =====================================================================

$Central = "\\domNG.ad\SYSVOL\domNG.ad\Policies\PolicyDefinitions"
New-Item -Path $Central -ItemType Directory -Force
Copy-Item "C:\Windows\PolicyDefinitions\*.admx" $Central -Force
New-Item -Path "$Central\fr-FR" -ItemType Directory -Force
Copy-Item "C:\Windows\PolicyDefinitions\fr-FR\*.adml" "$Central\fr-FR" -Force

(Get-ChildItem $Central -Filter *.admx).Count          # 213
(Get-ChildItem "$Central\fr-FR" -Filter *.adml).Count  # 214
# Contrôle : dans l'éditeur de GPO, le noeud s'intitule désormais "Modèles
# d'administration : définitions de stratégies (fichiers ADMX) récupérées à
# partir du magasin central."


# =====================================================================
# 7. G-SUPPORT TECHNIQUE : CONFIGURATION RESEAU DES STATIONS
#    Le groupe local intégré "Opérateurs de configuration réseau" (SID
#    S-1-5-32-556) donne le droit de modifier IP, DNS et cartes réseau sans
#    être administrateur du poste.
# =====================================================================

New-GPO -Name "GPO-Ordi-ReseauSupport" -Comment "G-Support technique dans Opérateurs de configuration réseau"
New-GPLink -Name "GPO-Ordi-ReseauSupport" -Target $OUS

# Paramètre posé EN GRAPHIQUE (préférence, donc additive) :
#   Config ordinateur > Préférences > Paramètres du Panneau de configuration >
#   Utilisateurs et groupes locaux > Nouveau > Groupe local
#     Action      : Mettre à jour
#     Nom du groupe : Opérateurs de configuration réseau (intégré)
#                     -> choisi dans la liste, donc identifié par son SID :
#                        fonctionne quelle que soit la langue du poste
#     Membres     : DOMNG\G-Support technique (ADD)
#     Ne PAS cocher "Supprimer les utilisateurs / les groupes", qui viderait
#     le groupe existant.
#
# Alternative "Groupes restreints" (Paramètres de sécurité) : à éviter ici car
# elle REMPLACE la liste des membres au lieu de l'enrichir.


# =====================================================================
# 8. REDIRECTION DE "MES DOCUMENTS" VERS SRV1 (partie annuaire)
#    Les profils sont locaux : une panne de disque fait perdre les documents.
#    La redirection place le dossier sur un partage de SRV1, sauvegardable.
# =====================================================================

# Groupe de ressource (méthode AGDLP) qui recevra le droit NTFS sur SRV1
New-ADGroup -Name "DL_Documents_Depot" -GroupScope DomainLocal -GroupCategory Security `
            -Path "OU=Ressources,OU=Groupes,OU=DOMNG,$Dom"
Add-ADGroupMember "DL_Documents_Depot" -Members (Get-ADGroup "$((Get-ADDomain).DomainSID)-513")

New-GPO -Name "GPO-User-RedirectionDocs" -Comment "Mes Documents redirigés vers SRV1"
New-GPLink -Name "GPO-User-RedirectionDocs" -Target $OUU

# Exclusion des intérimaires : un REFUS explicite est nécessaire, car
# G-Intérimaires est inclus dans "Utilisateurs authentifiés" qui applique la GPO.
# GUI : GPMC > GPO-User-RedirectionDocs > onglet Délégation > Avancé >
#       Ajouter G-Intérimaires > cocher REFUSER uniquement sur
#       "Appliquer la stratégie de groupe" (surtout pas sur Lire)
Set-GPPermission -Name "GPO-User-RedirectionDocs" -TargetName "G-Intérimaires" `
    -TargetType Group -PermissionLevel None -Replace

# Paramètre posé EN GRAPHIQUE :
#   Config utilisateur > Stratégies > Paramètres Windows > Redirection de
#   dossiers > Documents > Propriétés
#     Onglet Cible :
#       Paramètre : De base - Rediriger les dossiers de tout le monde vers le
#                   même emplacement
#       Emplacement : Créer un dossier pour chaque utilisateur sous le chemin
#                     d'accès racine
#       Chemin racine : \\SRV1\Documents$
#       (l'aperçu affiche \\SRV1\Documents$\<utilisateur>\Documents)
#     Onglet Paramètres :
#       [x] Accorder à l'utilisateur des droits exclusifs sur Documents
#       [x] Déplacer le contenu de Documents vers le nouvel emplacement
#
# NOTE : la redirection ne peut s'appliquer QU'A L'OUVERTURE DE SESSION.
# Un gpupdate /force propose donc de fermer la session : c'est normal.


# =====================================================================
# 9. BUREAU A DISTANCE AUTOMATIQUE SUR LES SERVEURS
# =====================================================================

New-GPO -Name "GPO-Ordi-RDP-Serveurs" -Comment "RDP + NLA pour G-Support technique"
New-GPLink -Name "GPO-Ordi-RDP-Serveurs" -Target $OUSRV

# Autoriser les connexions Bureau à distance
# GUI : Config ordinateur > Modèles d'administration > Composants Windows >
#       Services Bureau à distance > Hôte de session Bureau à distance >
#       Connexions
Set-GPRegistryValue -Name "GPO-Ordi-RDP-Serveurs" `
    -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" `
    -ValueName "fDenyTSConnections" -Type DWord -Value 0

# Exiger l'authentification NLA : l'utilisateur s'authentifie AVANT l'ouverture
# de la session graphique, ce qui protège le serveur des attaques sur l'écran
# de connexion et réduit la consommation de ressources.
# GUI : ... Hôte de session Bureau à distance > Sécurité
Set-GPRegistryValue -Name "GPO-Ordi-RDP-Serveurs" `
    -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" `
    -ValueName "UserAuthentication" -Type DWord -Value 1

# Deux réglages posés EN GRAPHIQUE dans la même GPO :
# 1) Ouverture du port 3389, indispensable puisque la GPO de l'étape 1 bloque
#    tout le trafic entrant :
#    Config ordinateur > Modèles d'administration > Réseau > Connexions réseau >
#    Pare-feu Windows Defender > Profil du domaine >
#    "Autoriser les exceptions du Bureau à distance en entrée" = Activé
#    Adresses autorisées : *
# 2) Membres autorisés :
#    Config ordinateur > Préférences > Paramètres du Panneau de configuration >
#    Utilisateurs et groupes locaux > Nouveau > Groupe local
#      Action : Mettre à jour
#      Groupe : Utilisateurs du Bureau à distance (intégré)
#      Membre : DOMNG\G-Support technique (ADD)
#
# NOUVEAUX SERVEURS : une machine qui rejoint le domaine arrive dans
# CN=Computers, un conteneur sur lequel aucune GPO ne peut être liée. Pour que
# l'activation soit réellement automatique :
#   redircmp "OU=Serveurs,OU=DOMNG,DC=domNG,DC=ad"


# =====================================================================
# 10. VERIFICATIONS GENERALES
# =====================================================================

Get-GPO -All | Format-Table DisplayName,GpoStatus,ModificationTime
Get-GPInheritance -Target $OUU | Select-Object -ExpandProperty GpoLinks |
    Format-Table DisplayName,Enabled,Order
Get-GPOReport -All -ReportType Html -Path "C:\GPO_domNG.html"
