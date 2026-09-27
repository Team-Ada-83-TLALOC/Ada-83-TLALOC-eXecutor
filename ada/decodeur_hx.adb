with Memoire; use Memoire;
with Mots; use Mots;
with HX_Codes; use HX_Codes;
with TX_Codes; use TX_Codes;
with Unchecked_Conversion;
package body Decodeur_HX is

   --  Instruction decodee, 16 octets comme un enregistrement TX
   type Decode is record
      Op    : Unsigned_8;       -- code TX
      Lvl   : Integer_8;
      Lg    : Unsigned_8;       -- 0 : pas encore decodee
      Poids : Unsigned_8;       -- Pas_Une_Instruction : pas un debut d'instruction
      Ofs   : Integer_32;
      Val   : Unsigned_64;
   end record;
   for Decode use record
      Op    at 0 range 0 .. 7;
      Lvl   at 1 range 0 .. 7;
      Lg    at 2 range 0 .. 7;
      Poids at 3 range 0 .. 7;
      Ofs   at 4 range 0 .. 31;
      Val   at 8 range 0 .. 63;
   end record;

   Pas_Une_Instruction : constant := 255;

   type Tableau is array (Natural range <>) of Decode;
   type Acces_Tableau is access Tableau;

   Cache      : Acces_Tableau;
   Taille     : Unsigned_64 := 0;      -- octets couverts a partir de Entree
   Table_Lue  : Boolean := False;
   Nb_Decodees : Natural := 0;

   function Mot_Signe is new Unchecked_Conversion (Integer_64, Unsigned_64);

   --  extension de signe d'un champ de Bits bits
   function Etendre (X : Unsigned_64; Bits : Natural) return Unsigned_64 is
      Signe_Bit : constant Unsigned_64 := Shift_Left (1, Bits - 1);
   begin
      if (X and Signe_Bit) /= 0 then
         return X or not (Shift_Left (Signe_Bit, 1) - 1);
      end if;
      return X;
   end Etendre;

   function Niveau (Champ : Unsigned_64) return Integer_8 is
   begin
      if Champ = 15 then
         return -1;
      end if;
      return Integer_8 (Champ);
   end Niveau;

   procedure Preparer is
      Vide_Initial : Decode := (Op => 0, Lvl => 0, Lg => 0, Poids => 1, Ofs => 0, Val => 0);
      Table : constant Unsigned_64 := Table_Instructions;
      W, A : Unsigned_64;
      D : Natural;
      Attente : Natural := 0;
   begin
      Table_Lue := Table /= 0;
      if Table_Lue then
         Taille := Table - Entree;               -- le code et ses donnees precedent la table
         Vide_Initial.Poids := Pas_Une_Instruction;
      else
         Taille := Fin_Code - Entree;
      end if;
      Cache := new Tableau'(0 .. Natural (Taille) - 1 => Vide_Initial);
      if not Table_Lue then
         return;
      end if;
      for K in 0 .. Nombre_Instructions - 1 loop
         W := Lire_32 (Table + Unsigned_64 (4 * K));
         A := Base_Image + (W and 16#3FFF_FFFF#);
         if (W and 16#4000_0000#) /= 0 then            -- VIDE : instruction LLIR sans instruction HX
            Attente := Attente + 1;
         else
            if A < Entree or else A - Entree >= Taille then
               Signaler ("table des instructions : adresse hors du code " & Hexa (A));
            end if;
            D := Natural (A - Entree);
            if (W and 16#8000_0000#) /= 0 then         -- SUITE
               Cache (D).Poids := Unsigned_8 (Attente);
            else
               Cache (D).Poids := Unsigned_8 (1 + Attente);
            end if;
            Attente := 0;
         end if;
      end loop;
   end Preparer;

   procedure Decoder (PC : Unsigned_64; D : Natural) is
      E    : Decode renames Cache (D);
      Code_Op : constant Natural := Natural (Lire_8 (PC));
      T    : constant Description := HX_Codes.Table (Code_Op);
      N    : constant Natural := Longueur_Complement (T.G);
      C    : Unsigned_64 := 0;
      Lvl  : Integer_8 := 0;
      Ofs  : Integer_32 := 0;
      Val  : Unsigned_64 := 0;
      Famille : constant Natural := Code_Op / 64;
   begin
      if E.Poids = Pas_Une_Instruction then
         Signaler ("PC " & Hexa (PC) & " : ce n'est pas un debut d'instruction HX");
      end if;
      if T.G = G_Illegal then
         Signaler ("opcode HX reserve " & Hexa (Unsigned_64 (Code_Op)) & " a l'adresse " & Hexa (PC));
      end if;
      if Unsigned_64 (D + 1 + N) > Taille then
         Signaler ("instruction HX tronquee a l'adresse " & Hexa (PC));
      end if;
      for K in 1 .. N loop                                  -- poids fort en tete
         C := Shift_Left (C, 8) or Lire_8 (PC + Unsigned_64 (K));
      end loop;
      case T.G is
         when G_Aucun =>
            if Famille = 1 or Famille = 2 then              -- FMT 00 : lvl = 1111, disp = 0
               Lvl := -1;
            elsif T.Code = OP_LEXCMP then                   -- s = bit 2, SZ = bits 1..0
               Ofs := Integer_32 (2 ** (Code_Op mod 4));
               if (Code_Op / 4) mod 2 = 0 then
                  Lvl := 1;                                 -- composants signes
               end if;
            end if;
         when G_Imm4 =>
            Val := Unsigned_64 (Code_Op mod 16);
         when G_B16 =>
            Lvl := Niveau (Shift_Right (C, 12));
            if T.Code = OP_LINK then
               Val := C and 16#FFF#;
            else
               Val := Etendre (C and 16#FFF#, 12);
            end if;
         when G_B24 =>
            Lvl := Niveau (Shift_Right (C, 20));
            if T.Code = OP_LINK then
               Val := C and 16#F_FFFF#;
            else
               Val := Etendre (C and 16#F_FFFF#, 20);
            end if;
         when G_C24 =>
            Lvl := Niveau (Shift_Right (C, 20));
            Ofs := Integer_32 (Shift_Right (C, 16) and 15);
            Val := Etendre (C and 16#FFFF#, 16);
         when G_C32 =>
            Lvl := Niveau (Shift_Right (C, 28));
            Ofs := Integer_32 (Shift_Right (C, 20) and 16#FF#);
            Val := Etendre (C and 16#F_FFFF#, 20);
         when G_D8 =>
            if T.Code = OP_LI then
               Val := Etendre (C, 8);
            elsif T.Code = OP_UNLINK or T.Code = OP_UNLINKR then
               Lvl := Integer_8 (C);
            else
               Val := C;                                    -- TRAP : service
            end if;
         when G_D16 =>
            Val := Etendre (C, 16);
         when G_D32 =>
            Val := Etendre (C, 32);
         when G_D64 =>
            Val := C;
         when G_D24 =>
            if T.Code = OP_CALL then
               Val := PC + 4 + Etendre (C, 24);
            else
               Val := C;                                    -- RTD n, EXC_RAISE top
            end if;
         when G_D8_8 =>
            Val := Shift_Right (C, 8);                      -- lsb
            Ofs := Integer_32 (C and 16#FF#);               -- w
         when G_BR8 | G_BR16 | G_BR24 | G_BR32 =>
            Val := PC + Unsigned_64 (1 + N) + Etendre (C, 8 * N);
         when G_Illegal =>
            null;
      end case;
      E.Op := Unsigned_8 (T.Code);
      E.Lvl := Lvl;
      E.Ofs := Ofs;
      E.Val := Val;
      E.Lg := Unsigned_8 (1 + N);
      Nb_Decodees := Nb_Decodees + 1;
   end Decoder;

   procedure Lire (PC       : Unsigned_64;
                   Op       : out Integer;
                   Lvl      : out Integer;
                   Ofs      : out Unsigned_64;
                   Val      : out Unsigned_64;
                   Longueur : out Unsigned_64;
                   Poids    : out Integer) is
      D : constant Unsigned_64 := PC - Entree;
   begin
      if D >= Taille then                                   -- couvre aussi PC < Entree
         Signaler ("PC hors de la zone de code : " & Hexa (PC));
      end if;
      if Cache (Natural (D)).Lg = 0 then
         Decoder (PC, Natural (D));
      end if;
      declare
         E : Decode renames Cache (Natural (D));
      begin
         Op := Integer (E.Op);
         Lvl := Integer (E.Lvl);
         Ofs := Mot_Signe (Integer_64 (E.Ofs));
         Val := E.Val;
         Longueur := Unsigned_64 (E.Lg);
         Poids := Integer (E.Poids);
      end;
   end Lire;

   function Avec_Table return Boolean is
   begin
      return Table_Lue;
   end Avec_Table;

   function Instructions_Decodees return Natural is
   begin
      return Nb_Decodees;
   end Instructions_Decodees;

end Decodeur_HX;
