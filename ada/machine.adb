with Memoire; use Memoire;
with TX_Codes; use TX_Codes;
with Profil;
with Hote;
with Limites;
with Frontal;
package body Machine is

   Nb_Niveaux  : constant := 15;             -- DISPLAY[0..14]
   Dernier_Niveau : constant := 14;
   Max_Retours : constant := 200_000;
   Masque_32   : constant Unsigned_64 := 16#FFFF_FFFF#;

   --  Etat architectural
   PC, DSP, CFP, CSP, HP : Unsigned_64 := 0;
   RSP     : Natural := 0;
   Display : array (0 .. Dernier_Niveau) of Unsigned_64 := (others => 0);
   Retours : array (1 .. Max_Retours) of Unsigned_64;

   --  Pour le profil : niveau statique du frame actif, indexe par profondeur d'appel
   Niveau_De : array (0 .. Max_Retours) of Integer := (others => 0);

   Avec_Profil : Boolean := False;
   Avec_Limites : Boolean := False;
   Classe_Courante : Limites.Classe_Acces := Limites.Indirecte;   -- acces explicite en cours
   Limite_Instr : Signe := 0;
   Nb_Executees : Signe := 0;
   Code_Final   : Integer := 0;
   Fini         : Boolean := False;
   Op_Courant   : Integer := 0;
   Limite_Pile  : Unsigned_64 := 0;          -- Fin_Pile - 8, fixe au chargement
   Max_DSP      : Unsigned_64 := 0;          -- plus haut sommet atteint (pour le profil)
   CEV          : Unsigned_64 := 0;          -- vecteur CONSTRAINT_ERROR des CHK

   Borne_64 : constant Long_Float := 9.223372036854775808E18;     -- 2**63
   Indefini : constant Unsigned_64 := Bit_63;                      -- « integer indefinite » x86

   ---------------------------------------------------------------- acces memoire observes
   --  Ces enveloppes masquent celles de Memoire dans tout le corps (et dans Trap) :
   --  chaque acces explicite est signale a Limites avec la classe courante.

   function Lire_8 (A : Unsigned_64) return Unsigned_64 is
   begin
      if Avec_Limites then
         Limites.Acces (A, 1, Limites.Lecture, Classe_Courante);
      end if;
      return Memoire.Lire_8 (A);
   end Lire_8;

   function Lire_16 (A : Unsigned_64) return Unsigned_64 is
   begin
      if Avec_Limites then
         Limites.Acces (A, 2, Limites.Lecture, Classe_Courante);
      end if;
      return Memoire.Lire_16 (A);
   end Lire_16;

   function Lire_32 (A : Unsigned_64) return Unsigned_64 is
   begin
      if Avec_Limites then
         Limites.Acces (A, 4, Limites.Lecture, Classe_Courante);
      end if;
      return Memoire.Lire_32 (A);
   end Lire_32;

   function Lire_64 (A : Unsigned_64) return Unsigned_64 is
   begin
      if Avec_Limites then
         Limites.Acces (A, 8, Limites.Lecture, Classe_Courante);
      end if;
      return Memoire.Lire_64 (A);
   end Lire_64;

   procedure Ecrire_8 (A : Unsigned_64; V : Unsigned_64) is
   begin
      if Avec_Limites then
         Limites.Acces (A, 1, Limites.Ecriture, Classe_Courante);
      end if;
      Memoire.Ecrire_8 (A, V);
   end Ecrire_8;

   procedure Ecrire_16 (A : Unsigned_64; V : Unsigned_64) is
   begin
      if Avec_Limites then
         Limites.Acces (A, 2, Limites.Ecriture, Classe_Courante);
      end if;
      Memoire.Ecrire_16 (A, V);
   end Ecrire_16;

   procedure Ecrire_32 (A : Unsigned_64; V : Unsigned_64) is
   begin
      if Avec_Limites then
         Limites.Acces (A, 4, Limites.Ecriture, Classe_Courante);
      end if;
      Memoire.Ecrire_32 (A, V);
   end Ecrire_32;

   procedure Ecrire_64 (A : Unsigned_64; V : Unsigned_64) is
   begin
      if Avec_Limites then
         Limites.Acces (A, 8, Limites.Ecriture, Classe_Courante);
      end if;
      Memoire.Ecrire_64 (A, V);
   end Ecrire_64;
   pragma Inline (Lire_8, Lire_16, Lire_32, Lire_64, Ecrire_8, Ecrire_16, Ecrire_32, Ecrire_64);

   ---------------------------------------------------------------- pile data

   procedure Empiler (V : Unsigned_64) is
   begin
      if DSP >= Limite_Pile then
         Signaler ("debordement de la pile data");
      end if;
      DSP := DSP + 8;
      Ecrire_Pile (DSP, V);
      if Avec_Limites then
         Limites.Acces (DSP, 8, Limites.Ecriture, Limites.Pile);
      end if;
      if DSP > Max_DSP then
         Max_DSP := DSP;
      end if;
   end Empiler;

   function Depiler return Unsigned_64 is
      V : Unsigned_64;
   begin
      if DSP <= Base_Pile then
         Signaler ("pile data vide");
      end if;
      V := Lire_Pile (DSP);
      if Avec_Limites then
         Limites.Acces (DSP, 8, Limites.Lecture, Limites.Pile);
      end if;
      DSP := DSP - 8;
      return V;
   end Depiler;

   function Sommet return Unsigned_64 is
   begin
      if Avec_Limites then
         Limites.Acces (DSP, 8, Limites.Lecture, Limites.Pile);
      end if;
      return Lire_Pile (DSP);
   end Sommet;

   procedure Remplacer_Sommet (V : Unsigned_64) is
   begin
      if Avec_Limites then
         Limites.Acces (DSP, 8, Limites.Ecriture, Limites.Pile);
      end if;
      Ecrire_Pile (DSP, V);
   end Remplacer_Sommet;
   pragma Inline (Empiler, Depiler, Sommet, Remplacer_Sommet);

   ---------------------------------------------------------------- pile des retours

   procedure Empiler_Retour (A : Unsigned_64) is
   begin
      if RSP = Max_Retours then
         Signaler ("debordement de la pile des retours");
      end if;
      RSP := RSP + 1;
      Retours (RSP) := A;
      Niveau_De (RSP) := Niveau_De (RSP - 1);
      if RSP > Profil.Max_Retours then
         Profil.Max_Retours := RSP;
      end if;
   end Empiler_Retour;

   function Depiler_Retour return Unsigned_64 is
   begin
      if RSP = 0 then
         Signaler ("retour avec une pile des retours vide");
      end if;
      RSP := RSP - 1;
      return Retours (RSP + 1);
   end Depiler_Retour;

   ---------------------------------------------------------------- utilitaires

   procedure Verifier_Niveau (Lvl : Integer) is
   begin
      if Lvl < 0 or Lvl >= Nb_Niveaux then
         Signaler ("niveau statique hors du display : " & Image (Lvl));
      end if;
   end Verifier_Niveau;
   pragma Inline (Verifier_Niveau);

   function Booleen (B : Boolean) return Unsigned_64 is
   begin
      if B then
         return 1;
      else
         return 0;
      end if;
   end Booleen;

   function Etendre_8 (V : Unsigned_64) return Unsigned_64 is
   begin
      if V >= 16#80# then
         return V or 16#FFFF_FFFF_FFFF_FF00#;
      end if;
      return V;
   end Etendre_8;

   function Etendre_16 (V : Unsigned_64) return Unsigned_64 is
   begin
      if V >= 16#8000# then
         return V or 16#FFFF_FFFF_FFFF_0000#;
      end if;
      return V;
   end Etendre_16;

   function Etendre_32 (V : Unsigned_64) return Unsigned_64 is
   begin
      if V >= 16#8000_0000# then
         return V or 16#FFFF_FFFF_0000_0000#;
      end if;
      return V;
   end Etendre_32;
   pragma Inline (Booleen, Etendre_8, Etendre_16, Etendre_32);

   function Arrondi_8 (N : Unsigned_64) return Unsigned_64 is   -- 8 * ((n + 7) sar 3)
   begin
      return Shift_Left (Shift_Right_Arithmetic (N + 7, 3), 3);
   end Arrondi_8;

   function Masque (Largeur : Unsigned_64) return Unsigned_64 is
   begin
      if Largeur = 0 or Largeur >= 64 then
         Profil.Champ_Limite;
      end if;
      if Largeur = 0 then
         return 0;
      elsif Largeur >= 64 then
         return 16#FFFF_FFFF_FFFF_FFFF#;
      end if;
      return Shift_Left (1, Natural (Largeur)) - 1;
   end Masque;

   function Compte_Decalage (N : Unsigned_64) return Natural is
   begin
      if N >= 64 then
         Profil.Decalage_Hors_Mot;
      end if;
      return Natural (N and 63);                    -- modulo 64, comme la reference [Q6]
   end Compte_Decalage;

   function Abs_Mot (S : Signe) return Unsigned_64 is
   begin
      if S < 0 then
         return 0 - Vers_Mot (S);
      end if;
      return Vers_Mot (S);
   end Abs_Mot;

   --  Produit 64 x 64 -> 128 bits non signe
   procedure Mul_128 (X, Y : Unsigned_64; Haut, Bas : out Unsigned_64) is
      X0 : constant Unsigned_64 := X and Masque_32;
      X1 : constant Unsigned_64 := Shift_Right (X, 32);
      Y0 : constant Unsigned_64 := Y and Masque_32;
      Y1 : constant Unsigned_64 := Shift_Right (Y, 32);
      P00 : constant Unsigned_64 := X0 * Y0;
      P01 : constant Unsigned_64 := X0 * Y1;
      P10 : constant Unsigned_64 := X1 * Y0;
      P11 : constant Unsigned_64 := X1 * Y1;
      Milieu : constant Unsigned_64 :=
        Shift_Right (P00, 32) + (P01 and Masque_32) + (P10 and Masque_32);
   begin
      Bas  := (P00 and Masque_32) or Shift_Left (Milieu, 32);
      Haut := P11 + Shift_Right (P01, 32) + Shift_Right (P10, 32) + Shift_Right (Milieu, 32);
   end Mul_128;

   --  Division 128 / 64 non signee, par restauration
   procedure Div_128 (Haut, Bas, D : Unsigned_64;
                      Q_Haut, Q_Bas, Reste : out Unsigned_64) is
      R, QH, QL, Bit : Unsigned_64 := 0;
      Retenue : Boolean;
   begin
      for I in reverse 0 .. 127 loop
         if I >= 64 then
            Bit := Shift_Right (Haut, I - 64) and 1;
         else
            Bit := Shift_Right (Bas, I) and 1;
         end if;
         Retenue := (R and Bit_63) /= 0;
         R := Shift_Left (R, 1) or Bit;
         if Retenue or else R >= D then
            R := R - D;
            if I >= 64 then
               QH := QH or Shift_Left (1, I - 64);
            else
               QL := QL or Shift_Left (1, I);
            end if;
         end if;
      end loop;
      Q_Haut := QH;
      Q_Bas := QL;
      Reste := R;
   end Div_128;

   --  (A * B) / C avec produit intermediaire sur 128 bits, comme imul puis idiv
   procedure Mul_Div (A, B, C : Signe; Q, R : out Signe) is
      Negatif_P : constant Boolean := (A < 0) /= (B < 0);
      Negatif_Q : constant Boolean := Negatif_P /= (C < 0);
      Haut, Bas, QH, QL, Reste : Unsigned_64;
   begin
      if C = 0 then
         Signaler ("division par zero dans une conversion virgule fixe");
      end if;
      Mul_128 (Abs_Mot (A), Abs_Mot (B), Haut, Bas);
      Div_128 (Haut, Bas, Abs_Mot (C), QH, QL, Reste);
      if QH /= 0 or else QL > Bit_63 or else (QL = Bit_63 and not Negatif_Q) then
         Signaler ("depassement de quotient dans une conversion virgule fixe");
      end if;
      if Negatif_Q then
         Q := Vers_Signe (0 - QL);
      else
         Q := Vers_Signe (QL);
      end if;
      if Negatif_P then
         R := Vers_Signe (0 - Reste);
      else
         R := Vers_Signe (Reste);
      end if;
   end Mul_Div;

   ---------------------------------------------------------------- flottants


   function Tronquer (F : Long_Float) return Unsigned_64 is
      T : Signe;
   begin
      if not (F >= -Borne_64 and F < Borne_64) then    -- hors bornes ou NaN
         return Indefini;
      end if;
      T := Signe (F);                                   -- au plus proche
      if F >= 0.0 and then Long_Float (T) > F then
         T := T - 1;
      elsif F < 0.0 and then Long_Float (T) < F then
         T := T + 1;
      end if;
      return Vers_Mot (T);
   end Tronquer;

   function Arrondir (F : Long_Float) return Unsigned_64 is
   begin
      if not (F > -Borne_64 - 0.5 and F < Borne_64 - 0.5) then
         return Indefini;
      end if;
      return Vers_Mot (Signe (F));                       -- mi-chemin a l'ecart de zero
   end Arrondir;

   ---------------------------------------------------------------- appels systeme

   procedure Trap (Service : Integer; Code : Unsigned_64) is separate;

   ---------------------------------------------------------------- interface

   procedure Initialiser (Profiler : Boolean; Limite : Signe; Mesurer_Limites : Boolean) is
   begin
      Avec_Limites := Mesurer_Limites;
      Limites.Actif := Mesurer_Limites;
      Avec_Profil := Profiler;
      Limite_Instr := Limite;
      PC := Entree;
      DSP := Base_Pile;                         -- DSP designe le sommet ; cellule 0 factice
      Limite_Pile := Fin_Pile - 8;
      CEV := Vecteur_CE;
      Max_DSP := DSP;
      Display := (others => 0);
      Display (0) := Base_Pile;
      CSP := Debut_Copile;                      -- premier « frame » de co-pile
      Ecrire_64 (CSP, CSP);
      CFP := CSP;
      CSP := CSP + 8;
      HP := Fin_Tas;
      RSP := 0;
      Nb_Executees := 0;
      Fini := False;
   end Initialiser;

   function Code_De_Sortie return Integer is
   begin
      return Code_Final;
   end Code_De_Sortie;

   function PC_Courant return Unsigned_64 is
   begin
      return PC;
   end PC_Courant;

   function Code_Courant return Integer is
   begin
      return Op_Courant;
   end Code_Courant;

   function Instructions_Executees return Signe is
   begin
      return Nb_Executees;
   end Instructions_Executees;

   ---------------------------------------------------------------- boucle d'execution

   procedure Executer is
      Op, Lvl : Integer;
      Ofs, Val, Suivant : Unsigned_64;
      A, B, V, W, L, N : Unsigned_64;
      SA, SB, Q, R : Signe;
      F, G : Long_Float;
      K : Integer;
      Taille_De : constant array (0 .. 6) of Unsigned_64 := (1, 2, 4, 8, 1, 2, 4);

      function Base_B return Unsigned_64 is       -- base d'un acces de famille B
      begin
         if Avec_Profil then
            Profil.Acces (Lvl, Niveau_De (RSP));
         end if;
         if Lvl = -1 then
            Classe_Courante := Limites.Indirecte;      -- adresse calculee
            if Avec_Limites then
               Limites.Adresse_Suivante;
            end if;
            return Depiler;
         end if;
         Verifier_Niveau (Lvl);
         Classe_Courante := Limites.Directe;          -- DISPLAY[lvl] + disp : connue au decodage
         if Avec_Limites then
            Limites.Marquer_Local (Lvl = Niveau_De (RSP), DSP);   -- locale du niveau courant ?
         end if;
         return Display (Lvl);
      end Base_B;

      function Adresse_C return Unsigned_64 is    -- adresse effective de famille C
         P : Unsigned_64;
      begin
         if Avec_Profil then
            Profil.Acces (Lvl, Niveau_De (RSP));
         end if;
         if Lvl = -1 then
            if Avec_Limites then
               Limites.Adresse_Suivante;
            end if;
            P := Depiler;
            Classe_Courante := Limites.Indirecte;
         else
            Verifier_Niveau (Lvl);
            P := Display (Lvl);
            Classe_Courante := Limites.Directe;       -- le pointeur est a une adresse directe
            if Avec_Limites then
               Limites.Marquer_Local (Lvl = Niveau_De (RSP), DSP);
            end if;
         end if;
         if Avec_Limites then
            Limites.Adresse_Suivante;                 -- le pointeur lu est l'adresse de l'element
         end if;
         P := Lire_64 (P + Val) + Ofs;
         Classe_Courante := Limites.Indirecte;        -- l'element designe ne l'est pas
         if Avec_Limites then
            Limites.Marquer_Local (False, DSP);
         end if;
         return P;
      end Adresse_C;

      procedure Operation_Bloc (Genre : Integer) is   -- ( @dst len @src -- )
         Src, Lg, Dst, K, X : Unsigned_64;
      begin
         Src := Depiler;
         Lg  := Depiler;
         if Avec_Limites then
            Limites.Adresse_Suivante;                 -- adresse de destination
         end if;
         Dst := Depiler;
         if Vers_Signe (Lg) < 0 then
            Signaler ("longueur de bloc negative");
         end if;
         K := 0;
         while K < Lg loop
            X := Lire_8 (Src + K);
            case Genre is
               when OP_BLKAND => X := X and Lire_8 (Dst + K);
               when OP_BLKOU  => X := X or Lire_8 (Dst + K);
               when others    => X := X xor Lire_8 (Dst + K);
            end case;
            Ecrire_8 (Dst + K, X);
            K := K + 1;
         end loop;
      end Operation_Bloc;

      function Composant (Adr : Unsigned_64) return Signe is   -- pour LEXCMP
      begin
         case Integer (Ofs) is
            when 1 =>
               if Lvl = 1 then
                  return Vers_Signe (Etendre_8 (Lire_8 (Adr)));
               end if;
               return Vers_Signe (Lire_8 (Adr));
            when 2 =>
               if Lvl = 1 then
                  return Vers_Signe (Etendre_16 (Lire_16 (Adr)));
               end if;
               return Vers_Signe (Lire_16 (Adr));
            when 4 =>
               if Lvl = 1 then
                  return Vers_Signe (Etendre_32 (Lire_32 (Adr)));
               end if;
               return Vers_Signe (Lire_32 (Adr));
            when others =>
               return Vers_Signe (Lire_64 (Adr));
         end case;
      end Composant;

      --  borne d'un CHK : K = 0 B, 1 W, 2 D, 3 Q, 4 UB, 5 UW, 6 UD
      function Borne (Adr : Unsigned_64; K : Integer) return Signe is
      begin
         case K is
            when 0      => return Vers_Signe (Etendre_8 (Lire_8 (Adr)));
            when 1      => return Vers_Signe (Etendre_16 (Lire_16 (Adr)));
            when 2      => return Vers_Signe (Etendre_32 (Lire_32 (Adr)));
            when 3      => return Vers_Signe (Lire_64 (Adr));
            when 4      => return Vers_Signe (Lire_8 (Adr));
            when 5      => return Vers_Signe (Lire_16 (Adr));
            when others => return Vers_Signe (Lire_32 (Adr));
         end case;
      end Borne;

   begin
      loop
         Lire_Instruction (PC, Op, Lvl, Ofs, Val);
         Op_Courant := Op;
         if Avec_Limites then
            Limites.Debut;
            Classe_Courante := Limites.Indirecte;
         end if;
         Nb_Executees := Nb_Executees + 1;
         if Limite_Instr > 0 and then Nb_Executees > Limite_Instr then
            Signaler ("limite du nombre d'instructions atteinte");
         end if;
         if Avec_Profil then
            Profil.Instruction (Op, Lvl, Ofs, Val, PC);
         end if;
         Suivant := PC + Taille_Enregistrement;

         case Op is

            ---------------------------------------------------- pile
            when OP_DROP =>
               V := Depiler;
            when OP_DUP =>
               Empiler (Sommet);
            when OP_OVER =>
               if Avec_Limites then
                  Limites.Acces (DSP - 8, 8, Limites.Lecture, Limites.Pile);
               end if;
               Empiler (Lire_Pile (DSP - 8));

            ---------------------------------------------------- immediats
            when OP_LI | OP_LIF | OP_LCA | OP_LSPA =>
               Empiler (Val);

            ---------------------------------------------------- adresses
            when OP_LVA =>
               Empiler (Base_B + Val);
            when OP_LIVA =>
               Empiler (Adresse_C);

            ---------------------------------------------------- chargements
            when OP_LB  => Empiler (Etendre_8  (Lire_8  (Base_B + Val)));
            when OP_LW  => Empiler (Etendre_16 (Lire_16 (Base_B + Val)));
            when OP_LD  => Empiler (Etendre_32 (Lire_32 (Base_B + Val)));
            when OP_LQ | OP_LA => Empiler (Lire_64 (Base_B + Val));
            when OP_ULB => Empiler (Lire_8  (Base_B + Val));
            when OP_ULW => Empiler (Lire_16 (Base_B + Val));
            when OP_ULD => Empiler (Lire_32 (Base_B + Val));

            when OP_LIB  => Empiler (Etendre_8  (Lire_8  (Adresse_C)));
            when OP_LIW  => Empiler (Etendre_16 (Lire_16 (Adresse_C)));
            when OP_LID  => Empiler (Etendre_32 (Lire_32 (Adresse_C)));
            when OP_LIQ | OP_LIA => Empiler (Lire_64 (Adresse_C));
            when OP_ULIB => Empiler (Lire_8  (Adresse_C));
            when OP_ULIW => Empiler (Lire_16 (Adresse_C));
            when OP_ULID => Empiler (Lire_32 (Adresse_C));

            ---------------------------------------------------- rangements : la donnee est au sommet
            when OP_SB => V := Depiler; Ecrire_8  (Base_B + Val, V);
            when OP_SW => V := Depiler; Ecrire_16 (Base_B + Val, V);
            when OP_SD => V := Depiler; Ecrire_32 (Base_B + Val, V);
            when OP_SQ | OP_SA => V := Depiler; Ecrire_64 (Base_B + Val, V);

            when OP_SIB => V := Depiler; Ecrire_8  (Adresse_C, V);
            when OP_SIW => V := Depiler; Ecrire_16 (Adresse_C, V);
            when OP_SID => V := Depiler; Ecrire_32 (Adresse_C, V);
            when OP_SIQ | OP_SIA => V := Depiler; Ecrire_64 (Adresse_C, V);

            ---------------------------------------------------- logique, decalages
            when OP_ET  => B := Depiler; Remplacer_Sommet (Sommet and B);
            when OP_OU  => B := Depiler; Remplacer_Sommet (Sommet or B);
            when OP_OUX => B := Depiler; Remplacer_Sommet (Sommet xor B);
            when OP_NON => Remplacer_Sommet (not Sommet);
            when OP_SHL =>
               B := Depiler;
               Remplacer_Sommet (Shift_Left (Sommet, Compte_Decalage (B)));
            when OP_SHR =>
               B := Depiler;
               Remplacer_Sommet (Shift_Right (Sommet, Compte_Decalage (B)));
            when OP_SAR =>
               B := Depiler;
               Remplacer_Sommet (Shift_Right_Arithmetic (Sommet, Compte_Decalage (B)));
            when OP_CLAMP0 =>
               if Vers_Signe (Sommet) < 0 then
                  Remplacer_Sommet (0);
               end if;

            ---------------------------------------------------- arithmetique entiere
            when OP_NEG => Remplacer_Sommet (0 - Sommet);
            when OP_ABS =>
               A := Sommet;
               V := Shift_Right_Arithmetic (A, 63);
               Remplacer_Sommet ((A xor V) - V);
            when OP_ADD => B := Depiler; Remplacer_Sommet (Sommet + B);
            when OP_SUB => B := Depiler; Remplacer_Sommet (Sommet - B);
            when OP_INC => Remplacer_Sommet (Sommet + 1);
            when OP_DEC => Remplacer_Sommet (Sommet - 1);
            when OP_MUL => B := Depiler; Remplacer_Sommet (Sommet * B);
            when OP_DIV | OP_REMI | OP_MODI =>
               SB := Vers_Signe (Depiler);
               SA := Vers_Signe (Sommet);
               if SB = 0 then
                  Signaler ("division entiere par zero");
               elsif SA = Signe'First and SB = -1 then
                  Signaler ("depassement de division entiere");
               end if;
               if Op = OP_DIV then
                  Remplacer_Sommet (Vers_Mot (SA / SB));
               elsif Op = OP_REMI then
                  Remplacer_Sommet (Vers_Mot (SA rem SB));
               else
                  Remplacer_Sommet (Vers_Mot (SA mod SB));
               end if;

            ---------------------------------------------------- champs de bits
            when OP_UBFX | OP_UBFXI =>        -- ( v lsb w -- champ ) ; UBFXI : ( v -- champ )
               if Op = OP_UBFX then
                  W := Depiler;
                  L := Depiler;
               else
                  W := Ofs;
                  L := Val;
               end if;
               Remplacer_Sommet (Shift_Right (Sommet, Compte_Decalage (L)) and Masque (W));
            when OP_SBFX | OP_SBFXI =>
               if Op = OP_SBFX then
                  W := Depiler;
                  L := Depiler;
               else
                  W := Ofs;
                  L := Val;
               end if;
               V := Shift_Right (Sommet, Compte_Decalage (L));
               if W = 0 then
                  Profil.Champ_Limite;
                  V := 0;
               elsif W >= 64 then
                  Profil.Champ_Limite;
               else
                  V := Shift_Right_Arithmetic (Shift_Left (V, Natural (64 - W)), Natural (64 - W));
               end if;
               Remplacer_Sommet (V);
            when OP_BFI | OP_BFII =>          -- ( old ins lsb w -- new ) ; BFII : ( old ins -- new )
               if Op = OP_BFI then
                  W := Depiler;
                  L := Depiler;
               else
                  W := Ofs;
                  L := Val;
               end if;
               V := Depiler;
               N := Unsigned_64 (Compte_Decalage (L));
               A := Masque (W);
               Remplacer_Sommet ((Sommet and not Shift_Left (A, Natural (N)))
                                 or Shift_Left (V and A, Natural (N)));

            ---------------------------------------------------- virgule fixe
            when OP_CVTIX =>                              -- ( i denom numer -- x )
               SB := Vers_Signe (Depiler);               -- NUMER
               SA := Vers_Signe (Depiler);               -- DENOM
               V  := Depiler;                            -- I
               Mul_Div (Vers_Signe (V), SA, SB, Q, R);
               Empiler (Vers_Mot (Q));
            when OP_CVTXI =>                              -- ( x numer denom -- i )
               B := Depiler;                             -- DENOM
               SA := Vers_Signe (Depiler);               -- NUMER
               V := Depiler;                             -- X
               Mul_Div (Vers_Signe (V), SA, Vers_Signe (B), Q, R);
               --  arrondi de la reference : |reste| >= ceil(denom / 2) (comparaison non signee)
               A := Shift_Right (B, 1) + (B and 1);
               if Abs_Mot (R) >= A then
                  if R < 0 then
                     Q := Q - 1;
                  else
                     Q := Q + 1;
                  end if;
               end if;
               Empiler (Vers_Mot (Q));

            ---------------------------------------------------- flottants
            when OP_FADD | OP_FSUB | OP_FMUL | OP_FDIV =>
               G := Vers_Reel (Depiler);
               F := Vers_Reel (Sommet);
               case Op is
                  when OP_FADD => F := F + G;
                  when OP_FSUB => F := F - G;
                  when OP_FMUL => F := F * G;
                  when others  => F := F / G;
               end case;
               Remplacer_Sommet (Depuis_Reel (F));
            when OP_FNEG => Remplacer_Sommet (Sommet xor Bit_63);
            when OP_FABS => Remplacer_Sommet (Sommet and not Bit_63);
            when OP_FEXP =>                               -- ( x n -- x**n )
               SB := Vers_Signe (Depiler);
               F := Vers_Reel (Sommet);
               G := 1.0;
               for K in 1 .. abs SB loop
                  G := G * F;
               end loop;
               if SB < 0 then                            -- Ada RM 4.5.6 [Q7]
                  G := 1.0 / G;
               end if;
               Remplacer_Sommet (Depuis_Reel (G));
            when OP_CVTIF =>
               Remplacer_Sommet (Depuis_Reel (Long_Float (Vers_Signe (Sommet))));
            when OP_CVTFI =>
               Remplacer_Sommet (Tronquer (Vers_Reel (Sommet)));
            when OP_CVTFIR =>
               Remplacer_Sommet (Arrondir (Vers_Reel (Sommet)));

            ---------------------------------------------------- comparaisons
            when OP_CEQ | OP_CNE | OP_CGT | OP_CGE | OP_CLT | OP_CLE =>
               SB := Vers_Signe (Depiler);
               SA := Vers_Signe (Sommet);
               case Op is
                  when OP_CEQ => V := Booleen (SA = SB);
                  when OP_CNE => V := Booleen (SA /= SB);
                  when OP_CGT => V := Booleen (SA > SB);
                  when OP_CGE => V := Booleen (SA >= SB);
                  when OP_CLT => V := Booleen (SA < SB);
                  when others => V := Booleen (SA <= SB);
               end case;
               Remplacer_Sommet (V);
            when OP_FCEQ | OP_FCNE | OP_FCGT | OP_FCGE | OP_FCLT | OP_FCLE =>
               G := Vers_Reel (Depiler);
               F := Vers_Reel (Sommet);
               case Op is
                  when OP_FCEQ => V := Booleen (F = G);
                  when OP_FCNE => V := Booleen (F /= G);      -- vrai si non ordonne
                  when OP_FCGT => V := Booleen (F > G);
                  when OP_FCGE => V := Booleen (F >= G);
                  when OP_FCLT => V := Booleen (F < G);
                  when others  => V := Booleen (F <= G);
               end case;
               Remplacer_Sommet (V);

            ---------------------------------------------------- controle
            when OP_BRA =>
               Suivant := Val;
            when OP_BT | OP_BF =>
               V := Depiler;
               if V > 1 and Avec_Profil then
                  Profil.Booleen_Non_Normalise (PC, V);
               end if;
               if (V /= 0) = (Op = OP_BT) then
                  Suivant := Val;
               end if;
            when OP_CALL =>
               Empiler_Retour (Suivant);
               Suivant := Val;
            when OP_CALLI =>
               A := Depiler;
               Empiler_Retour (Suivant);
               Suivant := A;
            when OP_RTD =>
               DSP := DSP - Val;
               Suivant := Depiler_Retour;

            ---------------------------------------------------- frames
            when OP_LINK =>
               Verifier_Niveau (Lvl);
               if Lvl > 0 then
                  Empiler (Display (Lvl));
                  Display (Lvl) := DSP;
               end if;
               if Arrondi_8 (Val) >= Fin_Pile - DSP then
                  Signaler ("debordement de la pile data (variables locales)");
               end if;
               DSP := DSP + Arrondi_8 (Val);
               if DSP > Max_DSP then
                  Max_DSP := DSP;
               end if;
               if CSP >= Fin_Copile - 8 then
                  Signaler ("co-pile epuisee");
               end if;
               Classe_Courante := Limites.Pile;             -- chainage de co-pile : pile materielle
               if Avec_Limites then
                  Limites.Registre (Limites.Reg_CSP, Limites.Lecture);
                  Limites.Registre (Limites.Reg_CSP, Limites.Ecriture);
               end if;
               Ecrire_64 (CSP, CFP);
               CFP := CSP;
               CSP := CSP + 8;
               Niveau_De (RSP) := Lvl;
               if Avec_Limites then
                  Limites.Lien (Display (Lvl), PC);          -- frame (FP, procedure)
               end if;
               if Lvl > Profil.Max_Niveau then
                  Profil.Max_Niveau := Lvl;
               end if;
            when OP_UNLINK | OP_UNLINKR =>
               if Lvl = 0 then
                  Signaler ("UNLINK 0 : LINK 0 n'a pas sauve de frame pointer");
               end if;
               Verifier_Niveau (Lvl);
               DSP := Display (Lvl);
               Display (Lvl) := Depiler;
               if Op = OP_UNLINKR then
                  CSP := CFP;
                  if Avec_Limites then
                     Limites.Registre (Limites.Reg_CSP, Limites.Ecriture);
                  end if;
               end if;
               Classe_Courante := Limites.Pile;
               CFP := Lire_64 (CFP);
               if Avec_Limites then
                  Limites.Delien;
               end if;

            ---------------------------------------------------- allocations
            when OP_CO_VAR =>                             -- ( n -- @bloc )
               N := Depiler;
               if Avec_Limites then
                  Limites.Registre (Limites.Reg_CSP, Limites.Lecture);
                  Limites.Registre (Limites.Reg_CSP, Limites.Ecriture);
               end if;
               Empiler (CSP);
               CSP := CSP + Arrondi_8 (N);
               if CSP > Fin_Copile or CSP < Debut_Copile then
                  Signaler ("co-pile epuisee");
               end if;
               if CSP - Debut_Copile > Profil.Max_Copile_Octets then
                  Profil.Max_Copile_Octets := CSP - Debut_Copile;
               end if;
            when OP_HEAP_ALLOC =>                         -- ( n -- @bloc )
               N := Arrondi_8 (Depiler);
               if Avec_Limites then
                  Limites.Registre (Limites.Reg_HP, Limites.Lecture);
                  Limites.Registre (Limites.Reg_HP, Limites.Ecriture);
               end if;
               if N > HP - Base_Tas then
                  Signaler ("tas epuise");
               end if;
               HP := HP - N;
               Empiler (HP);
               if Fin_Tas - HP > Profil.Max_Tas_Octets then
                  Profil.Max_Tas_Octets := Fin_Tas - HP;
               end if;

            ---------------------------------------------------- exceptions
            when OP_EXC_MACH =>
               Verifier_Niveau (Lvl);
               Classe_Courante := Limites.Directe;
               A := Display (Lvl) + Val;
               Ecrire_64 (A + 16, DSP);
               Ecrire_64 (A + 24, Unsigned_64 (RSP));
               Ecrire_64 (A + 32, CFP);
               Ecrire_64 (A + 40, CSP);
               Ecrire_64 (A + 48, Unsigned_64 (Lvl + 1));
               for I in 0 .. Lvl loop
                  Ecrire_64 (A + 56 + Unsigned_64 (8 * I), Display (I));
               end loop;
            when OP_EXC_RAISE =>
               if Avec_Limites then
                  Limites.Barriere;                         -- DSP, RSP et display recharges
               end if;
               A := Display (0) + Val;                   -- sommet de la pile des contextes
               B := Lire_64 (A);                         -- contexte
               Ecrire_64 (A, Lire_64 (B));               -- depiler avant dispatch
               CFP := Lire_64 (B + 32);
               CSP := Lire_64 (B + 40);
               V := Lire_64 (B + 24);
               if V > Unsigned_64 (Max_Retours) then
                  Signaler ("contexte d'exception corrompu (RSP)");
               end if;
               RSP := Natural (V);
               N := Lire_64 (B + 48);
               if N < 1 or N > Nb_Niveaux then
                  Signaler ("contexte d'exception corrompu (nombre de niveaux)");
               end if;
               for I in 0 .. Integer (N) - 1 loop
                  Display (I) := Lire_64 (B + 56 + Unsigned_64 (8 * I));
               end loop;
               DSP := Lire_64 (B + 16);
               Suivant := Lire_64 (B + 8);
               if Avec_Limites then
                  Limites.Retablir (DSP);
               end if;

            ---------------------------------------------------- blocs
            when OP_BLKMOV =>                             -- ( @dst len @src -- )
               A := Depiler;
               N := Depiler;
               if Avec_Limites then
                  Limites.Adresse_Suivante;              -- adresse de destination
               end if;
               B := Depiler;
               if Vers_Signe (N) < 0 then
                  Signaler ("longueur de bloc negative");
               end if;
               if Avec_Limites then
                  Limites.Acces (A, N, Limites.Lecture, Limites.Indirecte);
                  Limites.Acces (B, N, Limites.Ecriture, Limites.Indirecte);
               end if;
               Copier (B, A, N);
            when OP_BLKAND | OP_BLKOU | OP_BLKOUX =>
               Operation_Bloc (Op);
            when OP_BLKNOT =>                             -- ( @dst len -- )
               N := Depiler;
               if Avec_Limites then
                  Limites.Adresse_Suivante;              -- adresse de destination
               end if;
               A := Depiler;
               if Vers_Signe (N) < 0 then
                  Signaler ("longueur de bloc negative");
               end if;
               B := 0;
               while B < N loop
                  Ecrire_8 (A + B, Lire_8 (A + B) xor 1);
                  B := B + 1;
               end loop;
            when OP_BLKCMP =>                             -- ( @a len @b -- eq )
               B := Depiler;
               N := Depiler;
               A := Depiler;
               if Vers_Signe (N) < 0 then
                  Signaler ("longueur de bloc negative");
               end if;
               if Avec_Limites then
                  Limites.Acces (A, N, Limites.Lecture, Limites.Indirecte);
                  Limites.Acces (B, N, Limites.Lecture, Limites.Indirecte);
               end if;
               Empiler (Booleen (Egaux (A, B, N)));
            when OP_LEXCMP =>                             -- ( @g lg @d ld -- -1|0|+1 )
               declare
                  Lg_D : Signe := Vers_Signe (Depiler);
                  AD  : Unsigned_64 := Depiler;
                  Lg_G  : Signe := Vers_Signe (Depiler);
                  AG  : Unsigned_64 := Depiler;
                  Pas : constant Signe := Signe (Vers_Signe (Ofs));
                  CG, CD : Signe;
                  Res : Signe := 0;
                  Decide : Boolean := False;
               begin
                  while Lg_G > 0 and Lg_D > 0 loop
                     CG := Composant (AG);
                     CD := Composant (AD);
                     if CG /= CD then
                        if CG < CD then
                           Res := -1;
                        else
                           Res := 1;
                        end if;
                        Decide := True;
                        exit;
                     end if;
                     AG := AG + Unsigned_64 (Pas);
                     AD := AD + Unsigned_64 (Pas);
                     Lg_G := Lg_G - Pas;
                     Lg_D := Lg_D - Pas;
                  end loop;
                  if not Decide then
                     if Lg_G > Lg_D then
                        Res := 1;
                     elsif Lg_G < Lg_D then
                        Res := -1;
                     end if;
                  end if;
                  Empiler (Vers_Mot (Res));
               end;

            ---------------------------------------------------- controles d'intervalle
            when OP_CHKB .. OP_CHKUID =>                  -- ( v -- v )
               Verifier_Niveau (Lvl);
               if Op <= OP_CHKUD then
                  K := Op - OP_CHKB;
                  A := Base_B + Val;                        -- forme B
               else
                  K := Op - OP_CHKIB;
                  A := Adresse_C;                           -- forme C
               end if;
               SA := Vers_Signe (Sommet);
               if SA < Borne (A, K) or else SA > Borne (A + Taille_De (K), K) then
                  if CEV = 0 then
                     Signaler ("CHK en echec sans vecteur CEV (programme sans ce_raise_)");
                  end if;
                  Suivant := CEV;
               end if;

            ---------------------------------------------------- appels systeme
            when OP_TRAP =>
               if Val > Dernier_Service then
                  Signaler ("service TRAP inconnu : " & Image (Vers_Signe (Val)));
               end if;
               if Avec_Profil then
                  Profil.Service (Integer (Val));
               end if;
               if Avec_Limites then
                  Limites.Barriere;                         -- appel systeme : serialisant
               end if;
               Trap (Integer (Val), Ofs);

            when others =>
               Signaler ("code d'operation TX illegal : " & Image (Op));
         end case;

         if Avec_Limites then
            Limites.Fin (Op, PC, Suivant);
         end if;
         if Frontal.Actif then
            Frontal.Instruction (PC, Suivant);
         end if;
         exit when Fini;
         PC := Suivant;
      end loop;
      Profil.Max_Pile_Octets := Max_DSP - Base_Pile;
   exception
      when Faute =>
         Profil.Max_Pile_Octets := Max_DSP - Base_Pile;
         raise;
   end Executer;

end Machine;
