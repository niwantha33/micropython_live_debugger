# Source branch inventory

Historical branches retain useful source history. Closing or archiving a branch is not an approval to publish firmware. Before removing an obsolete branch, preserve its tip with a remote archive tag and verify the tag's SHA. Never delete a branch required by an open PR or referenced firmware provenance.

## Retain

| Branch | Reason |
| --- | --- |
| main | Default source history |
| fix/rp2-paused-global-scope | Current integrated RP2 candidate, PR #13 |
| fix/pico-frozen-rta-integration-candidate | Pinned weekly candidate source |
| feature/pico-frozen-debugger-v1 | Historical Pico W release provenance |
| feature/esp32-s3-debugger-v1 | Current ESP32-S3 source and release references, PR #4 |
| feature/esp32-c3-feasibility-v1 | Historical C3 notes; preserve until source identity is established |
| docs/clarify-firmware-source-repository | Documentation PR #14; remove only after merge and review |

## Historical branches eligible for archive after preserving remote tags

| Branch | Reviewed tip | Reason |
| --- | --- | --- |
| feature/rta-live-name-metadata | fdd1cb6398d6df435984a6a5fdef5fc3bd3df018 | Merged into main |
| fix/rta-runtime-events | 5c6afc300719a680f7a2fa0ffc22a6d240d2aea1 | Merged into main |
| fix/firmware-publish-auth | 70f123af6222e5be428bcca59353df28e566dd9c | Historical merged PR #3; preserve divergent tip |
| feature/rta-runtime-name-replies-v1 | 2ee29956856ba6ecc5cbd2bfac847a38eca45afd | Superseded experimental RTA encoder |
| diag/esp32-rta-wdt-ff9f4d8 | 5027b21c2f382265fb619111c7cf6ddf47dfbba4 | Closed diagnostic PR #5; preserve unique diagnostic work |
| esp32s3-port | 6bf2c9bd76e2dde01d6f15bcf7162ec5a183371e | Historical port notes; preserve unique commit |
| feature/poke-variables | ca189cde275c21e6baa935a2dd806e8edcb441a7 | Historical experimental branch; preserve unique patches, not a release candidate |

The table records the reviewed tips, not a statement that branches have been deleted. If any branch moves, re-review before deleting it. All existing distribution pins are unchanged.
