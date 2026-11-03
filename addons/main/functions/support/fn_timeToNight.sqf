/*
 * Name: AIC_fnc_timeToNight
 * Description:
 *   Mission seconds until it is night, 0 when it is night now. Night is
 *   sunOrMoon below AIC_NIGHT_SUN, or the time of day (daytime) before the
 *   sunrise or after the sunset of the current date on this map
 *   (BIS_fnc_sunriseSunsetTime when it is available, else 06:00 / 20:00).
 *   Game hours are turned into mission seconds with timeMultiplier, so a
 *   mission with accelerated time waits accordingly less. Where the sun
 *   never sets (polar day) the result is 1e6.
 *
 * Parameters:
 *   none
 *
 * Returns:
 *   NUMBER - seconds of mission time until night, 0 if it is night
 *
 * Example:
 *   private _wait = [] call AIC_fnc_timeToNight;
 *   if (_wait > 0 && {_wait < AIC_NIGHT_WAIT_MAX}) then { ... };
 */

#include "\z\aic\addons\main\script_component.hpp"

if (sunOrMoon < AIC_NIGHT_SUN) exitWith {0};

private _sunrise = 6;
private _sunset = 20;
if (!isNil "BIS_fnc_sunriseSunsetTime") then {
    // the date array itself is the argument (BIKI: date call BIS_fnc_sunriseSunsetTime)
    private _times = date call BIS_fnc_sunriseSunsetTime;
    if (!isNil "_times" && {_times isEqualType []} && {count _times >= 2}
        && {(_times select 0) isEqualType 0} && {(_times select 1) isEqualType 0}) then {
        _sunrise = _times select 0;
        _sunset = _times select 1;
    };
};
// polar day / night: the sun does not cross the horizon today; it is not
// night now (sunOrMoon above), so no night is coming soon
if (_sunrise < 0 || {_sunset < 0} || {_sunset <= _sunrise}) exitWith {1e6};

private _now = daytime;
if (_now < _sunrise || {_now >= _sunset}) exitWith {0};

((_sunset - _now) * 3600) / (timeMultiplier max 0.1)
