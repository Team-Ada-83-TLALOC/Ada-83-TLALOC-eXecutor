pragma Ada_2012;
--  Liaison POSIX : memes appels et memes parametres que les macros SYS_xxx
--  de codi_x86_64 (open 0x242 / mode 0700, lseek, ioctl TCGETS/TCSETS...).
with System;
with Interfaces.C; use Interfaces.C;
with GNAT.OS_Lib;
package body Hote is

   function C_Write (Fd : int; Buf : System.Address; N : size_t) return long;
   pragma Import (C, C_Write, "write");
   function C_Read (Fd : int; Buf : System.Address; N : size_t) return long;
   pragma Import (C, C_Read, "read");
   function C_Open (Nom : char_array; Drapeaux : int; Mode : unsigned) return int;
   pragma Import (C_Variadic_2, C_Open, "open");
   function C_Close (Fd : int) return int;
   pragma Import (C, C_Close, "close");
   function C_Lseek (Fd : int; Decalage : long; Origine : int) return long;
   pragma Import (C, C_Lseek, "lseek");
   function C_Unlink (Nom : char_array) return int;
   pragma Import (C, C_Unlink, "unlink");
   function C_Ioctl (Fd : int; Requete : unsigned_long; Arg : System.Address) return int;
   pragma Import (C_Variadic_2, C_Ioctl, "ioctl");

   type Timespec is record
      Sec  : long;
      Nsec : long;
   end record;
   pragma Convention (C, Timespec);
   function C_Clock_Gettime (Horloge_Id : int; Ts : access Timespec) return int;
   pragma Import (C, C_Clock_Gettime, "clock_gettime");

   O_RDWR_CREAT_TRUNC : constant := 16#242#;
   O_RDWR             : constant := 2;
   S_IRWXU            : constant := 8#700#;
   SEEK_SET           : constant := 0;
   SEEK_CUR           : constant := 1;
   SEEK_END           : constant := 2;
   TCGETS             : constant := 16#5401#;
   TCSETS             : constant := 16#5402#;

   Ouverts : array (0 .. 1023) of Boolean := (others => False);

   function Resultat (R : long) return Signe is
   begin
      if R < 0 then
         return -Signe (GNAT.OS_Lib.Errno);
      end if;
      return Signe (R);
   end Resultat;

   function Ecrire (Fd : Signe; Donnees : Tampon) return Signe is
   begin
      if Donnees'Length = 0 then
         return 0;
      end if;
      return Resultat (C_Write (int (Fd), Donnees (Donnees'First)'Address,
                                size_t (Donnees'Length)));
   end Ecrire;

   procedure Lire (Fd : Signe; Donnees : in out Tampon; Lus : out Signe) is
   begin
      if Donnees'Length = 0 then
         Lus := 0;
         return;
      end if;
      Lus := Resultat (C_Read (int (Fd), Donnees (Donnees'First)'Address,
                               size_t (Donnees'Length)));
   end Lire;

   --  Comme SYS_GET_CHAR : ICANON et ECHO (bits 1 et 3 de c_lflag, octet 12)
   --  retires le temps de la lecture, puis l'etat d'origine est restaure.
   procedure Lire_Immediat (Donnees : in out Tampon; Lus : out Signe) is
      Termios, Origine : Tampon (0 .. 63) := (others => 0);
      Terminal : constant Boolean := C_Ioctl (0, TCGETS, Termios'Address) = 0;
      R : int;
      pragma Unreferenced (R);
   begin
      if Terminal then
         Origine := Termios;
         Termios (12) := Termios (12) and 16#F5#;
         R := C_Ioctl (0, TCSETS, Termios'Address);
      end if;
      Lire (0, Donnees, Lus);
      if Terminal then
         R := C_Ioctl (0, TCSETS, Origine'Address);
      end if;
   end Lire_Immediat;

   function Noter (Fd : int) return Signe is
   begin
      if Fd >= 0 and then Integer (Fd) <= Ouverts'Last then
         Ouverts (Integer (Fd)) := True;
      end if;
      return Resultat (long (Fd));
   end Noter;

   function Creer (Nom : String) return Signe is
   begin
      return Noter (C_Open (To_C (Nom), O_RDWR_CREAT_TRUNC, S_IRWXU));
   end Creer;

   function Ouvrir (Nom : String) return Signe is
   begin
      return Noter (C_Open (To_C (Nom), O_RDWR, 0));
   end Ouvrir;

   function Fermer (Fd : Signe) return Signe is
   begin
      if Fd >= 0 and then Fd <= Signe (Ouverts'Last) then
         Ouverts (Integer (Fd)) := False;
      end if;
      return Resultat (long (C_Close (int (Fd))));
   end Fermer;

   function Detruire (Nom : String) return Signe is
   begin
      return Resultat (long (C_Unlink (To_C (Nom))));
   end Detruire;

   function Positionner (Fd : Signe; Position : Signe) return Signe is
   begin
      return Resultat (C_Lseek (int (Fd), long (Position), SEEK_SET));
   end Positionner;

   function Position (Fd : Signe) return Signe is
   begin
      return Resultat (C_Lseek (int (Fd), 0, SEEK_CUR));
   end Position;

   function Taille (Fd : Signe) return Signe is      -- sans deplacer la position courante
      Courante : constant long := C_Lseek (int (Fd), 0, SEEK_CUR);
      Fin      : constant long := C_Lseek (int (Fd), 0, SEEK_END);
      R        : long;
      pragma Unreferenced (R);
   begin
      if Courante >= 0 then
         R := C_Lseek (int (Fd), Courante, SEEK_SET);
      end if;
      return Resultat (Fin);
   end Taille;

   procedure Horloge (Secondes : out Signe; Nanosecondes : out Signe) is
      Ts : aliased Timespec := (0, 0);
      R  : constant int := C_Clock_Gettime (0, Ts'Access);      -- CLOCK_REALTIME
      pragma Unreferenced (R);
   begin
      Secondes := Signe (Ts.Sec);
      Nanosecondes := Signe (Ts.Nsec);
   end Horloge;

   procedure Terminer is
      R : int;
      pragma Unreferenced (R);
   begin
      for Fd in 3 .. Ouverts'Last loop
         if Ouverts (Fd) then
            R := C_Close (int (Fd));
            Ouverts (Fd) := False;
         end if;
      end loop;
   end Terminer;

end Hote;
