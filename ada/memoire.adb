with Direct_IO;
with Unchecked_Conversion;
package body Memoire is

   type Octets is array (Natural range <>) of Unsigned_8;
   type Acces_Octets is access Octets;

   type Region is record
      Debut   : Unsigned_64 := 0;
      Taille  : Unsigned_64 := 0;
      Donnees : Acces_Octets;
   end record;

   package Octet_IO is new Direct_IO (Unsigned_8);

   --  Lecture et ecriture des mots par blocs d'octets.
   --  L'hote doit etre petit-boutiste, comme la machine LLIR (x86-64, ARM64).
   subtype Huit   is Octets (0 .. 7);
   subtype Quatre is Octets (0 .. 3);
   subtype Deux   is Octets (0 .. 1);
   function De_Huit     is new Unchecked_Conversion (Huit, Unsigned_64);
   function Vers_Huit   is new Unchecked_Conversion (Unsigned_64, Huit);
   function De_Quatre   is new Unchecked_Conversion (Quatre, Unsigned_32);
   function Vers_Quatre is new Unchecked_Conversion (Unsigned_32, Quatre);
   function De_Deux     is new Unchecked_Conversion (Deux, Unsigned_16);
   function Vers_Deux   is new Unchecked_Conversion (Unsigned_16, Deux);

   --  Enregistrement d'instruction TX tel qu'il est range dans l'image
   subtype Seize is Octets (0 .. 15);
   type Enregistrement is record
      Op  : Unsigned_8;
      Lvl : Integer_8;
      Res : Unsigned_16;
      Ofs : Integer_32;
      Val : Unsigned_64;
   end record;
   for Enregistrement use record
      Op  at 0 range 0 .. 7;
      Lvl at 1 range 0 .. 7;
      Res at 2 range 0 .. 15;
      Ofs at 4 range 0 .. 31;
      Val at 8 range 0 .. 63;
   end record;
   function De_Seize is new Unchecked_Conversion (Seize, Enregistrement);
   function Mot_Signe is new Unchecked_Conversion (Integer_64, Unsigned_64);

   Img, Pile, Tas : Region;
   Fin_Du_Code    : Unsigned_64 := 0;
   Vecteur        : Unsigned_64 := 0;     -- en-tete +48 (format 2)
   Table_Adr      : Unsigned_64 := 0;     -- en-tete +56 (format 3)
   Table_Nb       : Natural := 0;         -- en-tete +64 (format 3)
   Debut_De_Copile : Unsigned_64 := 0;

   Texte_Faute    : String (1 .. 300);
   Longueur_Faute : Natural := 0;

   procedure Signaler (Texte : String) is
      N : Natural := Texte'Length;
   begin
      if N > Texte_Faute'Length then
         N := Texte_Faute'Length;
      end if;
      Texte_Faute (1 .. N) := Texte (Texte'First .. Texte'First + N - 1);
      Longueur_Faute := N;
      raise Faute;
   end Signaler;

   function Message return String is
   begin
      return Texte_Faute (1 .. Longueur_Faute);
   end Message;

   function Hexa (V : Unsigned_64) return String is
      Chiffres : constant String := "0123456789ABCDEF";
      R : String (1 .. 16);
      X : Unsigned_64 := V;
   begin
      for I in reverse R'Range loop
         R (I) := Chiffres (Integer (X and 15) + 1);
         X := Shift_Right (X, 4);
      end loop;
      return "16#" & R & "#";
   end Hexa;

   function Allouer (Taille : Natural) return Acces_Octets is
   begin
      return new Octets'(0 .. Taille - 1 => 0);
   end Allouer;

   --  Situe [A, A+N-1] dans une region ; rend la region et l'indice du premier octet
   procedure Situer (A : Unsigned_64; N : Unsigned_64;
                     R : out Acces_Octets; I : out Natural) is
      D : Unsigned_64;
   begin
      D := A - Pile.Debut;
      if D < Pile.Taille and then N <= Pile.Taille - D then
         R := Pile.Donnees; I := Natural (D); return;
      end if;
      D := A - Img.Debut;
      if D < Img.Taille and then N <= Img.Taille - D then
         R := Img.Donnees; I := Natural (D); return;
      end if;
      D := A - Tas.Debut;
      if D < Tas.Taille and then N <= Tas.Taille - D then
         R := Tas.Donnees; I := Natural (D); return;
      end if;
      Signaler ("acces memoire hors regions a l'adresse " & Hexa (A));
   end Situer;
   pragma Inline (Situer);

   function Lire (A : Unsigned_64; N : Natural) return Unsigned_64 is
      R : Acces_Octets;
      I : Natural;
   begin
      Situer (A, Unsigned_64 (N), R, I);
      case N is
         when 8 =>
            declare
               H : Huit;
            begin
               H := R (I .. I + 7);
               return De_Huit (H);
            end;
         when 4 =>
            declare
               Q : Quatre;
            begin
               Q := R (I .. I + 3);
               return Unsigned_64 (De_Quatre (Q));
            end;
         when 2 =>
            declare
               D : Deux;
            begin
               D := R (I .. I + 1);
               return Unsigned_64 (De_Deux (D));
            end;
         when others =>
            return Unsigned_64 (R (I));
      end case;
   end Lire;
   pragma Inline (Lire);

   procedure Ecrire (A : Unsigned_64; N : Natural; V : Unsigned_64) is
      R : Acces_Octets;
      I : Natural;
   begin
      Situer (A, Unsigned_64 (N), R, I);
      case N is
         when 8 =>
            R (I .. I + 7) := Vers_Huit (V);
         when 4 =>
            R (I .. I + 3) := Vers_Quatre (Unsigned_32 (V and 16#FFFF_FFFF#));
         when 2 =>
            R (I .. I + 1) := Vers_Deux (Unsigned_16 (V and 16#FFFF#));
         when others =>
            R (I) := Unsigned_8 (V and 16#FF#);
      end case;
   end Ecrire;
   pragma Inline (Ecrire);

   function Lire_8  (A : Unsigned_64) return Unsigned_64 is
   begin
      return Lire (A, 1);
   end Lire_8;
   function Lire_16 (A : Unsigned_64) return Unsigned_64 is
   begin
      return Lire (A, 2);
   end Lire_16;
   function Lire_32 (A : Unsigned_64) return Unsigned_64 is
   begin
      return Lire (A, 4);
   end Lire_32;
   function Lire_64 (A : Unsigned_64) return Unsigned_64 is
   begin
      return Lire (A, 8);
   end Lire_64;

   procedure Ecrire_8  (A : Unsigned_64; V : Unsigned_64) is
   begin
      Ecrire (A, 1, V);
   end Ecrire_8;
   procedure Ecrire_16 (A : Unsigned_64; V : Unsigned_64) is
   begin
      Ecrire (A, 2, V);
   end Ecrire_16;
   procedure Ecrire_32 (A : Unsigned_64; V : Unsigned_64) is
   begin
      Ecrire (A, 4, V);
   end Ecrire_32;
   procedure Ecrire_64 (A : Unsigned_64; V : Unsigned_64) is
   begin
      Ecrire (A, 8, V);
   end Ecrire_64;

   function Mot_Image (I : Natural) return Unsigned_64 is
      H : Huit;
   begin
      H := Img.Donnees (I .. I + 7);
      return De_Huit (H);
   end Mot_Image;

   procedure Charger_Image (Nom : String; Taille_Copile : Natural) is
      F : Octet_IO.File_Type;
      N : Natural;
      Taille_Code : Unsigned_64;
      Signature : constant String := "TLALOCTX";
   begin
      begin
         Octet_IO.Open (F, Octet_IO.In_File, Nom);
      exception
         when others =>
            Signaler ("impossible d'ouvrir l'image " & Nom);
      end;
      N := Natural (Octet_IO.Size (F));
      if N < 16#78# then
         Signaler ("image trop courte : " & Nom);
      end if;
      --  Taille provisoire pour lire l'en-tete et le contenu du fichier
      Img.Debut := Base_Image;
      Img.Donnees := Allouer (N);
      for I in 0 .. N - 1 loop
         Octet_IO.Read (F, Img.Donnees (I));
      end loop;
      Octet_IO.Close (F);

      for I in Signature'Range loop
         if Character'Val (Img.Donnees (I - 1)) /= Signature (I) then
            Signaler ("signature TLALOCTX absente : ce n'est pas une image TX");
         end if;
      end loop;
      if Mot_Image (8) = 3 then
         Vecteur := Mot_Image (48);
         Table_Adr := Mot_Image (56);
         Table_Nb := Natural (Mot_Image (64));
      elsif Mot_Image (8) = 2 then
         Vecteur := Mot_Image (48);
      elsif Mot_Image (8) /= 1 then
         Signaler ("version de format TX non reconnue");
      end if;
      if Mot_Image (16) /= Base_Image or Mot_Image (24) /= Entree
        or Mot_Image (40) /= Taille_Enregistrement then
         Signaler ("en-tete TX incoherent (base, entree ou taille d'enregistrement)");
      end if;
      Taille_Code := Mot_Image (32);
      if Unsigned_64 (N) /= 16#78# + Taille_Code then
         Signaler ("taille de l'image incoherente avec l'en-tete");
      end if;
      Fin_Du_Code := Entree + Taille_Code;
      Debut_De_Copile := Entree + 8 * ((Taille_Code + 7) / 8);

      --  Region definitive : image puis co-pile au-dessus
      declare
         Total : constant Natural :=
           Natural (Debut_De_Copile - Base_Image) + Taille_Copile;
         Nouveau : constant Acces_Octets := Allouer (Total);
      begin
         for I in 0 .. N - 1 loop
            Nouveau (I) := Img.Donnees (I);
         end loop;
         Img.Donnees := Nouveau;
         Img.Taille := Unsigned_64 (Total);
      end;
   end Charger_Image;

   procedure Creer_Pile (Taille : Natural) is
   begin
      Pile.Debut := Base_Pile;
      Pile.Taille := Unsigned_64 (Taille);
      Pile.Donnees := Allouer (Taille);
   end Creer_Pile;

   procedure Creer_Tas (Taille : Natural) is
   begin
      Tas.Debut := Base_Tas;
      Tas.Taille := Unsigned_64 (Taille);
      Tas.Donnees := Allouer (Taille);
   end Creer_Tas;

   function Fin_Code return Unsigned_64 is
   begin
      return Fin_Du_Code;
   end Fin_Code;
   function Debut_Copile return Unsigned_64 is
   begin
      return Debut_De_Copile;
   end Debut_Copile;
   function Fin_Copile return Unsigned_64 is
   begin
      return Img.Debut + Img.Taille;
   end Fin_Copile;
   function Fin_Pile return Unsigned_64 is
   begin
      return Pile.Debut + Pile.Taille;
   end Fin_Pile;
   function Vecteur_CE return Unsigned_64 is
   begin
      return Vecteur;
   end Vecteur_CE;

   function Table_Instructions return Unsigned_64 is
   begin
      return Table_Adr;
   end Table_Instructions;

   function Nombre_Instructions return Natural is
   begin
      return Table_Nb;
   end Nombre_Instructions;

   function Fin_Tas return Unsigned_64 is
   begin
      return Tas.Debut + Tas.Taille;
   end Fin_Tas;

   --  Copie de bloc : comme rep movsb, octet par octet vers l'avant si la
   --  destination recouvre la source par le haut, sinon par tranche
   procedure Copier (Dst, Src, Lg : Unsigned_64) is
      R_Src, R_Dst : Acces_Octets;
      I_Src, I_Dst : Natural;
      N : Natural;
   begin
      if Lg = 0 then
         return;
      end if;
      Situer (Src, Lg, R_Src, I_Src);
      Situer (Dst, Lg, R_Dst, I_Dst);
      N := Natural (Lg);
      if R_Src = R_Dst and then Dst > Src and then Dst - Src < Lg then
         for K in 0 .. N - 1 loop
            R_Dst (I_Dst + K) := R_Src (I_Src + K);
         end loop;
      else
         R_Dst (I_Dst .. I_Dst + N - 1) := R_Src (I_Src .. I_Src + N - 1);
      end if;
   end Copier;

   function Egaux (A, B, Lg : Unsigned_64) return Boolean is
      R_A, R_B : Acces_Octets;
      I_A, I_B : Natural;
      N : Natural;
   begin
      if Lg = 0 then
         return True;
      end if;
      Situer (A, Lg, R_A, I_A);
      Situer (B, Lg, R_B, I_B);
      N := Natural (Lg);
      return R_A (I_A .. I_A + N - 1) = R_B (I_B .. I_B + N - 1);
   end Egaux;

   function Lire_Pile (A : Unsigned_64) return Unsigned_64 is
      D : constant Unsigned_64 := A - Base_Pile;
      H : Huit;
   begin
      if D > Pile.Taille - 8 then
         Signaler ("acces hors de la pile data a l'adresse " & Hexa (A));
      end if;
      H := Pile.Donnees (Natural (D) .. Natural (D) + 7);
      return De_Huit (H);
   end Lire_Pile;

   procedure Ecrire_Pile (A : Unsigned_64; V : Unsigned_64) is
      D : constant Unsigned_64 := A - Base_Pile;
   begin
      if D > Pile.Taille - 8 then
         Signaler ("acces hors de la pile data a l'adresse " & Hexa (A));
      end if;
      Pile.Donnees (Natural (D) .. Natural (D) + 7) := Vers_Huit (V);
   end Ecrire_Pile;

   procedure Lire_Instruction (PC  : Unsigned_64;
                               Op  : out Integer;
                               Lvl : out Integer;
                               Ofs : out Unsigned_64;
                               Val : out Unsigned_64) is
      I : Natural;
      S : Seize;
      E : Enregistrement;
   begin
      if PC < Entree or else PC > Fin_Du_Code - Taille_Enregistrement then
         Signaler ("PC hors de la zone de code : " & Hexa (PC));
      end if;
      I := Natural (PC - Base_Image);
      S := Img.Donnees (I .. I + 15);
      E := De_Seize (S);
      Op  := Integer (E.Op);
      Lvl := Integer (E.Lvl);
      Ofs := Mot_Signe (Integer_64 (E.Ofs));          -- extension de signe
      Val := E.Val;
   end Lire_Instruction;

end Memoire;
