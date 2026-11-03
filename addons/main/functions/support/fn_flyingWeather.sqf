/*
 * Name: AIC_fnc_flyingWeather
 * Description:
 *   The one weather rule for aircraft (realism E): is the weather good
 *   enough to fly now? Not in fog above AIC_CAS_MAX_FOG or rain above
 *   AIC_CAS_MAX_RAIN; a helicopter also not in a wind stronger than
 *   AIC_HELI_MAX_WIND m/s. Used by AIC_fnc_supportCycle (CAS taskings and
 *   the recall of aircraft already on a sortie) and AIC_fnc_findTransport
 *   (no helicopter rides in such weather). Cheap: three engine reads.
 *
 * Parameters:
 *   0: BOOL - (optional) the aircraft is a helicopter, default false
 *
 * Returns:
 *   BOOL - true if it may fly
 *
 * Example:
 *   private _heliOk = [true] call AIC_fnc_flyingWeather;
 */

#include "\z\aic\addons\main\script_component.hpp"

params [["_heli", false, [false]]];

fog <= AIC_CAS_MAX_FOG
&& { rain <= AIC_CAS_MAX_RAIN }
&& { !_heli || { (vectorMagnitude wind) <= AIC_HELI_MAX_WIND } }
