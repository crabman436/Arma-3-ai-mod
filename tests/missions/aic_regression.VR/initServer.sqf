// AIC regression mission (VR): unit checks of the real functions, then a soak
call compile preprocessFileLineNumbers "harness.sqf";
[[
    "tests\t_f08_power.sqf",
    "tests\t_f07_antiair.sqf",
    "tests\t_f02_park.sqf",
    "tests\t_f10_march.sqf",
    "tests\t_f11_split.sqf",
    "tests\t_f13_markers.sqf",
    "tests\t_paradrop.sqf",
    "tests\t_replan.sqf",
    "tests\t_soak.sqf"
]] call AIC_T_run;
