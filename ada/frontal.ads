--  Disposition du code selon LLIR_hardware_support et modele de chargement.
--  Au chargement, chaque instruction de l'image TX (table emise par codi_TX) recoit
--  sa taille exacte selon les formats de la specification, dans deux organisations :
--    flux unique  : opcode puis complement, a la suite ; une branche porte un seul
--                   deplacement (8, 16, 24 ou 32 bits, soit 1 a 4 octets) ; CALL D24
--    double flux  : opcodes dans un flux, complements dans l'autre ; une branche porte
--                   delta_OP et delta_ARG (BR16 a BR64, 2 a 8 octets) ; CALL porte
--                   deux deplacements D24 (6 octets)
--  Les tailles de branches sont fixees par relaxation. Les donnees en ligne sont
--  exclues du code (elles iraient dans une section de donnees).
--  Chaque instruction executee alimente ensuite plusieurs modeles de chargement :
--  un bloc aligne de F octets par cycle et par flux, au plus L instructions
--  decodees par cycle, arret apres un transfert pris (prediction supposee parfaite).
with Interfaces; use Interfaces;
with Text_IO;
package Frontal is

   Actif : Boolean := False;

   procedure Preparer;                                  -- apres le chargement de l'image
   procedure Instruction (PC, Suivant : Unsigned_64);   -- chaque instruction executee
   procedure Rapport (Sortie : in out Text_IO.File_Type; Vers_Fichier : Boolean);

end Frontal;
