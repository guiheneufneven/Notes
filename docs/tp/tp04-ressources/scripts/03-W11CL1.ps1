<#
    ENI - ASR - Administration Windows Server
    TP04 : Gestion de ressources (domNG.ad)
    Commandes exécutées sur W11CL1 (poste client, RSAT installés)
#>


# =====================================================================
# 1. TESTS DES ACCES AUX PARTAGES
#    Ouvrir une invite de commandes sous l'identité à tester :
#      runas /user:DOMNG\<identifiant> cmd      (mot de passe : <MotDePasse>)
#    Entre deux comptes, couper les sessions SMB déjà ouvertes :
#      net use * /delete /y
#    (Windows n'autorise qu'une seule identité à la fois vers un même serveur.)
#
#    Rappel : après tout ajout dans un groupe, fermer et rouvrir la session,
#    les appartenances étant lues à l'ouverture de session.
# =====================================================================

# Test d'accès     : dir \\SRV1\Documentation
# Test de lecture  : type \\SRV1\Documentation\lisezmoi.txt
# Test d'écriture  : echo test > \\SRV1\Documentation\test.txt   puis   del ...

# --- Résultats obtenus ------------------------------------------------
# DOCUMENTATION
#   Christophe  Accès          ECHEC   (refus explicite des intérimaires)
#   Christelle  Accès          OK
#   David       Lecture        OK
#   Isabelle    Lecture        OK
#   Christelle  Modification   ECHEC   (lecture seule)
#   Isabelle    Modification   OK      (contrôle total via G-Informatique)
#
# COMPTABILITE
#   Christelle  Accès          OK
#   David       Accès          ECHEC   (autre service, aucune ACE)
#   Christelle  Modification   OK
#   Isabelle    Contrôle total OK
# ----------------------------------------------------------------------


# =====================================================================
# 2. TESTS DE LA DELEGATION AD
#    Ouvrir la console Utilisateurs et ordinateurs AD sous une autre identité :
# =====================================================================

# David (service Comptabilité)
#   runas /user:DOMNG\dgrenier "mmc C:\Windows\System32\dsa.msc"
#   OU Comptabilité : réinitialisation du mot de passe de Christophe   -> OK
#                     création / suppression d'un compte de test       -> OK
#   OU INFORMATIQUE : réinitialisation du mot de passe d'Isabelle      -> Accès refusé

# Ivan (support technique)
#   runas /user:DOMNG\itard "mmc C:\Windows\System32\dsa.msc"
#   OU DIRECTION et Comptabilité : création de compte, réinit. mdp     -> OK
#   OU INFORMATIQUE              : réinit. du mot de passe d'Isabelle  -> Accès refusé


# =====================================================================
# 3. DEPLOIEMENT DE L'IMPRIMANTE
# =====================================================================

Add-Printer -ConnectionName "\\SRV1\Dell5210"

Get-Printer | Format-Table Name,ComputerName,Type,DriverName,PortName

# Recherche via l'annuaire (imprimante publiée dans l'AD) :
#   Paramètres > Imprimantes et scanners > Ajouter une imprimante
#   > "L'imprimante que je veux n'est pas répertoriée"
#   > "Rechercher une imprimante dans l'annuaire"
#   -> Dell5210 et Dell5210-Compta sur SRV1.domNG.ad
