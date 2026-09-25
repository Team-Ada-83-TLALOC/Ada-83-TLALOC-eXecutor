package body Mots is

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

   function Image (V : Signe) return String is
      S : constant String := Signe'Image (V);
   begin
      if S (S'First) = ' ' then
         return S (S'First + 1 .. S'Last);
      else
         return S;
      end if;
   end Image;

   function Image (V : Integer) return String is
   begin
      return Image (Signe (V));
   end Image;

end Mots;
