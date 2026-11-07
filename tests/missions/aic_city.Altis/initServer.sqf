// AIC city mission (Altis): a layered garrison of Kavala and of the airport
call compile preprocessFileLineNumbers "harness.sqf";
[[
    "tests\t_city.sqf",
    "tests\t_airfield.sqf"
]] call AIC_T_run;
