--  Services TRAP : transcription des macros SYS_xxx de codi_x86_64.
--  Les fonctions systeme rendent leur resultat sur le « lieu result » :
--  la cellule qui devient sommet apres depilement des arguments.
separate (Machine)
procedure Trap (Service : Integer; Code : Unsigned_64) is

   Taille_Max : constant := 16 * 1024 * 1024;

   A, B, C : Unsigned_64;
   R, S, N : Signe;


   --  Longueur d'une chaine Ada a partir de son doublet @DATA | @USEINFO
   --  info : +8 FIRST, +12 LAST (dwords) ; longueur = LAST + 1 - FIRST
   function Longueur (Doublet : Unsigned_64) return Signe is
      Info : constant Unsigned_64 := Lire_64 (Doublet + 8);
      Dernier : constant Signe := Vers_Signe (Etendre_32 (Lire_32 (Info + 12)));
      Premier : constant Signe := Vers_Signe (Etendre_32 (Lire_32 (Info + 8)));
   begin
      return Dernier + 1 - Premier;
   end Longueur;

   procedure Verifier (Lg : Signe) is
   begin
      if Lg > Taille_Max then
         Signaler ("transfert d'entree-sortie trop long");
      end if;
   end Verifier;

   function Chaine (Doublet : Unsigned_64) return String is
      Lg : Signe := Longueur (Doublet);
   begin
      if Lg < 0 then
         Lg := 0;
      end if;
      Verifier (Lg);
      declare
         Donnees : constant Unsigned_64 := Lire_64 (Doublet);
         S : String (1 .. Integer (Lg));
      begin
         for I in S'Range loop
            S (I) := Character'Val (Lire_8 (Donnees + Unsigned_64 (I - 1)));
         end loop;
         return S;
      end;
   end Chaine;

   function Ecrire_Memoire (Fd : Signe; Adr : Unsigned_64; Lg : Signe) return Signe is
   begin
      if Lg <= 0 then
         return 0;
      end if;
      Verifier (Lg);
      declare
         T : Hote.Tampon (0 .. Natural (Lg) - 1);
      begin
         for I in T'Range loop
            T (I) := Unsigned_8 (Lire_8 (Adr + Unsigned_64 (I)));
         end loop;
         return Hote.Ecrire (Fd, T);
      end;
   end Ecrire_Memoire;

   function Lire_Memoire (Fd : Signe; Adr : Unsigned_64; Lg : Signe) return Signe is
      Lus : Signe;
   begin
      if Lg <= 0 then
         return 0;
      end if;
      Verifier (Lg);
      declare
         T : Hote.Tampon (0 .. Natural (Lg) - 1) := (others => 0);
      begin
         Hote.Lire (Fd, T, Lus);
         for I in 0 .. Integer (Lus) - 1 loop
            Ecrire_8 (Adr + Unsigned_64 (I), Unsigned_64 (T (I)));
         end loop;
         return Lus;
      end;
   end Lire_Memoire;

begin
   case Service is

      when SYS_EXIT =>                                    -- code en complement
         Code_Final := Integer (Vers_Signe (Code));
         Fini := True;

      when SYS_CLOCK_GETTIME =>                           -- ( @timespec -- )
         A := Depiler;
         Hote.Horloge (S, N);
         Ecrire_64 (A, Vers_Mot (S));
         Ecrire_64 (A + 8, Vers_Mot (N));

      when SYS_PUT_CHAR =>                                -- ( c -- )
         R := Ecrire_Memoire (1, DSP, 1);
         A := Depiler;

      when SYS_PUT_STR =>                                 -- ( @doublet -- )
         A := Depiler;
         R := Ecrire_Memoire (1, Lire_64 (A), Longueur (A));

      when SYS_GET_CHAR =>                                -- ( @dst -- )
         A := Depiler;
         declare
            T : Hote.Tampon (0 .. 0) := (others => 0);
         begin
            Hote.Lire_Immediat (T, R);
            if R = 1 then
               Ecrire_8 (A, Unsigned_64 (T (0)));
            end if;
         end;

      when SYS_GET_STR =>                                 -- ( @lg @doublet -- )
         A := Depiler;
         R := Lire_Memoire (0, Lire_64 (A), Longueur (A));
         B := Depiler;
         Ecrire_32 (B, Vers_Mot (R - 1) and Masque_32);

      when SYS_FILE_CREATE =>                             -- ( res @nom -- fd )
         A := Depiler;
         Remplacer_Sommet (Vers_Mot (Hote.Creer (Chaine (A))));

      when SYS_FILE_OPEN =>                               -- ( res @nom -- fd )
         A := Depiler;
         Remplacer_Sommet (Vers_Mot (Hote.Ouvrir (Chaine (A))));

      when SYS_FILE_SET_POS =>                            -- ( res pos fd -- r )
         A := Depiler;
         B := Depiler;
         Remplacer_Sommet (Vers_Mot (Hote.Positionner (Vers_Signe (A), Vers_Signe (B))));

      when SYS_FILE_GET_POS =>                            -- ( res fd -- pos )
         A := Depiler;
         Remplacer_Sommet (Vers_Mot (Hote.Position (Vers_Signe (A))));

      when SYS_FILE_GET_SIZE =>                           -- ( res fd -- taille )
         A := Depiler;
         Remplacer_Sommet (Vers_Mot (Hote.Taille (Vers_Signe (A))));

      when SYS_FILE_WRITE =>                              -- ( res lg @tampon fd -- n )
         A := Depiler;
         B := Depiler;
         C := Depiler;
         Remplacer_Sommet (Vers_Mot (Ecrire_Memoire (Vers_Signe (A), B, Vers_Signe (C))));

      when SYS_FILE_READ =>                               -- ( res lg @tampon fd -- n )
         A := Depiler;
         B := Depiler;
         C := Depiler;
         Remplacer_Sommet (Vers_Mot (Lire_Memoire (Vers_Signe (A), B, Vers_Signe (C))));

      when SYS_FILE_CLOSE =>                              -- ( res fd -- r )
         A := Depiler;
         Remplacer_Sommet (Vers_Mot (Hote.Fermer (Vers_Signe (A))));

      when SYS_FILE_DELETE =>                             -- ( res @nom -- r )
         A := Depiler;
         Remplacer_Sommet (Vers_Mot (Hote.Detruire (Chaine (A))));

      when others =>
         Signaler ("service TRAP non implante : " & Image (Service));
   end case;
end Trap;
