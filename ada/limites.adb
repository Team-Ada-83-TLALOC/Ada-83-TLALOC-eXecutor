with Mots; use Mots;
with TX_Codes; use TX_Codes;
package body Limites is

   pragma Suppress (Index_Check);
   pragma Suppress (Range_Check);
   pragma Suppress (Overflow_Check);

   ------------------------------------------------------------------ modeles

   G_M3   : constant := 3;
   G_M6   : constant := 6;
   G_M6RE : constant := 9;

   type Modele is range 1 .. 17;
   Genre   : constant array (Modele) of Integer :=
     (G_M3, G_M3, G_M6, G_M6, G_M6RE, G_M6RE, G_M6RE, G_M6RE, G_M6RE, G_M6RE,
      G_M6RE, G_M6RE, G_M6RE, G_M6RE, G_M6RE, G_M6RE, G_M6RE);
   Fenetre : constant array (Modele) of Unsigned_64 :=
     (64, 256, 64, 256, 64, 256, 64, 256, 64, 256,
      128, 128, 256, 128, 256, 128, 256);
   Largeur : constant array (Modele) of Unsigned_64 :=      -- 0 : illimitee
     (0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      0, 4, 4, 6, 6, 8, 8);
   Tranche : constant array (Modele) of Integer :=           -- 0 : illimitee, 1 : 128, 2 : 64
     (0, 0, 0, 0, 0, 0, 1, 1, 2, 2,
      1, 1, 1, 1, 1, 1, 1);
   Taille_Tranche : constant array (0 .. 2) of Unsigned_64 := (Unsigned_64'Last, 128, 64);

   Anneau : constant := 256;                         -- >= plus grande fenetre et largeur
   Dernier_Anneau : constant := 255;
   Fin_Instr, Retrait_Instr, Lance_Instr : array (Modele, 0 .. Dernier_Anneau) of Unsigned_64 :=
     (others => (others => 0));
   Max_Fin, Dernier_Retrait, Dernier_Lance, Barriere_T, Controle_T, Ind_Store_Debut :
     array (Modele) of Unsigned_64 := (others => 0);
   T_M0 : Unsigned_64 := 0;
   N    : Unsigned_64 := 0;                          -- numero de l'instruction courante

   ------------------------------------------------------------------ predicteurs

   Penalite : constant := 10;
   Bits_Histoire : constant := 16;
   Taille_Gshare : constant := 65536;
   Dernier_Gshare : constant := 65535;
   Gshare   : array (0 .. Dernier_Gshare) of Unsigned_8 := (others => 1);
   Histoire : Unsigned_64 := 0;
   Profondeur_RAS : constant := 32;
   Dernier_RAS    : constant := 31;
   RAS      : array (0 .. Dernier_RAS) of Unsigned_64 := (others => 0);
   Haut_RAS : Integer := 0;
   Dernier_BTB : constant := 4095;
   BTB      : array (0 .. Dernier_BTB) of Unsigned_64 := (others => 0);

   ------------------------------------------------------------------ suivi des mots

   Dernier_Mot   : constant := 511;                  -- pages de 4 Kio
   type Suivi is record
      Ecrivain : Unsigned_64 := 0;                   -- 0 : jamais ecrit
      Classe   : Classe_Acces := Pile;
   end record;
   type Page is array (0 .. Dernier_Mot) of Suivi;
   type Acces_Page is access Page;

   Taille_Table  : constant := 65536;
   Derniere_Case : constant := 65535;
   Cles  : array (0 .. Derniere_Case) of Unsigned_64 := (others => 0);  -- page + 1
   Pages : array (0 .. Derniere_Case) of Acces_Page;
   Nb_Pages : Natural := 0;
   Derniere_Cle, Avant_Derniere_Cle : Unsigned_64 := 0;
   Derniere_Page, Avant_Derniere_Page, Poubelle : Acces_Page;
   Table_Pleine : Boolean := False;

   ------------------------------------------------------------------ frames et variables exposees

   Max_Frames : constant := 4096;
   Frame_FP   : array (1 .. Max_Frames) of Unsigned_64 := (others => 0);   -- croissants
   Frame_PC   : array (1 .. Max_Frames) of Unsigned_64 := (others => 0);   -- adresse du LINK
   Nb_Frames  : Natural := 0;

   Taille_Exp  : constant := 1048576;                 -- ensemble des variables exposees
   Dernier_Exp : constant := 1048575;
   Exposees    : array (0 .. Dernier_Exp) of Unsigned_64 := (others => 0);
   Nb_Exposees : Natural := 0;
   Exp_Pleine  : Boolean := False;

   ------------------------------------------------------------------ instruction courante

   Capacite : constant := 256;
   L_Mot    : array (1 .. Capacite) of Unsigned_64;
   L_Sens   : array (1 .. Capacite) of Sens_Acces;
   L_Classe : array (1 .. Capacite) of Classe_Acces;
   L_Adr    : array (1 .. Capacite) of Boolean;       -- lecture qui fournit une adresse
   L_Local  : array (1 .. Capacite) of Boolean;       -- acces direct au niveau courant
   L_Prof   : array (1 .. Capacite) of Unsigned_64;   -- mots sous le sommet (locales)
   DSP_Courant : Unsigned_64 := 0;
   L_Page   : array (1 .. Capacite) of Acces_Page;
   L_Index  : array (1 .. Capacite) of Natural;
   Nb_Acces : Natural := 0;
   Prod     : array (1 .. Capacite) of Integer := (others => 0);   -- producteurs dans l'anneau
   Adr_Prod : array (1 .. Capacite) of Integer := (others => 0);   -- producteurs d'adresses
   Serialise, Enregistrer, Prochain_Adr, Local_Actif : Boolean := False;

   ------------------------------------------------------------------ statistiques

   type Compteur is range 0 .. 2**62;
   Lectures, Ecritures : array (Classe_Acces) of Compteur := (others => 0);
   Alias_ID, Alias_DI : Compteur := 0;
   Lect_Dir, Lect_Loc, Lect_Loc_Libre : Compteur := 0;
   Bornes_Prof : constant array (1 .. 7) of Unsigned_64 := (16, 32, 64, 128, 256, 512, Unsigned_64'Last);
   Prof_Loc, Prof_Libre : array (1 .. 7) of Compteur := (others => 0);
   Nb_Serialisees, Nb_Debordements : Compteur := 0;
   Nb_Cond, Err_Cond, Nb_Ret, Err_Ret, Nb_Ind, Err_Ind, Nb_Exc : Compteur := 0;

   ------------------------------------------------------------------

   function Max (A, B : Unsigned_64) return Unsigned_64 is
   begin
      if A > B then
         return A;
      end if;
      return B;
   end Max;
   pragma Inline (Max);

   function Trouver (Mot : Unsigned_64) return Acces_Page is
      Cle : constant Unsigned_64 := Shift_Right (Mot, 9) + 1;
      H   : Natural;
      P   : Acces_Page;
   begin
      if Cle = Derniere_Cle then
         return Derniere_Page;
      elsif Cle = Avant_Derniere_Cle then
         Avant_Derniere_Cle := Derniere_Cle;
         Derniere_Cle := Cle;
         P := Avant_Derniere_Page;
         Avant_Derniere_Page := Derniere_Page;
         Derniere_Page := P;
         return P;
      end if;
      H := Natural ((Cle * 16#9E37_79B9#) and Derniere_Case);
      loop
         if Cles (H) = Cle then
            exit;
         elsif Cles (H) = 0 then
            if Nb_Pages >= Taille_Table * 3 / 4 then   -- table saturee : mesure degradee
               Table_Pleine := True;
               if Poubelle = null then
                  Poubelle := new Page;
               end if;
               return Poubelle;
            end if;
            Cles (H) := Cle;
            Pages (H) := new Page;
            Nb_Pages := Nb_Pages + 1;
            exit;
         end if;
         H := (H + 1) mod Taille_Table;
      end loop;
      Avant_Derniere_Cle := Derniere_Cle;
      Avant_Derniere_Page := Derniere_Page;
      Derniere_Cle := Cle;
      Derniere_Page := Pages (H);
      return Pages (H);
   end Trouver;

   function Latence (Op : Integer) return Unsigned_64 is
   begin
      case Op is
         when OP_LB .. OP_ULD | OP_CHKB .. OP_CHKUD           => return 3;   -- une charge
         when OP_LIB .. OP_ULID | OP_CHKIB .. OP_CHKUID       => return 6;   -- deux charges
         when OP_LIVA                                         => return 4;
         when OP_MUL | OP_FADD | OP_FSUB | OP_CVTIF | OP_CVTFI | OP_CVTFIR
            | OP_FCEQ .. OP_FCLE                               => return 3;
         when OP_FMUL                                         => return 4;
         when OP_FDIV                                         => return 15;
         when OP_DIV | OP_REMI | OP_MODI | OP_CVTIX | OP_CVTXI | OP_FEXP => return 20;
         when others                                          => return 1;
      end case;
   end Latence;

   --  latence quand la lecture locale est un registre renomme : la charge disparait
   function Latence_Renommee (Op : Integer; Lat : Unsigned_64) return Unsigned_64 is
   begin
      case Op is
         when OP_LB .. OP_ULD | OP_CHKB .. OP_CHKUD               => return 1;
         when OP_LIB .. OP_ULID | OP_CHKIB .. OP_CHKUID | OP_LIVA => return Lat - 2;
         when others                                              => return Lat;
      end case;
   end Latence_Renommee;

   ------------------------------------------------------------------ interface

   procedure Debut is
   begin
      Nb_Acces := 0;
      Serialise := False;
      Enregistrer := True;
      Local_Actif := False;
      Prochain_Adr := False;
   end Debut;

   procedure Ajouter (Mot : Unsigned_64; Sens : Sens_Acces; Classe : Classe_Acces;
                      Adr : Boolean) is
      Loc : constant Boolean := Local_Actif and Classe = Directe;
   begin
      if Nb_Acces > 0 and then L_Mot (Nb_Acces) = Mot and then L_Sens (Nb_Acces) = Sens
        and then L_Classe (Nb_Acces) = Classe and then L_Adr (Nb_Acces) = Adr
        and then L_Local (Nb_Acces) = Loc then
         return;                                      -- meme mot : octets successifs
      end if;
      if Nb_Acces = Capacite then
         Serialise := True;                           -- trop de mots : instruction serialisante
         Enregistrer := False;
         Nb_Debordements := Nb_Debordements + 1;
         return;
      end if;
      Nb_Acces := Nb_Acces + 1;
      L_Mot (Nb_Acces) := Mot;
      L_Sens (Nb_Acces) := Sens;
      L_Classe (Nb_Acces) := Classe;
      L_Adr (Nb_Acces) := Adr;
      L_Local (Nb_Acces) := Loc;
      if Loc then
         L_Prof (Nb_Acces) := Shift_Right (DSP_Courant, 3) - Mot;   -- 0 : cellule du sommet
      end if;
   end Ajouter;

   procedure Acces (A, Taille : Unsigned_64; Sens : Sens_Acces; Classe : Classe_Acces) is
      Premier, Dernier, M : Unsigned_64;
      Adr : constant Boolean := Prochain_Adr;
   begin
      Prochain_Adr := False;
      if not Enregistrer or Taille = 0 then
         return;
      end if;
      Premier := Shift_Right (A, 3);
      Dernier := Shift_Right (A + Taille - 1, 3);
      M := Premier;
      loop
         Ajouter (M, Sens, Classe, Adr);
         exit when M = Dernier or not Enregistrer;
         M := M + 1;
      end loop;
   end Acces;

   procedure Registre (R : Registre_Machine; Sens : Sens_Acces) is
   begin
      if Enregistrer then                              -- mots 2 et 3 : page 0, hors memoire
         Ajouter (Unsigned_64 (Registre_Machine'Pos (R) + 2), Sens, Pile, False);
      end if;
   end Registre;

   procedure Barriere is
   begin
      Serialise := True;
      Enregistrer := False;
   end Barriere;

   procedure Adresse_Suivante is
   begin
      Prochain_Adr := True;
   end Adresse_Suivante;

   procedure Marquer_Local (Local : Boolean; DSP : Unsigned_64) is
   begin
      Local_Actif := Local;
      DSP_Courant := DSP;
   end Marquer_Local;

   procedure Lien (FP, PC_Link : Unsigned_64) is
   begin
      if Nb_Frames < Max_Frames then
         Nb_Frames := Nb_Frames + 1;
         Frame_FP (Nb_Frames) := FP;
         Frame_PC (Nb_Frames) := PC_Link;
      end if;
   end Lien;

   procedure Delien is
   begin
      if Nb_Frames > 0 then
         Nb_Frames := Nb_Frames - 1;
      end if;
   end Delien;

   procedure Retablir (DSP : Unsigned_64) is
   begin
      while Nb_Frames > 0 and then Frame_FP (Nb_Frames) > DSP loop
         Nb_Frames := Nb_Frames - 1;
      end loop;
   end Retablir;

   --  identite statique d'une variable : (LINK de sa procedure, deplacement en mots)
   function Cle_Variable (PC_Link, FP, Mot : Unsigned_64) return Unsigned_64 is
   begin
      return (Shift_Left (PC_Link, 20) xor ((Mot - Shift_Right (FP, 3)) and 16#F_FFFF#)) + 1;
   end Cle_Variable;

   function Indice_Exp (Cle : Unsigned_64) return Natural is
   begin
      return Natural ((Cle * 16#9E37_79B9#) and Dernier_Exp);
   end Indice_Exp;

   function Est_Exposee (Cle : Unsigned_64) return Boolean is
      H : Natural := Indice_Exp (Cle);
   begin
      loop
         if Exposees (H) = Cle then
            return True;
         elsif Exposees (H) = 0 then
            return False;
         end if;
         H := (H + 1) mod Taille_Exp;
      end loop;
   end Est_Exposee;

   procedure Exposer (Cle : Unsigned_64) is
      H : Natural := Indice_Exp (Cle);
   begin
      loop
         if Exposees (H) = Cle then
            return;
         elsif Exposees (H) = 0 then
            if Nb_Exposees >= Taille_Exp * 3 / 4 then
               Exp_Pleine := True;
               return;
            end if;
            Exposees (H) := Cle;
            Nb_Exposees := Nb_Exposees + 1;
            return;
         end if;
         H := (H + 1) mod Taille_Exp;
      end loop;
   end Exposer;

   --  acces par pointeur a un mot : si le mot est dans un frame actif, la variable
   --  est exposee ; on marque le frame qui le contient (deplacement >= 0) et le
   --  suivant (le mot peut etre un de ses parametres, deplacement < 0)
   procedure Exposer_Mot (Mot : Unsigned_64) is
      A : constant Unsigned_64 := Shift_Left (Mot, 3);
      Bas, Haut, Milieu : Natural;
   begin
      if Nb_Frames = 0 or else A < Frame_FP (1) then
         return;                                      -- hors de la pile des frames
      end if;
      Bas := 1;                                       -- dernier frame de FP <= A
      Haut := Nb_Frames;
      while Bas < Haut loop
         Milieu := (Bas + Haut + 1) / 2;
         if Frame_FP (Milieu) <= A then
            Bas := Milieu;
         else
            Haut := Milieu - 1;
         end if;
      end loop;
      Exposer (Cle_Variable (Frame_PC (Bas), Frame_FP (Bas), Mot));
      if Bas < Nb_Frames then
         Exposer (Cle_Variable (Frame_PC (Bas + 1), Frame_FP (Bas + 1), Mot));
      end if;
   end Exposer_Mot;

   --  Predit le transfert de controle de l'instruction et met les predicteurs a jour.
   function Mal_Predit (Op : Integer; PC, Suivant : Unsigned_64) return Boolean is
      Sequentiel : constant Unsigned_64 := PC + 16;
      I : Natural;
      Pris, Erreur : Boolean := False;
   begin
      case Op is
         when OP_BT | OP_BF =>
            Nb_Cond := Nb_Cond + 1;
            Pris := Suivant /= Sequentiel;
            I := Natural ((Shift_Right (PC, 4) xor Histoire) and Dernier_Gshare);
            Erreur := (Gshare (I) >= 2) /= Pris;
            if Pris and Gshare (I) < 3 then
               Gshare (I) := Gshare (I) + 1;
            elsif not Pris and Gshare (I) > 0 then
               Gshare (I) := Gshare (I) - 1;
            end if;
            Histoire := Shift_Left (Histoire, 1) and Dernier_Gshare;
            if Pris then
               Histoire := Histoire or 1;
            end if;
            if Erreur then
               Err_Cond := Err_Cond + 1;
            end if;
         when OP_CALL | OP_CALLI =>
            if Op = OP_CALLI then
               Nb_Ind := Nb_Ind + 1;
               I := Natural (Shift_Right (PC, 4) and Dernier_BTB);
               Erreur := BTB (I) /= Suivant;
               BTB (I) := Suivant;
               if Erreur then
                  Err_Ind := Err_Ind + 1;
               end if;
            end if;
            RAS (Haut_RAS) := Sequentiel;
            Haut_RAS := (Haut_RAS + 1) mod Profondeur_RAS;
         when OP_RTD =>
            Nb_Ret := Nb_Ret + 1;
            Haut_RAS := (Haut_RAS + Dernier_RAS) mod Profondeur_RAS;
            Erreur := RAS (Haut_RAS) /= Suivant;
            if Erreur then
               Err_Ret := Err_Ret + 1;
            end if;
         when OP_EXC_RAISE =>
            Nb_Exc := Nb_Exc + 1;
            Erreur := True;
         when others =>
            null;                                   -- BRA, CALL : cible connue au decodage
      end case;
      return Erreur;
   end Mal_Predit;

   procedure Fin (Op : Integer; PC, Suivant : Unsigned_64) is
      Lat : Unsigned_64 := Latence (Op);
      Lat_M : Unsigned_64;
      D, F, E, R, L, W, D_Adr : Unsigned_64;
      P : Acces_Page;
      K : Natural;
      Kp : Integer;
      Case_N : Integer;
      Nb_Prod, Nb_Adr : Natural := 0;
      --  resume de l'instruction, calcule une fois pour tous les modeles
      Lit_Ind, Lit_Dir, Ecr_Ind : Boolean := False;
      Hors_Renomme : array (0 .. 2) of Boolean := (others => False);   -- par tranche
      Renomme_Lu   : array (0 .. 2) of Boolean := (others => False);
      Lat_T        : array (0 .. 2) of Unsigned_64;
      Exposee      : Boolean;
      Erreur : constant Boolean := Mal_Predit (Op, PC, Suivant);
      Attend : Boolean;
   begin
      N := N + 1;
      Case_N := Integer (N mod Anneau);
      if Op >= OP_BLKMOV and Op <= OP_LEXCMP then
         Lat := Lat + Unsigned_64 (Nb_Acces / 2);     -- blocs : deux mots par cycle
      end if;
      T_M0 := T_M0 + Lat;
      if Serialise then
         Nb_Serialisees := Nb_Serialisees + 1;
      end if;

      for I in 1 .. Nb_Acces loop                       -- une seule recherche par mot
         P := Trouver (L_Mot (I));
         K := Integer (L_Mot (I) and Dernier_Mot);
         L_Page (I) := P;
         L_Index (I) := K;
         if L_Sens (I) = Lecture then
            E := P (K).Ecrivain;
            if E > 0 and then N - E < Anneau then       -- producteur encore dans l'anneau
               Kp := Integer (E mod Anneau);
               if L_Adr (I) then
                  Nb_Adr := Nb_Adr + 1;
                  Adr_Prod (Nb_Adr) := Kp;
               end if;
               for J in 1 .. Nb_Prod loop
                  if Prod (J) = Kp then
                     Kp := -1;
                     exit;
                  end if;
               end loop;
               if Kp >= 0 then
                  Nb_Prod := Nb_Prod + 1;
                  Prod (Nb_Prod) := Kp;
               end if;
            end if;
            case L_Classe (I) is
               when Pile => null;
               when Directe =>
                  Lit_Dir := True;
                  Lect_Dir := Lect_Dir + 1;
                  if L_Local (I) then
                     Lect_Loc := Lect_Loc + 1;
                     Exposee := Nb_Frames > 0 and then Est_Exposee
                       (Cle_Variable (Frame_PC (Nb_Frames), Frame_FP (Nb_Frames), L_Mot (I)));
                     for B in Bornes_Prof'Range loop
                        if L_Prof (I) < Bornes_Prof (B) then
                           Prof_Loc (B) := Prof_Loc (B) + 1;
                           if not Exposee then
                              Prof_Libre (B) := Prof_Libre (B) + 1;
                           end if;
                           exit;
                        end if;
                     end loop;
                     if not Exposee then
                        Lect_Loc_Libre := Lect_Loc_Libre + 1;
                     end if;
                     for T in 0 .. 2 loop                -- renommee dans cette tranche ?
                        if not Exposee and then L_Prof (I) < Taille_Tranche (T) then
                           Renomme_Lu (T) := True;
                        else
                           Hors_Renomme (T) := True;
                        end if;
                     end loop;
                  else
                     for T in 0 .. 2 loop
                        Hors_Renomme (T) := True;
                     end loop;
                  end if;
               when Indirecte => Lit_Ind := True;
            end case;
         elsif L_Classe (I) = Indirecte then
            Ecr_Ind := True;
         end if;
      end loop;
      for T in 0 .. 2 loop
         if Renomme_Lu (T) then
            Lat_T (T) := Latence_Renommee (Op, Lat);
         else
            Lat_T (T) := Lat;
         end if;
      end loop;

      for M in Modele loop
         --  lancement : dans l'ordre, fenetre, largeur, reprise apres erreur
         D := Max (Dernier_Lance (M), Max (Controle_T (M), Barriere_T (M)));
         W := Fenetre (M);
         L := Largeur (M);
         if N > W then
            D := Max (D, Retrait_Instr (M, Integer ((N - W) mod Anneau)));
         end if;
         if L > 0 and then N > L then
            D := Max (D, Lance_Instr (M, Integer ((N - L) mod Anneau)) + 1);
         end if;
         if Serialise then
            D := Max (D, Max_Fin (M));
         end if;
         Lance_Instr (M, Case_N) := D;
         Dernier_Lance (M) := D;

         --  adresse connue (pour un rangement indirect : partie STA)
         D_Adr := D;
         for J in 1 .. Nb_Adr loop
            D_Adr := Max (D_Adr, Fin_Instr (M, Adr_Prod (J)));
         end loop;
         --  vraies dependances, dans tous les modeles
         for J in 1 .. Nb_Prod loop
            D := Max (D, Fin_Instr (M, Prod (J)));
         end loop;
         --  attente des adresses des rangements indirects plus anciens
         case Genre (M) is
            when G_M6   => Attend := Lit_Ind or Lit_Dir;
            when G_M6RE => Attend := Lit_Ind or Hors_Renomme (Tranche (M));
            when others => Attend := False;
         end case;
         if Attend then
            D := Max (D, Ind_Store_Debut (M));
         end if;
         if Genre (M) = G_M6RE then
            Lat_M := Lat_T (Tranche (M));
         else
            Lat_M := Lat;
         end if;

         F := D + Lat_M;
         if Ecr_Ind then
            Ind_Store_Debut (M) := Max (Ind_Store_Debut (M), D_Adr);
         end if;
         Fin_Instr (M, Case_N) := F;
         R := Max (F, Dernier_Retrait (M));
         if L > 0 and then N > L then
            R := Max (R, Retrait_Instr (M, Integer ((N - L) mod Anneau)) + 1);
         end if;
         Retrait_Instr (M, Case_N) := R;
         Dernier_Retrait (M) := R;
         Max_Fin (M) := Max (Max_Fin (M), R);
         if Serialise then
            Barriere_T (M) := F;
         end if;
         if Erreur then
            Controle_T (M) := Max (Controle_T (M), F + Penalite);   -- le chargement repart
         end if;
      end loop;

      --  ecrivains et statistiques, apres le calcul des dates
      for I in 1 .. Nb_Acces loop
         P := L_Page (I);
         K := L_Index (I);
         if L_Classe (I) = Indirecte then
            Exposer_Mot (L_Mot (I));
         end if;
         if L_Sens (I) = Lecture then
            Lectures (L_Classe (I)) := Lectures (L_Classe (I)) + 1;
            if P (K).Ecrivain > 0 then
               if L_Classe (I) = Indirecte and P (K).Classe = Directe then
                  Alias_ID := Alias_ID + 1;
               elsif L_Classe (I) = Directe and P (K).Classe = Indirecte then
                  Alias_DI := Alias_DI + 1;
               end if;
            end if;
         else
            Ecritures (L_Classe (I)) := Ecritures (L_Classe (I)) + 1;
            P (K).Ecrivain := N;
            P (K).Classe := L_Classe (I);
         end if;
      end loop;
   end Fin;

   ------------------------------------------------------------------ rapport

   procedure Rapport (Sortie : in out Text_IO.File_Type; Vers_Fichier : Boolean) is

      Total_L, Total_E : Compteur := 0;

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

      function Nombre (V : Unsigned_64) return String is
      begin
         return Cadre (Image (Vers_Signe (V)), 14);
      end Nombre;

      function Deux_Decimales (P : Signe) return String is
      begin
         if P mod 100 < 10 then
            return Image (P / 100) & ".0" & Image (P mod 100);
         end if;
         return Image (P / 100) & "." & Image (P mod 100);
      end Deux_Decimales;

      function IPC (Cycles : Unsigned_64) return String is
      begin
         if Cycles = 0 then
            return Cadre ("-", 9);
         end if;
         return Cadre (Deux_Decimales ((Vers_Signe (N) * 100 + Vers_Signe (Cycles) / 2)
                                       / Vers_Signe (Cycles)), 9);
      end IPC;

      function Pour_Mille (V : Compteur) return String is
      begin
         if N = 0 then
            return "-";
         end if;
         return Deux_Decimales ((Signe (V) * 100000 + Vers_Signe (N) / 2) / Vers_Signe (N));
      end Pour_Mille;

      function Part (V, Sur : Compteur) return String is
         P : Signe;
      begin
         if Sur = 0 then
            return "     -  ";
         end if;
         P := (Signe (V) * 1000 + Signe (Sur) / 2) / Signe (Sur);
         return Cadre (Image (P / 10) & "." & Image (P mod 10), 6) & " %";
      end Part;

      procedure Ligne (Titre : String; M : Modele) is
      begin
         Ecrire ("  " & Titre & Cadre (Image (Vers_Signe (Fenetre (M))), 7)
                 & Nombre (Max_Fin (M)) & IPC (Max_Fin (M)));
      end Ligne;

   begin
      Ecrire ("LIMITES DE PARALLELISME   (prediction realiste ; emission illimitee sauf tableau des largeurs)");
      Ecrire ("  latences : ALU 1, charge 3, charge indirecte 6, MUL 3, division 20, flottants 3 a 15");
      Ecrire ("  modele                                      fenetre        cycles       IPC");
      Ecrire ("  M0   machine a pile sequentielle                  -" & Nombre (T_M0) & IPC (T_M0));
      Ligne ("M3   oracle memoire (reference)            ", 1);
      Ligne ("                                           ", 2);
      Ligne ("M6   LSQ, (lvl, disp) connus au decodage   ", 3);
      Ligne ("                                           ", 4);
      Ligne ("M6re + locales non exposees renommees      ", 5);
      Ligne ("                                           ", 6);
      Ligne ("     tranche de pile de 128 mots           ", 7);
      Ligne ("                                           ", 8);
      Ligne ("     tranche de pile de 64 mots            ", 9);
      Ligne ("                                           ", 10);
      Ecrire ("");
      Ecrire ("  M6re, tranche de 128 mots, a largeur finie (L lancees et retirees par cycle) : IPC");
      Ecrire ("         largeur    fenetre 64   fenetre 128   fenetre 256");
      for I in 0 .. 2 loop
         Ecrire ("  " & Cadre (Image (Vers_Signe (Largeur (Modele (12 + 2 * I)))), 14)
                 & Cadre ("-", 14)
                 & Cadre (IPC (Max_Fin (Modele (12 + 2 * I))), 14)
                 & Cadre (IPC (Max_Fin (Modele (13 + 2 * I))), 14));
      end loop;
      Ecrire ("      illimitee" & Cadre (IPC (Max_Fin (7)), 14) & Cadre (IPC (Max_Fin (11)), 14)
              & Cadre (IPC (Max_Fin (8)), 14));
      Ecrire ("");
      Ecrire ("  prediction : gshare " & Image (Signe (Taille_Gshare)) & " compteurs, histoire "
              & Image (Signe (Bits_Histoire)) & " bits ; pile des retours " & Image (Signe (Profondeur_RAS))
              & " ; derniere cible ; penalite " & Image (Signe (Penalite)) & " cycles");
      Ecrire ("  branchements conditionnels      " & Cadre (Image (Signe (Nb_Cond)), 14)
              & "   mal predits " & Cadre (Image (Signe (Err_Cond)), 12) & Part (Err_Cond, Nb_Cond)
              & "   pour 1000 instr. " & Pour_Mille (Err_Cond));
      Ecrire ("  retours                         " & Cadre (Image (Signe (Nb_Ret)), 14)
              & "   mal predits " & Cadre (Image (Signe (Err_Ret)), 12) & Part (Err_Ret, Nb_Ret));
      Ecrire ("  appels indirects                " & Cadre (Image (Signe (Nb_Ind)), 14)
              & "   mal predits " & Cadre (Image (Signe (Err_Ind)), 12) & Part (Err_Ind, Nb_Ind));
      Ecrire ("  exceptions levees (EXC_RAISE)   " & Cadre (Image (Signe (Nb_Exc)), 14));
      for C in Classe_Acces loop
         Total_L := Total_L + Lectures (C);
         Total_E := Total_E + Ecritures (C);
      end loop;
      Ecrire ("  mots lus      pile " & Part (Lectures (Pile), Total_L)
              & "   directs " & Part (Lectures (Directe), Total_L)
              & "   indirects " & Part (Lectures (Indirecte), Total_L));
      Ecrire ("  mots ecrits   pile " & Part (Ecritures (Pile), Total_E)
              & "   directs " & Part (Ecritures (Directe), Total_E)
              & "   indirects " & Part (Ecritures (Indirecte), Total_E));
      Ecrire ("  lectures directes                " & Cadre (Image (Signe (Lect_Dir)), 13)
              & "   dont au niveau courant " & Cadre (Image (Signe (Lect_Loc)), 13)
              & Part (Lect_Loc, Lect_Dir));
      Ecrire ("  lectures locales de variables non exposees           "
              & Cadre (Image (Signe (Lect_Loc_Libre)), 14) & Part (Lect_Loc_Libre, Lect_Loc));
      Ecrire ("  variables locales exposees (procedure, deplacement)  "
              & Cadre (Image (Signe (Nb_Exposees)), 14));
      Ecrire ("  lectures locales selon la profondeur sous le sommet (mots)   toutes     non exposees");
      for B in Bornes_Prof'Range loop
         if B < Bornes_Prof'Last then
            Ecrire ("    moins de " & Cadre (Image (Vers_Signe (Bornes_Prof (B))), 4) & "                         "
                    & Cadre (Image (Signe (Prof_Loc (B))), 14) & Part (Prof_Loc (B), Lect_Loc)
                    & Cadre (Image (Signe (Prof_Libre (B))), 14) & Part (Prof_Libre (B), Lect_Loc_Libre));
         else
            Ecrire ("    au-dela                              "
                    & Cadre (Image (Signe (Prof_Loc (B))), 14) & Part (Prof_Loc (B), Lect_Loc)
                    & Cadre (Image (Signe (Prof_Libre (B))), 14) & Part (Prof_Libre (B), Lect_Loc_Libre));
         end if;
      end loop;
      if Exp_Pleine then
         Ecrire ("  ATTENTION : table des variables exposees saturee");
      end if;
      Ecrire ("  alias : lecture indirecte d'un mot ecrit en direct   "
              & Cadre (Image (Signe (Alias_ID)), 14));
      Ecrire ("          lecture directe d'un mot ecrit en indirect   "
              & Cadre (Image (Signe (Alias_DI)), 14));
      Ecrire ("  instructions serialisantes (TRAP, EXC_RAISE, blocs)  "
              & Cadre (Image (Signe (Nb_Serialisees)), 14)
              & "   dont blocs > 256 mots " & Image (Signe (Nb_Debordements)));
      Ecrire ("  pages suivies (4 Kio)                                "
              & Cadre (Image (Signe (Nb_Pages)), 14));
      if Table_Pleine then
         Ecrire ("  ATTENTION : table des pages saturee, mesure approchee");
      end if;
      Ecrire ("");
   end Rapport;

end Limites;
