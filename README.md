# argus_bridge (Ada / Alire)

Ada bridge for [argus-debate-ai](https://pypi.org/project/argus-debate-ai/).

## Install

```bash
alr get argus_bridge
```

## Usage

```ada
with Argus_Bridge; use Argus_Bridge;

procedure Main is
   B   : Bridge_Type  := Create_Bridge;
   Orc : Session_Type := Create_Session (B, "RDCOrchestrator", "{""max_rounds"":5}");
   Res : JSON_Value   := Call_Method (B, Orc, "debate",
                                       Args   => "[""Nuclear energy is safe""]",
                                       Kwargs => "{""prior"":0.5}");
begin
   Ada.Text_IO.Put_Line (To_String (Unbounded_String (Res)));
   Close (B);
end Main;
```
