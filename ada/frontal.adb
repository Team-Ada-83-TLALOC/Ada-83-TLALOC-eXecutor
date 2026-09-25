with Memoire;
with Mots; use Mots;
with TX_Codes; use TX_Codes;
package body Frontal is

   type Compteur is range 0 .. 2**62;

   type Tab_U64 is array (Natural range <>) of Unsigned_64;
   type Tab_Ent is array (Natural range <>) of Integer;
   type Tab_Sig is array (Natural range <>) of Signe;
   type Tab_Bool is array (Natural range <>) of Boolean;
   type Acc_U64 is access Tab_U64;
   type Acc_Ent is access Tab_Ent;
   type Acc_Sig is access Tab_Sig;
   type Acc_Bool is access Tab_Bool;

   Nb : Natural := 0;                                -- instructions statiques
   Adr, Val_T : Acc_U64;
   Op_T, Cible, N_Op, Arg_S, Arg_D : Acc_Ent;        -- N_Op : 1, ou 2 pour un repli
   Pos_S, Pos_O, Pos_A : Acc_Sig;
   Case_De : Acc_Ent;                                -- (PC - Entree) / 16 -> indice
   Total_S, Total_O, Total_A : Signe := 0;
   Iterations : Natural := 0;

   --  statistiques statiques
   Nb_Branches, Nb_Appels, Nb_Replis, Nb_Hors : Natural := 0;
   Br_S, Br_D : array (1 .. 4) of Natural := (others => 0);    -- tailles de branches

   --  modeles de chargement
   Nb_Config : constant := 6;
   type Config is range 1 .. Nb_Config;
   Double : constant array (Config) of Boolean := (False, False, False, True, True, True);
   Bloc_O : constant array (Config) of Signe := (16, 32, 32, 8, 8, 16);   -- ou flux unique
   Bloc_A : constant array (Config) of Signe := (0, 0, 0, 8, 16, 16);
   Larg   : constant array (Config) of Natural := (6, 6, 8, 6, 6, 8);
   --  chargement continu d'un bloc par cycle et par flux depuis la derniere redirection
   --  (cycle Depart, blocs de base) ; decodage de L instructions au plus par cycle
   Depart, Base_O, Base_A, Decode : array (Config) of Signe := (others => 0);
   Dans_Cycle : array (Config) of Natural := (others => 0);
   Premier : Boolean := True;
   Pris_Prec : Boolean := False;
   N_Dyn : Compteur := 0;
   Octets_S, Octets_O, Octets_A : Compteur := 0;
   Lignes_S, Lignes_O, Lignes_A : Acc_Bool;          -- lignes de 64 octets touchees

   ------------------------------------------------------------------

   function Plus_Grand (A, B : Signe) return Signe is
   begin
      if A > B then
         return A;
      end if;
      return B;
   end Plus_Grand;

   function Tient (V : Signe; Bits : Natural) return Boolean is
      Lim : constant Signe := 2 ** (Bits - 1);
   begin
      return V >= -Lim and V < Lim;
   end Tient;

   function Taille_Imm (V : Unsigned_64) return Integer is
      S : constant Signe := Vers_Signe (V);
   begin
      if V <= 15 then
         return 0;                                    -- LI imm4 [Q3]
      elsif Tient (S, 8) then
         return 1;
      elsif Tient (S, 16) then
         return 2;
      elsif Tient (S, 32) then
         return 4;
      end if;
      return 8;
   end Taille_Imm;

   --  complement d'un acces B ; 0 si lvl = 1111 et disp = 0
   function Taille_B (Lvl : Integer; Disp : Unsigned_64) return Integer is
      D : constant Signe := Vers_Signe (Disp);
   begin
      if Lvl = -1 and D = 0 then
         return 0;
      elsif Tient (D, 12) then
         return 2;
      elsif Tient (D, 20) then
         return 3;
      end if;
      Nb_Hors := Nb_Hors + 1;
      return 8;                                        -- hors format (absent de TLALOC)
   end Taille_B;

   --  complement d'un acces C ; un repli (ofs > 255) ajoute une instruction B24
   procedure Taille_C (Lvl : Integer; Disp, Ofs : Unsigned_64; Nop, Arg : out Integer) is
      D : constant Signe := Vers_Signe (Disp);
      O : constant Signe := Vers_Signe (Ofs);
   begin
      Nop := 1;
      if Lvl = -1 and D = 0 and O = 0 then
         Arg := 0;
      elsif O >= 0 and O <= 15 and Tient (D, 16) then
         Arg := 3;
      elsif O >= 0 and O <= 255 and Tient (D, 20) then
         Arg := 4;
      elsif Tient (D, 20) and O >= 0 and Tient (O, 20) then
         Nop := 2;                                      -- LIVA lvl, disp, 0 puis Lx [B24] 1111, ofs
         Nb_Replis := Nb_Replis + 1;
         if Tient (D, 16) then
            Arg := 3 + 3;
         else
            Arg := 4 + 3;
         end if;
      else
         Nb_Hors := Nb_Hors + 1;
         Arg := 8;
      end if;
   end Taille_C;

   procedure Tailles (K : Natural; Lvl : Integer; Ofs, Val : Unsigned_64) is
      Op : constant Integer := Op_T (K);
      Nop : Integer := 1;
      A : Integer := 0;                                -- complement, identique dans les deux
   begin
      case Op is
         when OP_LI | OP_LIF | OP_LCA | OP_LSPA =>
            A := Taille_Imm (Val);
         when OP_UBFXI | OP_SBFXI | OP_BFII =>
            A := 2;                                    -- D8_8
         when OP_LVA | OP_LB .. OP_ULD | OP_SB .. OP_SA =>
            A := Taille_B (Lvl, Val);
         when OP_LINK =>
            if Val <= 4095 then
               A := 2;
            elsif Val < 2**20 then
               A := 3;
            else
               Nb_Hors := Nb_Hors + 1;
               A := 8;
            end if;
         when OP_EXC_MACH =>
            A := Taille_B (Lvl, Val);
         when OP_CHKB .. OP_CHKUD =>
            A := 3;                                    -- B24
         when OP_CHKIB .. OP_CHKUID =>
            A := 4;                                    -- C32
         when OP_LIVA | OP_LIB .. OP_ULID | OP_SIB .. OP_SIA =>
            Taille_C (Lvl, Val, Ofs, Nop, A);
         when OP_RTD =>
            if Val /= 0 then
               A := 3;
            end if;
         when OP_UNLINK | OP_UNLINKR | OP_TRAP =>
            A := 1;
         when OP_EXC_RAISE =>
            A := 3;
         when others =>
            A := 0;                                    -- famille A, LEXCMP, CALLI...
      end case;
      N_Op (K) := Nop;
      Arg_S (K) := A;
      Arg_D (K) := A;
      case Op is
         when OP_BRA | OP_BT | OP_BF =>
            Arg_S (K) := 1;                            -- relaxation a partir du plus court
            Arg_D (K) := 2;
            Nb_Branches := Nb_Branches + 1;
         when OP_CALL =>
            Arg_S (K) := 3;                            -- D24
            Arg_D (K) := 6;                            -- deux deplacements D24
            Nb_Appels := Nb_Appels + 1;
         when others => null;
      end case;
   end Tailles;

   procedure Positions is
      S, O, A : Signe := 0;
   begin
      for K in 0 .. Nb - 1 loop
         Pos_S (K) := S;
         Pos_O (K) := O;
         Pos_A (K) := A;
         S := S + Signe (N_Op (K) + Arg_S (K));
         O := O + Signe (N_Op (K));
         A := A + Signe (Arg_D (K));
      end loop;
      Total_S := S;
      Total_O := O;
      Total_A := A;
   end Positions;

   procedure Preparer is
      Table : constant Unsigned_64 := Memoire.Table_Instructions;
      Op, Lvl, T : Integer;
      Ofs, Val : Unsigned_64;
      Nb_Cases : Natural;
      Change : Boolean;
      DS, D_Op, DA : Signe;
      Taille : Integer;
   begin
      Nb := Memoire.Nombre_Instructions;
      if Table = 0 or Nb = 0 then
         Memoire.Signaler ("-f demande une image TX de format 3 (table des instructions)");
      end if;
      Adr := new Tab_U64 (0 .. Nb - 1);
      Val_T := new Tab_U64 (0 .. Nb - 1);
      Op_T := new Tab_Ent (0 .. Nb - 1);
      Cible := new Tab_Ent'(0 .. Nb - 1 => -1);
      N_Op := new Tab_Ent (0 .. Nb - 1);
      Arg_S := new Tab_Ent (0 .. Nb - 1);
      Arg_D := new Tab_Ent (0 .. Nb - 1);
      Pos_S := new Tab_Sig (0 .. Nb - 1);
      Pos_O := new Tab_Sig (0 .. Nb - 1);
      Pos_A := new Tab_Sig (0 .. Nb - 1);
      Nb_Cases := Natural ((Memoire.Fin_Code - Memoire.Entree) / 16) + 1;
      Case_De := new Tab_Ent'(0 .. Nb_Cases - 1 => -1);

      for K in 0 .. Nb - 1 loop
         Adr (K) := Memoire.Base_Image + Memoire.Lire_32 (Table + Unsigned_64 (4 * K));
         Case_De (Natural ((Adr (K) - Memoire.Entree) / 16)) := K;
      end loop;
      for K in 0 .. Nb - 1 loop
         Memoire.Lire_Instruction (Adr (K), Op, Lvl, Ofs, Val);
         Op_T (K) := Op;
         Val_T (K) := Val;
         Tailles (K, Lvl, Ofs, Val);
         if Op = OP_BRA or Op = OP_BT or Op = OP_BF or Op = OP_CALL then
            T := Case_De (Natural ((Val - Memoire.Entree) / 16));
            if T < 0 or else Adr (T) /= Val then
               Memoire.Signaler ("cible de branchement hors de la table des instructions");
            end if;
            Cible (K) := T;
         end if;
      end loop;

      --  relaxation : les branches ne font que grandir, donc la boucle termine
      loop
         Iterations := Iterations + 1;
         Positions;
         Change := False;
         for K in 0 .. Nb - 1 loop
            if Cible (K) >= 0 and Op_T (K) /= OP_CALL then
               T := Cible (K);
               DS := Pos_S (T) - (Pos_S (K) + Signe (N_Op (K) + Arg_S (K)));
               if Tient (DS, 8) then
                  Taille := 1;
               elsif Tient (DS, 16) then
                  Taille := 2;
               elsif Tient (DS, 24) then
                  Taille := 3;
               else
                  Taille := 4;
               end if;
               if Taille > Arg_S (K) then
                  Arg_S (K) := Taille;
                  Change := True;
               end if;
               D_Op := Pos_O (T) - (Pos_O (K) + Signe (N_Op (K)));
               DA := Pos_A (T) - (Pos_A (K) + Signe (Arg_D (K)));
               if Tient (D_Op, 8) and Tient (DA, 8) then
                  Taille := 2;
               elsif Tient (D_Op, 16) and Tient (DA, 16) then
                  Taille := 4;
               elsif Tient (D_Op, 24) and Tient (DA, 24) then
                  Taille := 6;
               else
                  Taille := 8;
               end if;
               if Taille > Arg_D (K) then
                  Arg_D (K) := Taille;
                  Change := True;
               end if;
            end if;
         end loop;
         exit when not Change;
      end loop;
      Positions;

      for K in 0 .. Nb - 1 loop
         if Cible (K) >= 0 and Op_T (K) /= OP_CALL then
            Br_S (Arg_S (K)) := Br_S (Arg_S (K)) + 1;
            Br_D (Arg_D (K) / 2) := Br_D (Arg_D (K) / 2) + 1;
         end if;
      end loop;
      Lignes_S := new Tab_Bool'(0 .. Natural (Total_S / 64) + 1 => False);
      Lignes_O := new Tab_Bool'(0 .. Natural (Total_O / 64) + 1 => False);
      Lignes_A := new Tab_Bool'(0 .. Natural (Total_A / 64) + 1 => False);
   end Preparer;

   ------------------------------------------------------------------ chargement

   procedure Instruction (PC, Suivant : Unsigned_64) is
      K : constant Integer := Case_De (Natural ((PC - Memoire.Entree) / 16));
      S, E, O, EO, A, EA, Dispo, Cand : Signe;
      Pris : constant Boolean := Suivant /= PC + 16;
   begin
      N_Dyn := N_Dyn + 1;
      S := Pos_S (K);
      E := S + Signe (N_Op (K) + Arg_S (K));
      O := Pos_O (K);
      EO := O + Signe (N_Op (K));
      A := Pos_A (K);
      EA := A + Signe (Arg_D (K));
      Octets_S := Octets_S + Compteur (E - S);
      Octets_O := Octets_O + Compteur (EO - O);
      Octets_A := Octets_A + Compteur (EA - A);
      Lignes_S (Natural (S / 64)) := True;
      Lignes_S (Natural ((E - 1) / 64)) := True;
      Lignes_O (Natural (O / 64)) := True;
      if EA > A then
         Lignes_A (Natural (A / 64)) := True;
         Lignes_A (Natural ((EA - 1) / 64)) := True;
      end if;

      for C in Config loop
         if Premier or Pris_Prec then                  -- redirection : nouveau groupe
            if Premier then
               Depart (C) := 0;
            else
               Depart (C) := Decode (C) + 1;          -- la cible est chargee au cycle suivant
            end if;
            if Double (C) then
               Base_O (C) := O / Bloc_O (C);
               Base_A (C) := A / Bloc_A (C);
            else
               Base_O (C) := S / Bloc_O (C);
            end if;
         end if;
         --  cycle ou tous les octets de l'instruction sont charges
         if Double (C) then
            Dispo := Depart (C) + ((EO - 1) / Bloc_O (C) - Base_O (C));
            if EA > A then
               Dispo := Plus_Grand (Dispo, Depart (C) + ((EA - 1) / Bloc_A (C) - Base_A (C)));
            end if;
         else
            Dispo := Depart (C) + ((E - 1) / Bloc_O (C) - Base_O (C));
         end if;
         if Premier or Pris_Prec then
            Cand := Dispo;
         elsif Dans_Cycle (C) = Larg (C) then
            Cand := Plus_Grand (Decode (C) + 1, Dispo);
         else
            Cand := Plus_Grand (Decode (C), Dispo);
         end if;
         if Premier or Pris_Prec or Cand > Decode (C) then
            Dans_Cycle (C) := 1;
         else
            Dans_Cycle (C) := Dans_Cycle (C) + 1;
         end if;
         Decode (C) := Cand;
      end loop;
      Premier := False;
      Pris_Prec := Pris;
   end Instruction;

   ------------------------------------------------------------------ rapport

   procedure Rapport (Sortie : in out Text_IO.File_Type; Vers_Fichier : Boolean) is

      Titres : constant array (Config) of String (1 .. 30) :=
        ("flux unique, bloc 16          ",
         "flux unique, bloc 32          ",
         "flux unique, bloc 32          ",
         "double flux, blocs 8 + 8      ",
         "double flux, blocs 8 + 16     ",
         "double flux, blocs 16 + 16    ");
      Ns : constant Signe := Signe (Nb);

      procedure Ecrire (S : String) is
      begin
         if Vers_Fichier then
            Text_IO.Put_Line (Sortie, S);
         else
            Text_IO.Put_Line (Text_IO.Standard_Error, S);
         end if;
      end Ecrire;

      function Cadre (S : String; Largeur : Natural) return String is
         Blancs : constant String (1 .. 40) := (others => ' ');
      begin
         if S'Length >= Largeur then
            return S;
         end if;
         return Blancs (1 .. Largeur - S'Length) & S;
      end Cadre;

      function Nombre (V : Signe) return String is
      begin
         return Cadre (Image (V), 13);
      end Nombre;

      function Ratio (V, Sur : Signe) return String is      -- deux decimales
         P : Signe;
      begin
         if Sur = 0 then
            return "-";
         end if;
         P := (V * 100 + Sur / 2) / Sur;
         if P mod 100 < 10 then
            return Image (P / 100) & ".0" & Image (P mod 100);
         end if;
         return Image (P / 100) & "." & Image (P mod 100);
      end Ratio;

      function Compte (T : Acc_Bool) return Signe is
         R : Signe := 0;
      begin
         for I in T'Range loop
            if T (I) then
               R := R + 1;
            end if;
         end loop;
         return R;
      end Compte;

   begin
      Ecrire ("DISPOSITION DU CODE (LLIR_hardware_support) ET CHARGEMENT");
      Ecrire ("  instructions statiques               " & Nombre (Ns)
              & "   dont branches " & Image (Nb_Branches) & ", CALL " & Image (Nb_Appels)
              & ", replis C " & Image (Nb_Replis) & ", hors format " & Image (Nb_Hors));
      Ecrire ("  taille du code     flux unique       " & Nombre (Total_S) & " octets   "
              & Ratio (Total_S, Ns) & " par instruction");
      Ecrire ("                     double flux       " & Nombre (Total_O + Total_A) & " octets   "
              & Ratio (Total_O + Total_A, Ns) & " par instruction  (opcodes "
              & Image (Total_O) & ", arguments " & Image (Total_A) & ")");
      Ecrire ("  branches (statique) flux unique   1 / 2 / 3 / 4 octets : " & Image (Br_S (1)) & " / "
              & Image (Br_S (2)) & " / " & Image (Br_S (3)) & " / " & Image (Br_S (4)));
      Ecrire ("                      double flux   2 / 4 / 6 / 8 octets : " & Image (Br_D (1)) & " / "
              & Image (Br_D (2)) & " / " & Image (Br_D (3)) & " / " & Image (Br_D (4)));
      Ecrire ("  relaxation des branches : " & Image (Iterations) & " iterations");
      Ecrire ("  octets lus (dynamique)  flux unique " & Nombre (Signe (Octets_S))
              & "   " & Ratio (Signe (Octets_S), Signe (N_Dyn)) & " par instruction");
      Ecrire ("                          double flux " & Nombre (Signe (Octets_O + Octets_A))
              & "   " & Ratio (Signe (Octets_O + Octets_A), Signe (N_Dyn)) & " par instruction");
      Ecrire ("  lignes de 64 octets touchees : flux unique " & Image (Compte (Lignes_S))
              & ", double flux " & Image (Compte (Lignes_O)) & " + " & Image (Compte (Lignes_A)));
      Ecrire ("  debit du chargement (prediction parfaite) :         largeur   instructions / cycle");
      for C in Config loop
         Ecrire ("    " & Titres (C) & "                  " & Cadre (Image (Larg (C)), 3)
                 & Cadre (Ratio (Signe (N_Dyn), Decode (C) + 1), 14));
      end loop;
      Ecrire ("");
   end Rapport;

end Frontal;
