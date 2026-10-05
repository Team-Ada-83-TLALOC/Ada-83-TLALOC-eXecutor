--  Machine LLIR : etat architectural et boucle d'execution des enregistrements TX.
--  Semantique : LLIR_hardware_support (revision), transcription de codi_x86_64.
with Interfaces; use Interfaces;
with Mots; use Mots;
package Machine is

   procedure Initialiser (Profiler : Boolean; Limite : Signe; Mesurer_Limites : Boolean);
   procedure Executer;                        -- jusqu'a SYS_EXIT ; les fautes levent Memoire.Faute

   function Code_De_Sortie return Integer;


   procedure Ouvrir_Trace (Nom : String);   -- -x : pc de chaque instruction executee

   procedure Fermer_Trace;
   procedure Activer_Verification;          -- -v : regle V8 des cellules de calcul (avant Initialiser)
   function PC_Courant return Unsigned_64;
   function Code_Courant return Integer;
   function Instructions_Executees return Signe;   -- instructions executees (TX ou HX)
   function Instructions_LLIR return Signe;        -- instructions LLIR representees
   function Octets_Lus return Signe;               -- octets de code des instructions executees

end Machine;
