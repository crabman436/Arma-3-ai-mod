// AIC scenario mission (Stratis): paradrop from the airfield, digging in
call compile preprocessFileLineNumbers "harness.sqf";
[[
    "tests\t_fortify.sqf",
    "tests\t_para_flow.sqf",
    "tests\t_heli_ride.sqf",
    "tests\t_ropes.sqf",
    "tests\t_fastrope.sqf",
    "tests\t_hot_lz.sqf"
]] call AIC_T_run;
