--  Machine LLIR : etat architectural et boucle d'execution des enregistrements TX.
--  Semantique : LLIR_hardware_support (revision), transcription de codi_x86_64.
with Interfaces; use Interfaces;
with Mots; use Mots;
package Machine is

   procedure Initialiser (Profiler : Boolean; Limite : Signe; Mesurer_Limites : Boolean);
   procedure Executer;                        -- jusqu'a SYS_EXIT ; les fautes levent Memoire.Faute

   function Code_De_Sortie return Integer;
   function PC_Courant return Unsigned_64;
   function Code_Courant return Integer;
   function Instructions_Executees return Signe;

end Machine;
