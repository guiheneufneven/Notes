<#
    ENI - ASR - Administration Windows Server
    TP05 : Les stratégies de groupes (domNG.ad)
    Commandes exécutées sur W11CL1 (poste client)

    METHODE DE TEST
    ---------------
    * Paramètres ORDINATEUR : gpupdate /force puis REDEMARRAGE du poste.
    * Paramètres UTILISATEUR : gpupdate /force puis FERMETURE/REOUVERTURE de
      session. Un simple runas ne suffit pas : le profil chargé n'est pas
      celui de l'utilisateur testé.
    * La redirection de dossiers et les connexions d'imprimantes ne peuvent
      s'appliquer qu'à l'ouverture de session (gpupdate propose de la fermer).
#>


# =====================================================================
# ETAPE 1 - Tous les utilisateurs
# =====================================================================

gpupdate /force
gpresult /r /scope:computer     # GPO-Ordi-Securite doit être appliquée

# Pare-feu : les 3 profils doivent être Enabled=True et Block
Get-NetFirewallProfile -PolicyStore ActiveStore | Format-Table Name,Enabled,DefaultInboundAction
# Equivalent en CMD : netsh advfirewall show allprofiles
#
# Constat du TP : avec la clé "StandardProfile", le profil Privé restait à
# False. Le pare-feu moderne lit "PrivateProfile" ; après correction de la GPO,
# les trois profils passent bien à True.

# Identifiant masqué : fermer la session -> l'écran affiche "Autre utilisateur"
# avec les champs Nom d'utilisateur et Mot de passe vides.


# =====================================================================
# ETAPE 2 - Session de David (DOMNG\dgrenier)
# =====================================================================

# Clic droit sur Ce PC          -> pas de "Propriétés"
# regedit                       -> bloqué par l'administrateur
# Ctrl+Maj+Echap                -> Gestionnaire des tâches désactivé
# mmc > Ajouter un composant    -> Certificats absent / refusé


# =====================================================================
# ETAPE 3 - Session de Christophe (DOMNG\ctalmie), puis de Christelle
# =====================================================================

# Christophe : pas de corbeille sur le bureau, D:\ inaccessible ("Accès refusé")
# Christelle : corbeille présente -> le filtrage de sécurité fonctionne
gpresult /r /scope:user
# Chez David, GPO-User-Interimaires apparaît en "Refusé (Sécurité)".


# =====================================================================
# ETAPE 4 - Verrouillage de compte (PSO)
#
# Les tentatives sont dirigées vers UN SEUL contrôleur : le compteur
# badPwdCount n'étant pas répliqué en temps réel, des échecs répartis entre
# CD1 et CD2 n'atteignent jamais le seuil.
# =====================================================================

net use \\CD1.domNG.ad\SYSVOL /user:DOMNG\itard Faux1
net use \\CD1.domNG.ad\SYSVOL /user:DOMNG\itard Faux2
net use \\CD1.domNG.ad\SYSVOL /user:DOMNG\itard Cs3cr3t!
# -> "Le compte référencé est actuellement verrouillé..."
# Déverrouillage depuis CD1 : Unlock-ADAccount itard


# =====================================================================
# ETAPE 5 - Imprimantes déployées
# =====================================================================

gpupdate /force
Get-Printer | Format-Table Name,Type
# David     -> \\SRV1.domNG.ad\Dell5210
# Christelle-> \\SRV1.domNG.ad\Dell5210-Compta
#
# En cas d'échec de l'extension "Deployed Printer Connections" : c'est le
# blocage Point and Print (PrintNightmare). Corrigé par la valeur
# RestrictDriverInstallationToAdministrators = 0 dans GPO-Ordi-Securite,
# suivie d'un redémarrage du poste.


# =====================================================================
# ETAPE 7 - Droits réseau du support technique (session d'Ivan)
# =====================================================================

net localgroup "Opérateurs de configuration réseau"   # DOMNG\G-Support technique
whoami /groups | findstr /i "configuration"
# Modification d'IP : passer par Paramètres > Réseau et Internet > Ethernet.
# netsh et ncpa.cpl exigent une élévation UAC : dans une console non élevée, le
# privilège apparaît comme "utilisé pour les refus uniquement", ce qui est le
# comportement normal du filtrage de jeton UAC, pas une absence de droit.


# =====================================================================
# ETAPE 8 - Redirection de Mes Documents
# =====================================================================

# Session de David : gpupdate /force puis fermeture de session
# Propriétés de Documents > Général > Emplacement :
#   \\SRV1\Documents$\dgrenier
# Session de Christophe : Emplacement = C:\Users\ctalmie (exclusion effective)


# =====================================================================
# ETAPE 9 - Bureau à distance (session d'Ivan)
# =====================================================================

Test-NetConnection SRV1 -Port 3389
mstsc /v:SRV1
# Connexion acceptée pour DOMNG\itard (membre de G-Support technique),
# refusée pour un utilisateur hors du groupe.
