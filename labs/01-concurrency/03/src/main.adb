
with Ada.Text_IO;       use Ada.Text_IO;
with Ada.Strings;       use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;

procedure Main is
   subtype Bin is Integer range 0 .. 9;
   type Histogram is array (Bin) of Natural;
   type Numbers is array (Positive range <>) of Integer;

   function Img (Value : Integer) return String is
     (Trim (Integer'Image (Value), Both));

   function Count_Sequential (Data : Numbers) return Histogram is
      Result : Histogram := (others => 0);
   begin
      for Value of Data loop
         if Value not in Bin then
            raise Constraint_Error with "Numbers must be between 0 and 9";
         end if;
         Result (Value) := Result (Value) + 1;
      end loop;
      return Result;
   end Count_Sequential;

   function Count_Parallel
     (Data : Numbers; Requested_Workers : Positive; Verbose : Boolean := False)
      return Histogram
   is
   begin
      if Data'Length = 0 then
         return (others => 0);
      end if;

      for Value of Data loop
         if Value not in Bin then
            raise Constraint_Error with "Numbers must be between 0 and 9";
         end if;
      end loop;

      declare
         Worker_Count : constant Positive :=
           Positive'Min (Requested_Workers, Data'Length);
         type Workloads is array (Positive range <>) of Natural;

         protected type Collector_Type (Required : Positive) is
            procedure Submit (Id : Positive; Part : Histogram; Items : Natural);
            entry Wait_All;
            function Get_Result return Histogram;
            function Get_Workload (Id : Positive) return Natural;
         private
            Counts : Histogram := (others => 0);
            Loads : Workloads (1 .. Required) := (others => 0);
            Completed : Natural := 0;
         end Collector_Type;

         protected body Collector_Type is
            procedure Submit (Id : Positive; Part : Histogram; Items : Natural) is
            begin
               for B in Bin loop
                  Counts (B) := Counts (B) + Part (B);
               end loop;
               Loads (Id) := Items;
               Completed := Completed + 1;
            end Submit;

            entry Wait_All when Completed = Required is
            begin
               null;
            end Wait_All;

            function Get_Result return Histogram is
            begin
               return Counts;
            end Get_Result;

            function Get_Workload (Id : Positive) return Natural is
            begin
               return Loads (Id);
            end Get_Workload;
         end Collector_Type;

         Collector : Collector_Type (Worker_Count);

         task type Worker is
            entry Configure (Id, First_Index, Last_Index : Positive);
         end Worker;

         task body Worker is
            My_Id : Positive := 1;
            First : Positive := 1;
            Last : Positive := 1;
            Local_Counts : Histogram := (others => 0);
         begin
            accept Configure (Id, First_Index, Last_Index : Positive) do
               My_Id := Id;
               First := First_Index;
               Last := Last_Index;
            end Configure;

            for Index in First .. Last loop
               Local_Counts (Data (Index)) := Local_Counts (Data (Index)) + 1;
            end loop;

            Collector.Submit (My_Id, Local_Counts, Last - First + 1);
         end Worker;

         type Worker_Array is array (Positive range <>) of Worker;
         Workers : Worker_Array (1 .. Worker_Count);
      begin
         for Id in Workers'Range loop
            declare
               First : constant Positive :=
                 Data'First + ((Id - 1) * Data'Length) / Worker_Count;
               Last : constant Positive :=
                 Data'First + (Id * Data'Length) / Worker_Count - 1;
            begin
               Workers (Id).Configure (Id, First, Last);
            end;
         end loop;

         Collector.Wait_All;

         if Verbose then
            for Id in Workers'Range loop
               declare
                  First : constant Positive :=
                    Data'First + ((Id - 1) * Data'Length) / Worker_Count;
                  Last : constant Positive :=
                    Data'First + (Id * Data'Length) / Worker_Count - 1;
               begin
                  Put_Line
                    ("worker-" & Img (Id) & ": indexes " & Img (First) & ".." &
                     Img (Last) & ", processed=" &
                     Img (Collector.Get_Workload (Id)));
               end;
            end loop;
         end if;

         return Collector.Get_Result;
      end;
   end Count_Parallel;

   function Rejects (Data : Numbers) return Boolean is
   begin
      declare
         Result : constant Histogram := Count_Parallel (Data, 2);
      begin
         return False;
      end;
   exception
      when Constraint_Error =>
         return True;
   end Rejects;

   procedure Check
     (Name : String; Condition : Boolean;
      Passed, Total : in out Natural)
   is
   begin
      Total := Total + 1;
      if Condition then
         Passed := Passed + 1;
         Put_Line (Name & ": PASS");
      else
         Put_Line (Name & ": FAIL");
      end if;
   end Check;

   procedure Run_Tests is
      Passed : Natural := 0;
      Total : Natural := 0;
      Small : constant Numbers := (1, 2, 2, 3, 3, 3, 9);
      Mixed : constant Numbers :=
        (3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5, 8, 9, 7, 9, 3, 0, 2, 4, 6);
      Large : Numbers (1 .. 1000);
   begin
      Check ("Single zero",
             Count_Parallel (Numbers'(1 => 0), 1) =
             Histogram'(0 => 1, others => 0), Passed, Total);
      Check ("Single nine",
             Count_Parallel (Numbers'(1 => 9), 1) =
             Histogram'(9 => 1, others => 0), Passed, Total);
      Check ("Repeated values",
             Count_Parallel (Numbers'(1 => 3, 2 => 3, 3 => 3), 2) =
             Histogram'(3 => 3, others => 0), Passed, Total);
      Check ("All ten bins",
             Count_Parallel (Numbers'(0, 1, 2, 3, 4, 5, 6, 7, 8, 9), 4) =
             Histogram'(others => 1), Passed, Total);
      Check ("Empty input",
             Count_Parallel (Numbers'(1 .. 0 => 0), 4) =
             Histogram'(others => 0), Passed, Total);
      Check ("One worker", Count_Parallel (Mixed, 1) =
             Count_Sequential (Mixed), Passed, Total);
      Check ("Two workers", Count_Parallel (Mixed, 2) =
             Count_Sequential (Mixed), Passed, Total);
      Check ("Three workers", Count_Parallel (Mixed, 3) =
             Count_Sequential (Mixed), Passed, Total);
      Check ("Four workers", Count_Parallel (Mixed, 4) =
             Count_Sequential (Mixed), Passed, Total);
      Check ("More workers than values",
             Count_Parallel (Numbers'(1 => 0, 2 => 9), 12) =
             Histogram'(0 => 1, 9 => 1, others => 0), Passed, Total);
      Check ("Uneven division", Count_Parallel (Small, 4) =
             Count_Sequential (Small), Passed, Total);
      Check ("Different order", Count_Parallel (Numbers'(9, 3, 3, 2, 3, 2, 1), 3) =
             Count_Sequential (Small), Passed, Total);

      for I in Large'Range loop
         Large (I) := (I * 7) mod 10;
      end loop;
      Check ("Large input", Count_Parallel (Large, 8) =
             Count_Sequential (Large), Passed, Total);
      Check ("Negative value rejected",
             Rejects (Numbers'(1 => -1, 2 => 4)), Passed, Total);
      Check ("Value above nine rejected",
             Rejects (Numbers'(1 => 3, 2 => 10)), Passed, Total);

      Put_Line ("Passed: " & Img (Passed) & "/" & Img (Total));
      if Passed /= Total then
         raise Program_Error with "Some tests failed";
      end if;
   end Run_Tests;

   Input : constant Numbers :=
     (3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5, 8, 9, 7, 9, 3, 0, 2, 4, 6);
   Counts : Histogram;
   Total : Natural := 0;
begin
   Put_Line ("=== Parallel Number Histogram (Ada) ===");
   Put_Line ("Input length: 20");
   Put_Line ("Workers: 4");
   Counts := Count_Parallel (Input, 4, True);

   New_Line;
   Put_Line ("Histogram (value | count):");
   for Value in Bin loop
      Put (Img (Value) & " | ");
      for I in 1 .. Counts (Value) loop
         Put ("#");
      end loop;
      Put_Line (" (" & Img (Counts (Value)) & ")");
      Total := Total + Counts (Value);
   end loop;
   Put_Line ("Total counted: " & Img (Total));

   New_Line;
   Put_Line ("=== Tests ===");
   Run_Tests;
end Main;
