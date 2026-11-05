// AIC stress mission (Altis): large armies, commander cost and server FPS
call compile preprocessFileLineNumbers "harness.sqf";
[[
    "tests\t_stress.sqf"
]] call AIC_T_run;
