--  Profilage dynamique de l'execution LLIR.
--  Pour chaque instruction executee : comptage par code, et taille qu'elle
--  occuperait dans les deux flux de LLIR_hardware_support (1 octet d'opcode,
--  complement dans le flux des arguments).
with Interfaces; use Interfaces;
package Profil is

   type Compteur is range 0 .. 2**62;

   procedure Instruction (Op : Integer; Lvl : Integer;
                          Ofs, Val : Unsigned_64; PC : Unsigned_64;
                          Longueur : Unsigned_64);   -- octets de l'instruction (TX : 16)
   procedure Acces (Lvl : Integer; Courant : Integer);   -- familles B et C
   procedure Service (N : Integer);                      -- TRAP n
   procedure Booleen_Non_Normalise (PC, V : Unsigned_64);  -- BT/BF sur valeur hors {0,1}
   procedure Decalage_Hors_Mot;                          -- compte de decalage >= 64
   procedure Champ (Lsb, Largeur : Unsigned_64);         -- UBFX.. : classe les cas limites

   --  Debordement signe sur 64 bits d'une operation entiere (mesure pour une
   --  semantique deroutante de ces operations, faute 129) ; A, B : operandes
   type Operation_Entiere is (D_ADD, D_SUB, D_MUL, D_NEG, D_ABS, D_INC, D_DEC);
   procedure Debordement (Op : Operation_Entiere; PC, A, B : Unsigned_64);

   --  Maxima tenus par la machine
   Max_Pile_Octets   : Unsigned_64 := 0;
   Max_Retours       : Natural := 0;
   Max_Copile_Octets : Unsigned_64 := 0;
   Max_Tas_Octets    : Unsigned_64 := 0;
   Max_Niveau        : Integer := 0;

   function Total return Compteur;

   --  Image HX : mesures exactes fournies par la machine avant le rapport
   Image_HX          : Boolean := False;
   Instructions_LLIR : Compteur := 0;         -- instructions LLIR representees
   Octets_HX         : Compteur := 0;         -- octets de code HX lus

   procedure Rapport (Nom_Fichier : String);   -- "" : sur la sortie d'erreur

end Profil;
