--  Etude de limites du parallelisme d'instructions (ILP) sur la trace executee.
--  Chaque instruction recoit une date de debut au plus tot, selon ses dependances,
--  la fenetre et la largeur de la machine, pour plusieurs modeles calcules en une
--  seule execution. Prediction de branchement realiste partout sauf M0 (gshare,
--  pile des retours, derniere cible des appels indirects ; apres une erreur, rien
--  ne demarre avant la resolution + Penalite cycles).
--    M0   machine a pile sequentielle : somme des latences
--    M3   oracle memoire : seules les vraies dependances (reference)
--    M6   pile renommee ; file de chargements/rangements ou les adresses (lvl, disp)
--         sont connues au decodage : un chargement attend seulement que les
--         rangements indirects plus anciens aient calcule leur adresse
--    M6re M6r limite aux locales non exposees. Une variable locale est identifiee
--         par (adresse du LINK de sa procedure, deplacement dans le frame) ; elle
--         devient exposee des qu'un acces par pointeur la touche, pour toutes les
--         activations suivantes : c'est ce que le compilateur sait statiquement.
--         Une locale renommee est lue sans latence de chargement et sans attente.
--         Variante a tranche de pile de K mots : seules les locales situees dans
--         les K mots sous le sommet (DSP) sont en registres, les autres en memoire.
--    M6t  tranche de pile adressee par intervalle : toute locale lue a moins de K mots
--         sous le sommet est un registre renomme, exposee ou non ; comme dans M6,
--         toute lecture directe attend l'adresse des rangements indirects plus anciens
--         (un acces par pointeur qui vise la tranche y est redirige : cache de pile).
--         Aucune information d'exposition.
--  La machine complete (M6re, tranche de 128 mots) est aussi calculee a largeur
--  finie : au plus L instructions lancees et retirees par cycle, dans l'ordre
--  (unites d'execution illimitees).
with Interfaces; use Interfaces;
with Text_IO;
package Limites is

   type Classe_Acces is (Pile, Directe, Indirecte);
   type Sens_Acces is (Lecture, Ecriture);
   type Registre_Machine is (Reg_CSP, Reg_HP);

   Actif : Boolean := False;

   procedure Regions (Pile, Fin_Pile, Copile, Fin_Copile, Tas, Fin_Tas : Unsigned_64);
   procedure Debut (DSP : Unsigned_64);              -- nouvelle instruction
   procedure Acces (A, Taille : Unsigned_64; Sens : Sens_Acces; Classe : Classe_Acces);
   procedure Registre (R : Registre_Machine; Sens : Sens_Acces);
   procedure Barriere;                               -- instruction serialisante
   procedure Adresse_Suivante;                       -- le prochain acces lu fournit une adresse
   procedure Marquer_Local (Local : Boolean; DSP : Unsigned_64);   -- acces directs suivants :
                                                     -- niveau courant ? (DSP : sommet)
   procedure Lien (FP, PC_Link : Unsigned_64; Lvl : Integer; Locales : Unsigned_64);
                                                     -- nouveau frame (apres LINK) ; octets de locales
   procedure Delien;                                 -- frame libere (UNLINK, UNLINKR)
   procedure Retablir (DSP : Unsigned_64);           -- apres EXC_RAISE : frames au-dessus de DSP
   procedure Fin (Op : Integer; PC, Suivant, Sequentiel : Unsigned_64);   -- dates de l'instruction
   --  Decalage applique au PC pour indexer les predicteurs : 4 en TX (16 octets par
   --  instruction), 0 en HX (longueur variable, l'adresse d'octet est deja unique)
   Decalage_PC : Natural := 4;
                                                     -- Suivant : PC effectivement suivi

   procedure Rapport (Sortie : in out Text_IO.File_Type; Vers_Fichier : Boolean);

end Limites;
