// AIC airlift mission (Tanoa): squads flown between two held airfields
call compile preprocessFileLineNumbers "harness.sqf";
[[
    "tests\t_airlift.sqf"
]] call AIC_T_run;
