// AIC scenario mission (Stratis): paradrop from the airfield, digging in
call compile preprocessFileLineNumbers "harness.sqf";
[[
    "tests\t_fortify.sqf",
    "tests\t_para_flow.sqf"
]] call AIC_T_run;
