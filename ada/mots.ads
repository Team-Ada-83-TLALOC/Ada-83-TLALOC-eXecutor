--  Types de base de la machine LLIR : mots de 64 bits vus en non signe
--  (arithmetique modulaire, operations logiques, decalages) ou en signe.
with Interfaces; use Interfaces;
with Unchecked_Conversion;
package Mots is

   type Signe is range -2**63 .. 2**63 - 1;

   function Vers_Signe  is new Unchecked_Conversion (Unsigned_64, Signe);
   function Vers_Mot    is new Unchecked_Conversion (Signe, Unsigned_64);
   function Vers_Reel   is new Unchecked_Conversion (Unsigned_64, Long_Float);
   function Depuis_Reel is new Unchecked_Conversion (Long_Float, Unsigned_64);

   Bit_63 : constant Unsigned_64 := 16#8000_0000_0000_0000#;

   function Hexa (V : Unsigned_64) return String;   -- 16#....#
   function Image (V : Signe) return String;        -- sans espace de tete
   function Image (V : Integer) return String;

end Mots;
