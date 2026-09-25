--  Memoire simulee de la machine LLIR : trois regions bornees.
--    image + co-pile   a partir de 16#40_0000#, co-pile au-dessus du code (comme en x86)
--    pile data         croissante, a partir de Base_Pile
--    tas               decroissant depuis Fin_Tas
--  Tout acces hors region leve Faute, avec un message dans Message.
with Interfaces; use Interfaces;
package Memoire is

   Faute : exception;
   procedure Signaler (Texte : String);          -- memorise le texte et leve Faute
   function Message return String;

   Base_Image  : constant := 16#40_0000#;
   Entree      : constant := 16#40_0078#;
   Base_Pile   : constant := 16#7F00_0000_0000#;
   Base_Tas    : constant := 16#7E00_0000_0000#;
   Taille_Enregistrement : constant := 16;

   procedure Charger_Image (Nom : String; Taille_Copile : Natural);
   procedure Creer_Pile (Taille : Natural);
   procedure Creer_Tas (Taille : Natural);

   --  Bornes etablies par le chargement
   function Fin_Code     return Unsigned_64;       -- premier octet apres code et donnees
   function Debut_Copile return Unsigned_64;
   function Fin_Copile   return Unsigned_64;
   function Fin_Pile     return Unsigned_64;
   function Fin_Tas      return Unsigned_64;
   function Vecteur_CE   return Unsigned_64;       -- CEV : cible des CHK en echec (0 : aucune)
   function Table_Instructions  return Unsigned_64;  -- format 3 : adresse de la table (0 : absente)
   function Nombre_Instructions return Natural;      -- format 3 : nombre d'instructions

   --  Acces aux donnees, petit-boutiste ; les lectures rendent la valeur etendue par zeros
   function Lire_8  (A : Unsigned_64) return Unsigned_64;
   function Lire_16 (A : Unsigned_64) return Unsigned_64;
   function Lire_32 (A : Unsigned_64) return Unsigned_64;
   function Lire_64 (A : Unsigned_64) return Unsigned_64;
   procedure Ecrire_8  (A : Unsigned_64; V : Unsigned_64);
   procedure Ecrire_16 (A : Unsigned_64; V : Unsigned_64);
   procedure Ecrire_32 (A : Unsigned_64; V : Unsigned_64);
   procedure Ecrire_64 (A : Unsigned_64; V : Unsigned_64);

   --  Blocs (BLKMOV, BLKCMP) ; un bloc doit tenir dans une seule region
   procedure Copier (Dst, Src, Lg : Unsigned_64);
   function Egaux (A, B, Lg : Unsigned_64) return Boolean;

   --  Acces rapides a la pile data (seule la pile est verifiee)
   function Lire_Pile (A : Unsigned_64) return Unsigned_64;
   procedure Ecrire_Pile (A : Unsigned_64; V : Unsigned_64);

   --  Lecture d'un enregistrement d'instruction
   procedure Lire_Instruction (PC  : Unsigned_64;
                               Op  : out Integer;
                               Lvl : out Integer;
                               Ofs : out Unsigned_64;       -- deja etendu en signe
                               Val : out Unsigned_64);

   pragma Inline (Lire_8, Lire_16, Lire_32, Lire_64);
   pragma Inline (Ecrire_8, Ecrire_16, Ecrire_32, Ecrire_64);
   pragma Inline (Lire_Pile, Ecrire_Pile, Lire_Instruction, Fin_Pile);

end Memoire;
