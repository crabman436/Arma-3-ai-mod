# Reactive army acceptance scenarios

Status: pending in-engine verification. Run with only Coordinated AI enabled,
then repeat with the intended mod set. Enable `CAI_debug = true` and retain the
RPT log, map, mod version, and hosted/dedicated configuration for each run.

## Reinforcement allocation

1. Place a four-man friendly caller, three idle four-man friendly squads, and
   four enemy infantry. Keep squads within QRF range, disable artillery and
   aircraft, and set `CAI_maxResponders = 3; CAI_supportRatio = 1.5;`.
2. Let the caller spot all four enemies. Expected: one squad responds, giving
   eight friendly infantry against a required six; two squads stay available.
3. Allow another request interval. Expected: the existing responder counts;
   no additional squad is sent solely because there are open response slots.
4. Remove casualties from the committed force and add more detected enemies.
   Expected: allocation uses surviving strength and sends more squads only
   when required, up to the cap. No group receives two concurrent QRF jobs.
5. Repeat with vehicle crews: one vehicle contributes once, not once per crew
   member. Repeat with two separate callers to check remaining groups respond
   to the second fight. Record limitations when both callers report one fight.

## Building clearing

1. Sync an infantry squad to Clear Area over an enterable multi-floor house.
   Watch each building position. Expected: success only after every position
   has been reached within two horizontal metres and 1.5 vertical metres, with
   no recent known hostile remaining near the house.
2. Block a route or disable entry-team PATH after assignment. Expected: timeout
   leaves `CAI_cleared_<SIDE>` unchanged, releases the claim, and sets a retry
   delay. Other reachable buildings remain eligible. Restore movement and
   start another clear after the retry delay to verify recovery.
3. Kill the entry team during a room assignment, including just before arrival.
   Expected: unvisited rooms prevent success. A casualty between batches does
   not cause the reduced team to skip positions.
4. Place soldiers directly below upstairs positions. Expected: they do not
   confirm the upstairs rooms until they reach the correct elevation.
5. Interrupt the clear with a commander order while a move is waiting.
   Expected: the old job neither reports success nor issues regroup orders
   over the commander's new orders. Immediately start a replacement clear and
   verify the old job does not cancel it or release its building claim.
6. Repeat with two squads and verify they normally select separate buildings;
   stop one squad and verify its abandoned building becomes eligible again.

## Remaining full-goal gates

The complete reactive-army goal also requires scenario evidence for contact
aging and radio propagation without omniscient pursuit, searching last-known
positions, threat-appropriate combined-arms allocation across simultaneous
engagements, commander attack/defense transitions, transport cancellation,
and dedicated-server/headless-client ownership changes. These are not proven
by the above targeted fixes or by a syntax/build check.
