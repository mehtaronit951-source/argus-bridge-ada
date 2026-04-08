-- ARGUS Ada Bridge — Implementation
-- Uses POSIX pipes to spawn and communicate with argus_bridge.py.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with GNAT.OS_Lib;
with GNAT.JSON;

package body Argus_Bridge is

   function Generate_Id return String is
      use GNAT.OS_Lib;
      T : constant String := Integer'Image (Integer (Clock));
   begin
      return T (T'First + 1 .. T'Last);
   end Generate_Id;

   function Create_Bridge
     (Module      : String := "argus";
      Python      : String := "python3";
      Bridge_Path : String := "bridge/argus_bridge.py") return Bridge_Type
   is
      -- Use environment overrides if set
      Py  : constant String :=
        (if GNAT.OS_Lib.Getenv ("ARGUS_PYTHON").all /= ""
         then GNAT.OS_Lib.Getenv ("ARGUS_PYTHON").all else Python);
      Bp  : constant String :=
        (if GNAT.OS_Lib.Getenv ("ARGUS_BRIDGE_PATH").all /= ""
         then GNAT.OS_Lib.Getenv ("ARGUS_BRIDGE_PATH").all else Bridge_Path);

      Args  : GNAT.OS_Lib.Argument_List := (1 => new String'(Bp));
      Pid   : GNAT.OS_Lib.Process_Id;
      Sin   : GNAT.OS_Lib.File_Descriptor;
      Sout  : GNAT.OS_Lib.File_Descriptor;
   begin
      GNAT.OS_Lib.Spawn_And_Get_IO (Py, Args, Pid, Sin, Sout);
      return (Stdin_Fd  => Integer (Sin),
              Stdout_Fd => Integer (Sout),
              Pid       => Integer (Pid),
              Module    => To_Unbounded_String (Module));
   end Create_Bridge;

   function Send_Request
     (Bridge  : in out Bridge_Type;
      Request : String) return JSON_Value
   is
      use GNAT.OS_Lib;
      Id   : constant String  := Generate_Id;
      Line : constant String  := Request & "," & ASCII.LF;
      Buf  : String (1 .. 4096);
      Last : Natural;
   begin
      -- Write JSON line to stdin
      declare
         Dummy : Integer;
      begin
         Dummy := Write (File_Descriptor (Bridge.Stdin_Fd), Line'Address, Line'Length);
      end;
      -- Read response line from stdout
      Last := 0;
      loop
         declare
            N : constant Integer :=
              Read (File_Descriptor (Bridge.Stdout_Fd), Buf (Last + 1)'Address, 1);
         begin
            exit when N <= 0;
            Last := Last + 1;
            exit when Buf (Last) = ASCII.LF;
         end;
      end loop;
      return JSON_Value (To_Unbounded_String (Buf (1 .. Last - 1)));
   end Send_Request;

   function Call_Fn
     (Bridge  : in out Bridge_Type;
      Fn      : String;
      Args    : String := "[]";
      Kwargs  : String := "{}") return JSON_Value
   is
      Id  : constant String := Generate_Id;
      Req : constant String :=
        "{""id"":""" & Id & """,""module"":""" & To_String (Bridge.Module)
        & """,""method"":""" & Fn
        & """,""args"":" & Args
        & ",""kwargs"":" & Kwargs
        & ",""store"":false}";
   begin
      return Send_Request (Bridge, Req);
   end Call_Fn;

   function Create_Session
     (Bridge      : in out Bridge_Type;
      Class_Name  : String;
      Init_Kwargs : String := "{}") return Session_Type
   is
      Id  : constant String := Generate_Id;
      Req : constant String :=
        "{""id"":""" & Id & """,""module"":""" & To_String (Bridge.Module)
        & """,""class"":""" & Class_Name
        & """,""init_kwargs"":" & Init_Kwargs
        & ",""args"":[],""kwargs"":{},""store"":true}";
      Resp    : constant JSON_Value := Send_Request (Bridge, Req);
      Resp_Str : constant String    := To_String (Unbounded_String (Resp));
      -- Extract session id from response JSON string (simple parse)
      Marker   : constant String    := """session"":""";
      Start    : Natural := Ada.Strings.Fixed.Index (Resp_Str, Marker) + Marker'Length;
      Stop     : Natural := Ada.Strings.Fixed.Index (Resp_Str, """", Start);
   begin
      return (Session_Id => To_Unbounded_String (Resp_Str (Start .. Stop - 1)),
              Module     => Bridge.Module);
   end Create_Session;

   function Call_Method
     (Bridge  : in out Bridge_Type;
      Session : Session_Type;
      Method  : String;
      Args    : String := "[]";
      Kwargs  : String := "{}") return JSON_Value
   is
      Id  : constant String := Generate_Id;
      Req : constant String :=
        "{""id"":""" & Id
        & """,""session"":""" & To_String (Session.Session_Id)
        & """,""module"":""" & To_String (Session.Module)
        & """,""method"":""" & Method
        & """,""args"":" & Args
        & ",""kwargs"":" & Kwargs & "}";
   begin
      return Send_Request (Bridge, Req);
   end Call_Method;

   function Ref (Session_Id : String) return String is
   begin
      return "{""__session__"":""" & Session_Id & """}";
   end Ref;

   procedure Close (Bridge : in out Bridge_Type) is
      use GNAT.OS_Lib;
   begin
      Close (File_Descriptor (Bridge.Stdin_Fd));
   end Close;

end Argus_Bridge;
