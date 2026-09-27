with Text_IO;
with Mots; use Mots;
with TX_Codes; use TX_Codes;
with Limites;
with Frontal;
package body Profil is

   Par_Code     : array (0 .. Dernier_Code) of Compteur := (others => 0);
   Arg_Par_Code : array (0 .. Dernier_Code) of Compteur := (others => 0);
   Par_Service  : array (0 .. Dernier_Service) of Compteur := (others => 0);
   Nb_Instr     : Compteur := 0;
   Octets_Arg   : Compteur := 0;

   --  formats
   B_A, B16, B24, B_Hors         : Compteur := 0;
   C_A, C24, C32, C_Hors         : Compteur := 0;
   LI4, LI8, LI16, LI32, LI64    : Compteur := 0;
   BR16, BR32, BR48, BR64        : Compteur := 0;
   CHK_B24, CHK_C32, CHK_Hors    : Compteur := 0;   -- formats fixes des CHK

   --  acces par niveau
   Acces_Pile, Acces_Local, Acces_Global, Acces_Englobant : Compteur := 0;
   Par_Niveau : array (0 .. 14) of Compteur := (others => 0);

   Nb_Booleens, Nb_Decalages, Nb_Champs : Compteur := 0;

   --  BT/BF sur valeur hors {0,1} : les 16 premiers PC distincts
   Max_Signales : constant := 16;
   Sig_PC, Sig_Val : array (1 .. Max_Signales) of Unsigned_64 := (others => 0);
   Sig_Nb          : array (1 .. Max_Signales) of Compteur := (others => 0);
   Nb_Signales     : Integer := 0;

   --  Paires d'instructions : B executee juste apres A ET placee juste apres A
   --  dans le code, donc fusionnables au decodage.
   Paires : array (0 .. Dernier_Code, 0 .. Dernier_Code) of Compteur :=
     (others => (others => 0));
   Op_Precedent : Integer := 0;
   Suivant_Precedent : Unsigned_64 := 0;      -- adresse qui suit l'instruction precedente
   Suivant_Fenetre   : Unsigned_64 := 0;      -- meme chose pour la fenetre des idiomes
   Longueur_Courante : Unsigned_64 := 16;
   Nb_Paires    : Compteur := 0;      -- paires adjacentes observees
   Appel_Link   : Compteur := 0;      -- CALL/CALLI dont la cible commence par LINK

   --  Fenetre des 8 dernieres instructions executees, pour reconnaitre des idiomes
   type Element_Fenetre is record
      Op, Lvl  : Integer := 0;
      Ofs, Val : Unsigned_64 := 0;
      PC       : Unsigned_64 := 0;
      Arg      : Compteur := 0;         -- octets du flux ARG
   end record;
   Fenetre  : array (0 .. 7) of Element_Fenetre;
   Tete     : Integer := 0;             -- indice de l'instruction courante
   Sequence : Integer := 0;             -- instructions consecutives dans le code finissant a Tete

   --  controles d'intervalle : DUP / borne / CLT|CLE|CGT|CGE / BT
   Chk_Complets, Chk_Demi           : Compteur := 0;
   Chk_Adjacents, Chk_Immediats     : Compteur := 0;
   Chk_Octets_Idiome, Chk_Octets_Chk : Compteur := 0;
   Dernier_Demi_Chk                 : Compteur := 0;
   Demi_En_Attente                  : Unsigned_64 := 0;   -- PC du BT du dernier demi-controle

   --  disposition des bornes des controles complets a bornes voisines
   Chk_Par_Op                        : array (0 .. Dernier_Code) of Compteur := (others => 0);
   Chk_Ordre_Normal, Chk_Ordre_Inverse, Chk_Autre_Ecart : Compteur := 0;
   Chk_Clt_Cgt                       : Compteur := 0;   -- CLT sur FST puis CGT sur LST
   Chk_Meme_Cible                    : Compteur := 0;   -- les deux BT vers Cible_Chk
   Cible_Chk                         : Unsigned_64 := 0;

   --  champs de bits : indice 0 UBFX, 1 SBFX, 2 BFI
   Bf_Imm, Bf_Etroit     : array (0 .. 2) of Compteur := (others => 0);
   Bf_Arg_LI             : array (0 .. 2) of Compteur := (others => 0);  -- octets ARG des deux LI
   Couples : array (0 .. 2, 0 .. 63, 1 .. 64) of Compteur :=
     (others => (others => (others => 0)));

   --  reductions par peephole
   Lva_B, Lva_C, La_B, La_C          : Compteur := 0;

   --  branchements conditionnels
   Pris, Non_Pris                    : Compteur := 0;

   Sortie : Text_IO.File_Type;
   Vers_Fichier : Boolean := False;

   function Entre (V : Unsigned_64; Bas, Haut : Signe) return Boolean is
      S : constant Signe := Vers_Signe (V);
   begin
      return S >= Bas and S <= Haut;
   end Entre;
   pragma Inline (Entre);

   function Taille_B (Op, Lvl : Integer; Disp : Unsigned_64) return Compteur is
   begin
      if Op = OP_LINK then                        -- taille non signee
         if Entre (Disp, 0, 4095) then
            B16 := B16 + 1; return 2;
         elsif Entre (Disp, 0, 2**20 - 1) then
            B24 := B24 + 1; return 3;
         end if;
      elsif Lvl = -1 and Disp = 0 then
         B_A := B_A + 1; return 0;
      elsif Entre (Disp, -2048, 2047) then
         B16 := B16 + 1; return 2;
      elsif Entre (Disp, -2**19, 2**19 - 1) then
         B24 := B24 + 1; return 3;
      end if;
      B_Hors := B_Hors + 1;
      return 8;
   end Taille_B;

   function Taille_C (Lvl : Integer; Disp, Ofs : Unsigned_64) return Compteur is
   begin
      if Lvl = -1 and Disp = 0 and Ofs = 0 then
         C_A := C_A + 1; return 0;
      elsif Entre (Disp, -2**15, 2**15 - 1) and Entre (Ofs, 0, 15) then
         C24 := C24 + 1; return 3;
      elsif Entre (Disp, -2**19, 2**19 - 1) and Entre (Ofs, 0, 255) then
         C32 := C32 + 1; return 4;
      end if;
      C_Hors := C_Hors + 1;
      return 8;
   end Taille_C;

   function Taille_LI (V : Unsigned_64) return Compteur is
   begin
      if V <= 15 then                             -- LI imm4 non signe [Q3]
         LI4 := LI4 + 1; return 0;
      elsif Entre (V, -2**7, 2**7 - 1) then
         LI8 := LI8 + 1; return 1;
      elsif Entre (V, -2**15, 2**15 - 1) then
         LI16 := LI16 + 1; return 2;
      elsif Entre (V, -2**31, 2**31 - 1) then
         LI32 := LI32 + 1; return 4;
      end if;
      LI64 := LI64 + 1;
      return 8;
   end Taille_LI;

   --  Estimation : ecart OP en instructions, ecart ARG suppose double
   function Taille_Branche (Cible, PC : Unsigned_64) return Compteur is
      D : Signe := Vers_Signe (Cible - PC - 16) / 16;
   begin
      if Image_HX then                         -- format reel : BR8, BR16, BR24, BR32
         case Longueur_Courante is
            when 2 => BR16 := BR16 + 1;
            when 3 => BR32 := BR32 + 1;
            when 4 => BR48 := BR48 + 1;
            when others => BR64 := BR64 + 1;
         end case;
         return Compteur (Longueur_Courante) - 1;
      end if;
      if D < 0 then
         D := -D;
      end if;
      D := 2 * D;
      if D < 2**7 then
         BR16 := BR16 + 1; return 2;
      elsif D < 2**15 then
         BR32 := BR32 + 1; return 4;
      elsif D < 2**23 then
         BR48 := BR48 + 1; return 6;
      end if;
      BR64 := BR64 + 1;
      return 8;
   end Taille_Branche;
   pragma Inline (Taille_B, Taille_C, Taille_LI, Taille_Branche);

   --  element K instructions en arriere (0 = courante)
   function Recul (K : Integer) return Element_Fenetre is
   begin
      return Fenetre ((Tete - K) mod 8);
   end Recul;

   function Est_Borne (Op : Integer) return Boolean is
   begin
      return Op = OP_LI or (Op >= OP_LB and Op <= OP_ULID);
   end Est_Borne;

   --  DUP / borne / comparaison / BT se terminant K instructions en arriere
   function Est_Quad (K : Integer) return Boolean is
   begin
      return Recul (K).Op = OP_BT
        and then Recul (K + 1).Op >= OP_CGT and then Recul (K + 1).Op <= OP_CLE
        and then Est_Borne (Recul (K + 2).Op)
        and then Recul (K + 3).Op = OP_DUP;
   end Est_Quad;

   --  deux bornes lues par la meme instruction a des adresses voisines (FST, LST)
   function Bornes_Adjacentes (P, Q : Element_Fenetre) return Boolean is
      D : Signe;
   begin
      if P.Op /= Q.Op or P.Lvl /= Q.Lvl or P.Op = OP_LI then
         return False;
      elsif P.Op <= OP_ULD then                          -- famille B : disp voisins
         D := Vers_Signe (Q.Val - P.Val);
         return D /= 0 and D >= -8 and D <= 8;
      else                                               -- famille C : meme disp, ofs voisins
         D := Vers_Signe (Q.Ofs - P.Ofs);
         return P.Val = Q.Val and D /= 0 and D >= -8 and D <= 8;
      end if;
   end Bornes_Adjacentes;

   --  taille d'une borne d'apres l'instruction qui la lit
   function Taille_Borne (Op : Integer) return Signe is
   begin
      case Op is
         when OP_LB | OP_ULB | OP_LIB | OP_ULIB => return 1;
         when OP_LW | OP_ULW | OP_LIW | OP_ULIW => return 2;
         when OP_LD | OP_ULD | OP_LID | OP_ULID => return 4;
         when others                            => return 8;
      end case;
   end Taille_Borne;

   --  controle complet a bornes voisines : B1 lue par le premier volet, B2 par le second
   procedure Analyser_Chk (B1, B2 : Element_Fenetre) is
      Ecart : Signe;
      T     : constant Signe := Taille_Borne (B1.Op);
   begin
      Chk_Par_Op (B1.Op) := Chk_Par_Op (B1.Op) + 1;
      if B1.Op <= OP_ULD then                            -- famille B : ecart des disp
         Ecart := Vers_Signe (B2.Val - B1.Val);
      else                                               -- famille C : ecart des ofs
         Ecart := Vers_Signe (B2.Ofs - B1.Ofs);
      end if;
      if Ecart = T then
         Chk_Ordre_Normal := Chk_Ordre_Normal + 1;
      elsif Ecart = -T then
         Chk_Ordre_Inverse := Chk_Ordre_Inverse + 1;
      else
         Chk_Autre_Ecart := Chk_Autre_Ecart + 1;
      end if;
      --  Recul (5) : comparaison du premier volet ; Recul (1) : celle du second
      if Ecart = T and Recul (5).Op = OP_CLT and Recul (1).Op = OP_CGT then
         Chk_Clt_Cgt := Chk_Clt_Cgt + 1;
      end if;
      --  Recul (4) et Recul (0) : les deux BT
      if Cible_Chk = 0 then
         Cible_Chk := Recul (0).Val;
      end if;
      if Recul (4).Val = Cible_Chk and Recul (0).Val = Cible_Chk then
         Chk_Meme_Cible := Chk_Meme_Cible + 1;
      end if;
   end Analyser_Chk;

   --  UBFX, SBFX ou BFI qui vient d'entrer dans la fenetre (Recul (0))
   --  Recul (2) = LI lsb, Recul (1) = LI w ; pour UBFX/SBFX, Recul (3) = producteur de v
   procedure Observer_Champs (Op : Integer) is
      K : constant Integer := Op - OP_UBFX;
      L, W : Unsigned_64;
      Chg : Element_Fenetre;
      Aligne : Boolean;
   begin
      if Sequence < 3 or else Recul (1).Op /= OP_LI or else Recul (2).Op /= OP_LI then
         return;                                      -- lsb ou w calcules : pas de forme immediate
      end if;
      L := Recul (2).Val;
      W := Recul (1).Val;
      Bf_Imm (K) := Bf_Imm (K) + 1;
      Bf_Arg_LI (K) := Bf_Arg_LI (K) + Recul (1).Arg + Recul (2).Arg;
      if L <= 63 and W >= 1 and W <= 64 then
         Couples (K, Integer (L), Integer (W)) := Couples (K, Integer (L), Integer (W)) + 1;
      end if;
      Aligne := L mod 8 = 0 and (W = 8 or W = 16 or W = 32);
      if Aligne and Op = OP_BFI then                  -- rangement etroit possible (a verifier)
         Bf_Etroit (K) := Bf_Etroit (K) + 1;
      elsif Aligne and Sequence >= 4 then
         Chg := Recul (3);
         if Chg.Op >= OP_LB and then Chg.Op <= OP_ULID
           and then L + W <= Unsigned_64 (8 * Taille_Borne (Chg.Op)) then
            Bf_Etroit (K) := Bf_Etroit (K) + 1;         -- charge etroite a l'octet L / 8
         end if;
      end if;
   end Observer_Champs;

   procedure Observer (Op, Lvl : Integer; Ofs, Val, PC : Unsigned_64; T : Compteur) is
      Prec : constant Element_Fenetre := Fenetre (Tete);
      Somme_Arg : Compteur;
      B1, B2 : Element_Fenetre;
   begin
      --  branchement conditionnel precedent : pris ou non
      if Prec.Op = OP_BT or Prec.Op = OP_BF then
         if PC = Prec.Val then
            Pris := Pris + 1;
         else
            Non_Pris := Non_Pris + 1;
         end if;
      end if;

      --  entree dans la fenetre
      if PC = Suivant_Fenetre then
         if Sequence < 8 then
            Sequence := Sequence + 1;
         end if;
      else
         Sequence := 1;
      end if;
      Suivant_Fenetre := PC + Longueur_Courante;
      Tete := (Tete + 1) mod 8;
      Fenetre (Tete) := (Op, Lvl, Ofs, Val, PC, T);
      if Op = OP_UBFX or Op = OP_SBFX or Op = OP_BFI then
         Observer_Champs (Op);
      end if;

      --  idiome de controle d'intervalle
      if Op = OP_BT and then Sequence >= 4 and then Est_Quad (0) then
         B2 := Recul (2);
         Somme_Arg := Recul (0).Arg + Recul (1).Arg + B2.Arg + Recul (3).Arg;
         Chk_Octets_Idiome := Chk_Octets_Idiome + Somme_Arg;
         if Sequence >= 8 and then Est_Quad (4)
           and then Recul (4).PC = Demi_En_Attente then   -- second volet : controle complet
            B1 := Recul (6);
            Chk_Demi := Chk_Demi - 1;
            Chk_Octets_Chk := Chk_Octets_Chk - Dernier_Demi_Chk;
            Chk_Complets := Chk_Complets + 1;
            if B1.Op = OP_LI and B2.Op = OP_LI then
               Chk_Immediats := Chk_Immediats + 1;
               Chk_Octets_Chk := Chk_Octets_Chk + B1.Arg + B2.Arg;
            elsif Bornes_Adjacentes (B1, B2) then
               Chk_Adjacents := Chk_Adjacents + 1;
               Chk_Octets_Chk := Chk_Octets_Chk + B1.Arg;   -- CHK lit la paire (FST, LST)
               Analyser_Chk (B1, B2);
            else
               Chk_Octets_Chk := Chk_Octets_Chk + B1.Arg + B2.Arg;
            end if;
            Dernier_Demi_Chk := 0;
            Demi_En_Attente := 0;
         else                                               -- premier volet ou borne unique
            Chk_Demi := Chk_Demi + 1;
            Dernier_Demi_Chk := B2.Arg;
            Demi_En_Attente := PC;
            Chk_Octets_Chk := Chk_Octets_Chk + B2.Arg;
         end if;
      end if;

      --  adresse produite par LVA/LA puis consommee aussitot au sommet (lvl = -1)
      if Lvl = -1 and then Sequence >= 2 and then Prec.Lvl >= 0 then
         if Op = OP_LVA or (Op >= OP_LB and Op <= OP_ULD) then
            if Prec.Op = OP_LVA then
               Lva_B := Lva_B + 1;
            elsif Prec.Op = OP_LA or Prec.Op = OP_LQ then
               La_B := La_B + 1;
            end if;
         elsif Op = OP_LIVA or (Op >= OP_LIB and Op <= OP_ULID) then
            if Prec.Op = OP_LVA then
               Lva_C := Lva_C + 1;
            elsif Prec.Op = OP_LA or Prec.Op = OP_LQ then
               La_C := La_C + 1;
            end if;
         end if;
      end if;
   end Observer;

   --  CHK : un seul format par forme, B24 (lvl 4, disp 20) et C32 (lvl 4, disp 20, ofs 8)
   function Taille_Chk (Op : Integer; Disp, Ofs : Unsigned_64) return Compteur is
   begin
      if Op <= OP_CHKUD then
         if Entre (Disp, -2**19, 2**19 - 1) then
            CHK_B24 := CHK_B24 + 1; return 3;
         end if;
      elsif Entre (Disp, -2**19, 2**19 - 1) and Entre (Ofs, 0, 255) then
         CHK_C32 := CHK_C32 + 1; return 4;
      end if;
      CHK_Hors := CHK_Hors + 1;                 -- sequence de remplacement
      return 8;
   end Taille_Chk;

   procedure Instruction (Op : Integer; Lvl : Integer;
                          Ofs, Val : Unsigned_64; PC : Unsigned_64;
                          Longueur : Unsigned_64) is
      T : Compteur := 0;
   begin
      Longueur_Courante := Longueur;
      Nb_Instr := Nb_Instr + 1;
      Par_Code (Op) := Par_Code (Op) + 1;
      if Op_Precedent /= 0 then
         if PC = Suivant_Precedent then
            Paires (Op_Precedent, Op) := Paires (Op_Precedent, Op) + 1;
            Nb_Paires := Nb_Paires + 1;
         elsif (Op_Precedent = OP_CALL or Op_Precedent = OP_CALLI)
           and Op = OP_LINK then
            Appel_Link := Appel_Link + 1;
         end if;
      end if;
      Op_Precedent := Op;
      Suivant_Precedent := PC + Longueur;
      case Op is
         when OP_LVA | OP_LB | OP_LW | OP_LD | OP_LQ | OP_LA | OP_ULB | OP_ULW | OP_ULD
            | OP_SB | OP_SW | OP_SD | OP_SQ | OP_SA | OP_LINK | OP_EXC_MACH =>
            T := Taille_B (Op, Lvl, Val);
         when OP_LIVA | OP_LIB | OP_LIW | OP_LID | OP_LIQ | OP_LIA
            | OP_ULIB | OP_ULIW | OP_ULID
            | OP_SIB | OP_SIW | OP_SID | OP_SIQ | OP_SIA =>
            T := Taille_C (Lvl, Val, Ofs);
         when OP_LI | OP_LIF | OP_LCA | OP_LSPA =>
            T := Taille_LI (Val);
         when OP_CHKB .. OP_CHKUID =>
            T := Taille_Chk (Op, Val, Ofs);
         when OP_UBFXI | OP_SBFXI | OP_BFII =>
            T := 2;                                  -- [D16] : lsb 6 bits, w - 1 6 bits
         when OP_BRA | OP_BT | OP_BF =>
            T := Taille_Branche (Val, PC);
         when OP_CALL | OP_EXC_RAISE =>
            T := 3;
         when OP_RTD =>
            if Val /= 0 then
               T := 3;
            end if;
         when OP_UNLINK | OP_UNLINKR | OP_TRAP =>
            T := 1;
         when others =>
            T := 0;
      end case;
      if Image_HX then
         T := Compteur (Longueur) - 1;           -- complement reel de l'instruction HX
      end if;
      Arg_Par_Code (Op) := Arg_Par_Code (Op) + T;
      Octets_Arg := Octets_Arg + T;
      Observer (Op, Lvl, Ofs, Val, PC, T);
   end Instruction;

   procedure Acces (Lvl : Integer; Courant : Integer) is
   begin
      if Lvl < 0 then
         Acces_Pile := Acces_Pile + 1;
      else
         if Lvl <= 14 then
            Par_Niveau (Lvl) := Par_Niveau (Lvl) + 1;
         end if;
         if Lvl = Courant then
            Acces_Local := Acces_Local + 1;
         elsif Lvl = 0 then
            Acces_Global := Acces_Global + 1;
         else
            Acces_Englobant := Acces_Englobant + 1;
         end if;
      end if;
   end Acces;

   procedure Service (N : Integer) is
   begin
      if N >= 0 and N <= Dernier_Service then
         Par_Service (N) := Par_Service (N) + 1;
      end if;
   end Service;

   procedure Booleen_Non_Normalise (PC, V : Unsigned_64) is
   begin
      Nb_Booleens := Nb_Booleens + 1;
      for K in 1 .. Nb_Signales loop
         if Sig_PC (K) = PC then
            Sig_Nb (K) := Sig_Nb (K) + 1;
            return;
         end if;
      end loop;
      if Nb_Signales < Max_Signales then
         Nb_Signales := Nb_Signales + 1;
         Sig_PC (Nb_Signales) := PC;
         Sig_Val (Nb_Signales) := V;
         Sig_Nb (Nb_Signales) := 1;
      end if;
   end Booleen_Non_Normalise;

   procedure Decalage_Hors_Mot is
   begin
      Nb_Decalages := Nb_Decalages + 1;
   end Decalage_Hors_Mot;

   procedure Champ_Limite is
   begin
      Nb_Champs := Nb_Champs + 1;
   end Champ_Limite;

   function Total return Compteur is
   begin
      return Nb_Instr;
   end Total;

   ---------------------------------------------------------------- rapport

   procedure Ecrire (S : String) is
   begin
      if Vers_Fichier then
         Text_IO.Put_Line (Sortie, S);
      else
         Text_IO.Put_Line (Text_IO.Standard_Error, S);
      end if;
   end Ecrire;

   function Cadre (S : String; Largeur : Natural) return String is
   begin
      if S'Length >= Largeur then
         return S;
      else
         declare
            Blancs : constant String (1 .. Largeur - S'Length) := (others => ' ');
         begin
            return Blancs & S;
         end;
      end if;
   end Cadre;

   function Nombre (N : Compteur; Largeur : Natural := 12) return String is
   begin
      return Cadre (Image (Signe (N)), Largeur);
   end Nombre;

   --  pourcentage avec une decimale, calcul entier
   function Pourcent (N, Sur : Compteur) return String is
      P : Signe;
   begin
      if Sur = 0 then
         return "     -  ";
      end if;
      P := (Signe (N) * 1000 + Signe (Sur) / 2) / Signe (Sur);
      return Cadre (Image (P / 10) & "." & Image (P mod 10), 6) & " %";
   end Pourcent;

   --  rapport a deux decimales
   function Ratio (N, Sur : Compteur) return String is
      P : Signe;
      D : Signe;
   begin
      if Sur = 0 then
         return "-";
      end if;
      P := (Signe (N) * 100 + Signe (Sur) / 2) / Signe (Sur);
      D := P mod 100;
      if D < 10 then
         return Image (P / 100) & ".0" & Image (D);
      else
         return Image (P / 100) & "." & Image (D);
      end if;
   end Ratio;

   procedure Ligne (Titre : String; N : Compteur; Sur : Compteur) is
   begin
      Ecrire ("  " & Titre & Nombre (N) & "  " & Pourcent (N, Sur));
   end Ligne;

   --  somme des paires (A, B) avec A dans De_A .. De_B et B dans Vers_A .. Vers_B
   function Somme (De_A, De_B, Vers_A, Vers_B : Integer) return Compteur is
      S : Compteur := 0;
   begin
      for A in De_A .. De_B loop
         for B in Vers_A .. Vers_B loop
            S := S + Paires (A, B);
         end loop;
      end loop;
      return S;
   end Somme;

   procedure Rapport_Paires is
      Nb_Rangs : constant := 30;
      Deja : array (0 .. Dernier_Code, 0 .. Dernier_Code) of Boolean :=
        (others => (others => False));
      Max_A, Max_B : Integer;
      Cumul : Compteur := 0;
      Comp_Branche, Retour, Imm_Binaire, Imm_Rangement : Compteur;
   begin
      Ecrire ("PAIRES ADJACENTES LES PLUS FREQUENTES   (part des instructions executees)");
      for Rang in 1 .. Nb_Rangs loop
         Max_A := 0;
         Max_B := 0;                                -- Paires (0, 0) reste nul
         for A in 1 .. Dernier_Code loop
            for B in 1 .. Dernier_Code loop
               if not Deja (A, B) and then Paires (A, B) > Paires (Max_A, Max_B) then
                  Max_A := A;
                  Max_B := B;
               end if;
            end loop;
         end loop;
         exit when Paires (Max_A, Max_B) = 0;
         Deja (Max_A, Max_B) := True;
         Cumul := Cumul + Paires (Max_A, Max_B);
         Ecrire ("  " & Cadre (Image (Rang), 3) & "  " & Noms (Max_A) & " " & Noms (Max_B)
                 & Nombre (Paires (Max_A, Max_B)) & "  " & Pourcent (Paires (Max_A, Max_B), Nb_Instr)
                 & "   cumul " & Pourcent (Cumul, Nb_Instr));
      end loop;
      Ecrire ("");

      --  familles candidates ; une fusion retire une instruction et un octet du flux OP
      Comp_Branche := Somme (OP_CEQ, OP_FCLE, OP_BT, OP_BF);
      Retour       := Somme (OP_UNLINK, OP_UNLINKR, OP_RTD, OP_RTD);
      Imm_Binaire  := Somme (OP_LI, OP_LI, OP_ET, OP_OU)
                    + Somme (OP_LI, OP_LI, OP_OUX, OP_OUX)
                    + Somme (OP_LI, OP_LI, OP_SHL, OP_SAR)
                    + Somme (OP_LI, OP_LI, OP_ADD, OP_SUB)
                    + Somme (OP_LI, OP_LI, OP_MUL, OP_MODI)
                    + Somme (OP_LI, OP_LI, OP_CEQ, OP_CLE);
      Imm_Rangement := Somme (OP_LI, OP_LI, OP_SB, OP_SA)
                     + Somme (OP_LI, OP_LI, OP_SIB, OP_SIA);
      Ecrire ("FUSIONS CANDIDATES          (instructions et octets OP economises)");
      Ligne ("comparaison + BT/BF                ", Comp_Branche, Nb_Instr);
      Ligne ("UNLINK/UNLINKR + RTD               ", Retour, Nb_Instr);
      Ligne ("LI + operation binaire             ", Imm_Binaire, Nb_Instr);
      Ligne ("LI + rangement de constante        ", Imm_Rangement, Nb_Instr);
      Ligne ("CALL/CALLI -> LINK a la cible      ", Appel_Link, Nb_Instr);
      Ecrire ("  (les familles peuvent se chevaucher : LI CGT BT compte deux fois ;");
      Ecrire ("   CALL -> LINK n'est pas adjacent : fusion a la prise de l'appel)");
      Ecrire ("  paires adjacentes observees       " & Nombre (Nb_Paires)
              & "  " & Pourcent (Nb_Paires, Nb_Instr));
      Ecrire ("");
   end Rapport_Paires;

   procedure Rapport_Mesures is
      Instr_Idiome, Economie : Compteur;
   begin
      Instr_Idiome := 8 * Chk_Complets + 4 * Chk_Demi;
      Economie := 7 * Chk_Complets + 3 * Chk_Demi;
      Ecrire ("CONTROLES D'INTERVALLE   (DUP / borne / CLT|CLE|CGT|CGE / BT)");
      Ecrire ("  controles complets (deux bornes)   " & Nombre (Chk_Complets));
      Ligne ("  dont bornes voisines en memoire  ", Chk_Adjacents, Chk_Complets);
      Ligne ("  dont bornes immediates (LI, LI)  ", Chk_Immediats, Chk_Complets);
      Ecrire ("  bornes voisines : instruction qui lit la 1re borne");
      for Code in 1 .. Dernier_Code loop
         if Chk_Par_Op (Code) > 0 then
            Ligne ("    " & Noms (Code) & "                     ", Chk_Par_Op (Code), Chk_Adjacents);
         end if;
      end loop;
      Ligne ("  LST = FST + taille, FST d'abord  ", Chk_Ordre_Normal, Chk_Adjacents);
      Ligne ("  LST d'abord (ecart = -taille)    ", Chk_Ordre_Inverse, Chk_Adjacents);
      Ligne ("  autre ecart                      ", Chk_Autre_Ecart, Chk_Adjacents);
      Ligne ("  CLT sur FST puis CGT sur LST     ", Chk_Clt_Cgt, Chk_Adjacents);
      Ligne ("  deux BT vers la meme cible       ", Chk_Meme_Cible, Chk_Adjacents);
      Ecrire ("    cible de reference " & Hexa (Cible_Chk));
      Ecrire ("  demi-controles (une borne)         " & Nombre (Chk_Demi));
      Ligne ("instructions de l'idiome           ", Instr_Idiome, Nb_Instr);
      Ligne ("instructions economisees par CHK   ", Economie, Nb_Instr);
      Ligne ("octets ARG de l'idiome             ", Chk_Octets_Idiome, Octets_Arg);
      Ligne ("octets ARG estimes avec CHK        ", Chk_Octets_Chk, Octets_Arg);
      Ligne ("octets ARG economises              ", Chk_Octets_Idiome - Chk_Octets_Chk, Octets_Arg);
      Ecrire ("  (CHK sans cible : exception par vecteur ; bornes voisines lues par un seul acces)");
      Ecrire ("");
      Ecrire ("REDUCTIONS PAR PEEPHOLE   (adresse consommee aussitot au sommet, lvl = -1)");
      Ligne ("LVA l,d + acces B  -> acces B (l)   ", Lva_B, Nb_Instr);
      Ligne ("LVA l,d + acces C  -> acces C (l)   ", Lva_C, Nb_Instr);
      Ligne ("LA  l,d + acces B  -> acces C (l,d) ", La_B, Nb_Instr);
      Ligne ("LA  l,d + acces C  (irreductible)   ", La_C, Nb_Instr);
      Ecrire ("");
      Ecrire ("BRANCHEMENTS CONDITIONNELS");
      Ligne ("BT/BF pris                         ", Pris, Pris + Non_Pris);
      Ligne ("BT/BF non pris                     ", Non_Pris, Pris + Non_Pris);
      Ecrire ("");
   end Rapport_Mesures;

   procedure Rapport_Champs is
      Noms_Bf : constant array (0 .. 2) of String (1 .. 5) := ("UBFX ", "SBFX ", "BFI  ");
      Nb_Rangs : constant := 12;
      Vu : array (0 .. 2, 0 .. 63, 1 .. 64) of Boolean := (others => (others => (others => False)));
      Imm, Etroit, Arg_LI, Total_Bf : Compteur := 0;
      Mk, Ml, Mw : Integer;

      procedure Bilan_Arg (Titre : String; Retires, Ajoutes : Compteur) is
      begin
         if Retires >= Ajoutes then
            Ecrire ("  " & Titre & Nombre (Retires - Ajoutes) & "  "
                    & Pourcent (Retires - Ajoutes, Octets_Arg) & " economises");
         else
            Ecrire ("  " & Titre & Nombre (Ajoutes - Retires) & "  "
                    & Pourcent (Ajoutes - Retires, Octets_Arg) & " ajoutes");
         end if;
      end Bilan_Arg;

   begin
      Ecrire ("CHAMPS DE BITS   (lsb et w fournis par LI, LI juste avant)");
      Ecrire ("               executions     lsb, w immediats      charge etroite / champ aligne");
      for K in 0 .. 2 loop
         Total_Bf := Total_Bf + Par_Code (OP_UBFX + K);
         Ecrire ("  " & Noms_Bf (K) & Nombre (Par_Code (OP_UBFX + K), 15)
                 & Nombre (Bf_Imm (K), 15) & "  " & Pourcent (Bf_Imm (K), Par_Code (OP_UBFX + K))
                 & Nombre (Bf_Etroit (K), 15) & "  " & Pourcent (Bf_Etroit (K), Par_Code (OP_UBFX + K)));
         Imm := Imm + Bf_Imm (K);
         Etroit := Etroit + Bf_Etroit (K);
         Arg_LI := Arg_LI + Bf_Arg_LI (K);
      end loop;
      Ecrire ("  (BFI : champ aligne sur l'octet, rangement etroit a verifier sur le code)");
      Ligne ("instr. economisees : UBFXI/SBFXI/BFII", 2 * Imm, Nb_Instr);
      Ligne ("  avec charges etroites (3 par cas) ", 2 * Imm + Etroit, Nb_Instr);
      --  forme immediate : deux LI remplaces par un complement D16 de 2 octets ;
      --  charge etroite : les deux LI disparaissent, la charge garde son complement
      Bilan_Arg ("octets ARG, formes immediates      ", Arg_LI, 2 * Imm);
      Bilan_Arg ("  avec charges etroites            ", Arg_LI, 2 * (Imm - Etroit));
      Ecrire ("  couples (lsb, w) les plus frequents");
      for Rang in 1 .. Nb_Rangs loop
         Mk := -1;
         Ml := 0;
         Mw := 1;
         for K in 0 .. 2 loop
            for L in 0 .. 63 loop
               for W in 1 .. 64 loop
                  if not Vu (K, L, W) and then Couples (K, L, W) > 0
                    and then (Mk < 0 or else Couples (K, L, W) > Couples (Mk, Ml, Mw)) then
                     Mk := K;
                     Ml := L;
                     Mw := W;
                  end if;
               end loop;
            end loop;
         end loop;
         exit when Mk < 0;
         Vu (Mk, Ml, Mw) := True;
         Ecrire ("    " & Noms_Bf (Mk) & Cadre (Image (Ml), 3) & "," & Cadre (Image (Mw), 3)
                 & Nombre (Couples (Mk, Ml, Mw), 15) & "  " & Pourcent (Couples (Mk, Ml, Mw), Total_Bf));
      end loop;
      Ecrire ("");
   end Rapport_Champs;

   procedure Rapport (Nom_Fichier : String) is
      Nb_B, Nb_C, Nb_LI, Nb_BR, Nb_Acces : Compteur;
      Noms_Services : constant array (0 .. Dernier_Service) of String (1 .. 14) :=
        ("EXIT          ", "CLOCK_GETTIME ", "PUT_CHAR      ", "PUT_STR       ",
         "GET_CHAR      ", "GET_STR       ", "FILE_CREATE   ", "FILE_OPEN     ",
         "FILE_SET_POS  ", "FILE_GET_POS  ", "FILE_GET_SIZE ", "FILE_WRITE    ",
         "FILE_READ     ", "FILE_CLOSE    ", "FILE_DELETE   ");
   begin
      if Nom_Fichier'Length > 0 then
         Text_IO.Create (Sortie, Text_IO.Out_File, Nom_Fichier);
         Vers_Fichier := True;
      end if;

      Ecrire ("========================================================================");
      Ecrire ("TLALOC  --  TX_RUN : profil dynamique d'execution LLIR");
      Ecrire ("========================================================================");
      Ecrire ("");
      Ecrire ("instructions executees                : " & Nombre (Nb_Instr));
      if Image_HX then
         Ecrire ("image HX (codi_HX) : mesures exactes");
         Ecrire ("  instructions LLIR representees      : " & Nombre (Instructions_LLIR));
         Ecrire ("  octets de code HX lus               : " & Nombre (Octets_HX));
         Ecrire ("  octets HX par instruction HX        : " & Cadre (Ratio (Octets_HX, Nb_Instr), 12));
         Ecrire ("  (les formats et flux ci-dessous restent les estimations du modele TX)");
      end if;
      Ecrire ("flux des opcodes       (octets)       : " & Nombre (Nb_Instr));
      Ecrire ("flux des arguments     (octets)       : " & Nombre (Octets_Arg));
      Ecrire ("octets de code lus par instruction    : " & Cadre (Ratio (Nb_Instr + Octets_Arg, Nb_Instr), 12));
      Ecrire ("");
      Ecrire ("profondeurs maximales atteintes");
      Ecrire ("  pile data            (octets)       : " & Nombre (Compteur (Max_Pile_Octets)));
      Ecrire ("  pile des retours     (adresses)     : " & Nombre (Compteur (Max_Retours)));
      Ecrire ("  co-pile              (octets)       : " & Nombre (Compteur (Max_Copile_Octets)));
      Ecrire ("  tas                  (octets)       : " & Nombre (Compteur (Max_Tas_Octets)));
      Ecrire ("  niveau statique le plus profond     : " & Nombre (Compteur (Max_Niveau)));
      Ecrire ("");

      Nb_B := B_A + B16 + B24 + B_Hors;
      Nb_C := C_A + C24 + C32 + C_Hors;
      Nb_LI := LI4 + LI8 + LI16 + LI32 + LI64;
      Nb_BR := BR16 + BR32 + BR48 + BR64;
      Ecrire ("FORMATS (LLIR_hardware_support), en instructions executees");
      Ecrire ("  famille B        A (sans complement)" & Nombre (B_A) & "  " & Pourcent (B_A, Nb_B));
      Ecrire ("                   B16                " & Nombre (B16) & "  " & Pourcent (B16, Nb_B));
      Ecrire ("                   B24                " & Nombre (B24) & "  " & Pourcent (B24, Nb_B));
      Ecrire ("                   hors format        " & Nombre (B_Hors) & "  " & Pourcent (B_Hors, Nb_B));
      Ecrire ("  famille C        A (sans complement)" & Nombre (C_A) & "  " & Pourcent (C_A, Nb_C));
      Ecrire ("                   C24                " & Nombre (C24) & "  " & Pourcent (C24, Nb_C));
      Ecrire ("                   C32                " & Nombre (C32) & "  " & Pourcent (C32, Nb_C));
      Ecrire ("                   hors format        " & Nombre (C_Hors) & "  " & Pourcent (C_Hors, Nb_C));
      Ecrire ("  immediats        imm4 (0..15)       " & Nombre (LI4) & "  " & Pourcent (LI4, Nb_LI));
      Ecrire ("                   imm8               " & Nombre (LI8) & "  " & Pourcent (LI8, Nb_LI));
      Ecrire ("                   imm16              " & Nombre (LI16) & "  " & Pourcent (LI16, Nb_LI));
      Ecrire ("                   imm32              " & Nombre (LI32) & "  " & Pourcent (LI32, Nb_LI));
      Ecrire ("                   imm64              " & Nombre (LI64) & "  " & Pourcent (LI64, Nb_LI));
      if Image_HX then
         Ecrire ("  branches (HX)    BR8                " & Nombre (BR16) & "  " & Pourcent (BR16, Nb_BR));
         Ecrire ("                   BR16               " & Nombre (BR32) & "  " & Pourcent (BR32, Nb_BR));
         Ecrire ("                   BR24               " & Nombre (BR48) & "  " & Pourcent (BR48, Nb_BR));
         Ecrire ("                   BR32               " & Nombre (BR64) & "  " & Pourcent (BR64, Nb_BR));
      else
      Ecrire ("  branches (estim.) BR16              " & Nombre (BR16) & "  " & Pourcent (BR16, Nb_BR));
      Ecrire ("                   BR32               " & Nombre (BR32) & "  " & Pourcent (BR32, Nb_BR));
      Ecrire ("                   BR48               " & Nombre (BR48) & "  " & Pourcent (BR48, Nb_BR));
      Ecrire ("                   BR64               " & Nombre (BR64) & "  " & Pourcent (BR64, Nb_BR));
      Ecrire ("  (branches : ecart ARG estime au double de l'ecart OP)");
      end if;
      Ecrire ("  controles CHK      B24             " & Nombre (CHK_B24));
      Ecrire ("                     C32             " & Nombre (CHK_C32));
      Ecrire ("                     hors format     " & Nombre (CHK_Hors));
      Ecrire ("");

      Nb_Acces := Acces_Pile + Acces_Local + Acces_Global + Acces_Englobant;
      Ecrire ("ACCES MEMOIRE DES FAMILLES B ET C");
      Ligne ("adresse sur la pile (lvl = -1)     ", Acces_Pile, Nb_Acces);
      Ligne ("niveau courant                     ", Acces_Local, Nb_Acces);
      Ligne ("niveau 0 (global)                  ", Acces_Global, Nb_Acces);
      Ligne ("niveau englobant intermediaire     ", Acces_Englobant, Nb_Acces);
      for L in Par_Niveau'Range loop
         if Par_Niveau (L) > 0 then
            Ligne ("  lvl " & Cadre (Image (L), 2) & "                           ",
                   Par_Niveau (L), Nb_Acces);
         end if;
      end loop;
      Ecrire ("");

      Ecrire ("SERVICES TRAP");
      for S in Par_Service'Range loop
         if Par_Service (S) > 0 then
            Ecrire ("  " & Noms_Services (S) & Nombre (Par_Service (S)));
         end if;
      end loop;
      Ecrire ("");

      Ecrire ("DIAGNOSTICS");
      Ecrire ("  BT/BF sur valeur hors {0,1}         : " & Nombre (Nb_Booleens));
      for K in 1 .. Nb_Signales loop
         if (Sig_Val (K) and 16#FF#) = 0 then
            Ecrire ("      PC " & Hexa (Sig_PC (K)) & "  1re valeur " & Hexa (Sig_Val (K))
                    & Nombre (Sig_Nb (K)) & " fois   <- octet bas nul : x86 ne brancherait pas");
         else
            Ecrire ("      PC " & Hexa (Sig_PC (K)) & "  1re valeur " & Hexa (Sig_Val (K))
                    & Nombre (Sig_Nb (K)) & " fois");
         end if;
      end loop;
      Ecrire ("  decalages de 64 positions ou plus   : " & Nombre (Nb_Decalages));
      Ecrire ("  champs de bits de largeur 0 ou 64   : " & Nombre (Nb_Champs));
      Ecrire ("");

      Rapport_Paires;
      Rapport_Mesures;
      if Limites.Actif then
         Limites.Rapport (Sortie, Vers_Fichier);
      end if;
      if Frontal.Actif then
         Frontal.Rapport (Sortie, Vers_Fichier);
      end if;
      Rapport_Champs;

      Ecrire ("HISTOGRAMME DYNAMIQUE   code / executions / part / octets d'arguments");
      for Op in 1 .. Dernier_Code loop
         if Par_Code (Op) > 0 then
            Ecrire ("  " & Noms (Op) & Nombre (Par_Code (Op)) & "  "
                    & Pourcent (Par_Code (Op), Nb_Instr) & Nombre (Arg_Par_Code (Op)));
         end if;
      end loop;

      if Vers_Fichier then
         Text_IO.Close (Sortie);
      end if;
   end Rapport;

end Profil;
