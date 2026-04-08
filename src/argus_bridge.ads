-- ARGUS Ada Bridge
-- Spec: subprocess JSON-Lines bridge to argus_bridge.py
-- Build with: alr build

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package Argus_Bridge is

   type Bridge_Type is limited private;
   type Session_Type is record
      Session_Id : Unbounded_String;
      Module     : Unbounded_String;
   end record;

   type JSON_Value is new Unbounded_String;

   function Create_Bridge
     (Module      : String := "argus";
      Python      : String := "python3";
      Bridge_Path : String := "bridge/argus_bridge.py") return Bridge_Type;

   function Call_Fn
     (Bridge  : in out Bridge_Type;
      Fn      : String;
      Args    : String := "[]";
      Kwargs  : String := "{}") return JSON_Value;

   function Create_Session
     (Bridge      : in out Bridge_Type;
      Class_Name  : String;
      Init_Kwargs : String := "{}") return Session_Type;

   function Call_Method
     (Bridge  : in out Bridge_Type;
      Session : Session_Type;
      Method  : String;
      Args    : String := "[]";
      Kwargs  : String := "{}") return JSON_Value;

   function Ref (Session_Id : String) return String;

   procedure Close (Bridge : in out Bridge_Type);

private
   type Bridge_Type is limited record
      Stdin_Fd  : Integer;
      Stdout_Fd : Integer;
      Pid       : Integer;
      Module    : Unbounded_String;
   end record;

end Argus_Bridge;
