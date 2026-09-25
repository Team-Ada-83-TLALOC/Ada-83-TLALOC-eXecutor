--  TX_RUN : interprete des images TX produites par fasmg avec codi_TX.finc.
--
--    tx_run [-p rapport] [-l] [-f] [-n limite] [-c copile_Mio] [-t tas_Mio] [-d pile_Mio] image.tx
--
--  -p rapport   ecrit le profil dynamique dans le fichier rapport ("-" : sortie d'erreur)
--  -l           etude de limites du parallelisme dans le rapport
--  -f           disposition du code (flux unique / double flux) et chargement
--  -n limite    arrete l'execution apres ce nombre d'instructions
--  La sortie standard est celle du programme LLIR ; les diagnostics vont sur la
--  sortie d'erreur. Le code de sortie est celui de SYS_EXIT (70 sur faute).
with Text_IO;
with Args;
with Mots; use Mots;
with Memoire;
with Machine;
with Profil;
with Hote;
with Frontal;
with TX_Codes;
procedure TX_Run is

   Mio : constant := 1024 * 1024;

   Nom_Image   : String (1 .. 1024);
   Lg_Image    : Natural := 0;
   Nom_Rapport : String (1 .. 1024);
   Lg_Rapport  : Natural := 0;
   Avec_Profil : Boolean := False;
   Avec_Limites : Boolean := False;
   Avec_Frontal : Boolean := False;
   Limite      : Signe := 0;
   Copile, Tas, Pile : Natural := 0;
   I : Positive := 1;
   Code : Integer := 0;

   procedure Usage is
   begin
      Text_IO.Put_Line (Text_IO.Standard_Error,
        "usage : tx_run [-p rapport] [-l] [-f] [-n limite] [-c copile_Mio] [-t tas_Mio] [-d pile_Mio] image.tx");
      Args.Code_De_Sortie (2);
   end Usage;

   function Valeur (S : String) return Natural is
   begin
      return Natural'Value (S);
   end Valeur;

   procedure Stocker (S : String; Dans : in out String; Lg : out Natural) is
   begin
      Dans (Dans'First .. Dans'First + S'Length - 1) := S;
      Lg := S'Length;
   end Stocker;

   procedure Rapport_Final is
   begin
      if Avec_Profil then
         if Nom_Rapport (1 .. Lg_Rapport) = "-" then
            Profil.Rapport ("");
         else
            Profil.Rapport (Nom_Rapport (1 .. Lg_Rapport));
         end if;
      end if;
   end Rapport_Final;

begin
   Copile := 64;
   Tas := 64;
   Pile := 4;
   while I <= Args.Nombre loop
      declare
         A : constant String := Args.Argument (I);
      begin
         if (A = "-p" or A = "-n" or A = "-c" or A = "-t" or A = "-d") and I = Args.Nombre then
            Usage;
            return;
         elsif A = "-p" then
            I := I + 1;
            Stocker (Args.Argument (I), Nom_Rapport, Lg_Rapport);
            Avec_Profil := True;
         elsif A = "-l" then
            Avec_Limites := True;
         elsif A = "-f" then
            Avec_Frontal := True;
         elsif A = "-n" then
            I := I + 1;
            Limite := Signe (Valeur (Args.Argument (I)));
         elsif A = "-c" then
            I := I + 1;
            Copile := Valeur (Args.Argument (I));
         elsif A = "-t" then
            I := I + 1;
            Tas := Valeur (Args.Argument (I));
         elsif A = "-d" then
            I := I + 1;
            Pile := Valeur (Args.Argument (I));
         else
            Stocker (A, Nom_Image, Lg_Image);
         end if;
      end;
      I := I + 1;
   end loop;
   if Lg_Image = 0 then
      Usage;
      return;
   end if;
   if (Avec_Limites or Avec_Frontal) and not Avec_Profil then   -- rapport sur la sortie d'erreur
      Stocker ("-", Nom_Rapport, Lg_Rapport);
      Avec_Profil := True;
   end if;

   begin
      Memoire.Charger_Image (Nom_Image (1 .. Lg_Image), Copile * Mio);
      Memoire.Creer_Pile (Pile * Mio);
      Memoire.Creer_Tas (Tas * Mio);
      if Avec_Frontal then
         Frontal.Preparer;
         Frontal.Actif := True;
      end if;
      Machine.Initialiser (Avec_Profil, Limite, Avec_Limites);
      Machine.Executer;
      Code := Machine.Code_De_Sortie;
   exception
      when Memoire.Faute =>
         Text_IO.Put_Line (Text_IO.Standard_Error,
           "tx_run : FAUTE : " & Memoire.Message);
         if Machine.Instructions_Executees > 0 then
            Text_IO.Put_Line (Text_IO.Standard_Error,
              "         PC = " & Hexa (Machine.PC_Courant)
              & "  instruction " & TX_Codes.Noms (Machine.Code_Courant)
              & "  apres " & Image (Machine.Instructions_Executees) & " instructions");
         end if;
         Code := 70;
   end;
   Hote.Terminer;
   Rapport_Final;
   Args.Code_De_Sortie (Code);
end TX_Run;
