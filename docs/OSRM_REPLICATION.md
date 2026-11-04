# Road-network routing: recovered configuration

## Evidence

The original project log `docs/SESSION_LOG_OSRM_ROAD_DISTANCES.md` (session through May 26, 2026) records the following configuration. These are historical run records, not a new routing validation.

| Component | Recorded configuration |
| --- | --- |
| Map | Geofabrik US extract `us-210101.osm.pbf`, 2021 vintage |
| Algorithm | MLD (Multi-Level Dijkstra) |
| Server | Docker container, port 5000 |
| Recorded server command | `osrm-routed --algorithm mld /data/us-210101.osrm` |
| Compute | AWS EC2 r5.4xlarge, 128 GB RAM; 32 GB and 64 GB runs encountered out-of-memory failures |
| Query | `/table` endpoint, one residence tract source and batched workplace destinations |
| Historical concurrency | 16 worker threads |
| Historical scale | 80,931,663 unique OD tract pairs; 73,057 residence tracts; approximately 26 hours |
| Road panel | 725,622 rows, employment-weighted distance and duration outcomes |

The included query script uses the `driving` API profile and defaults to 8 workers; set `WORKERS=16` to match the logged concurrency. Concurrency alone does not specify the routing engine or map preprocessing.

## Running the included client

Once a compatible OSRM server is prepared and running, and the preceding geometry stage is complete, run from the repository root:

```sh
export OSRM_URL=http://localhost:5000
export WORKERS=16
python code/replicate.py run routing
python code/replicate.py run commuting
```

The runner supplies the client input/output paths. Road distances are converted from meters to kilometers and durations from seconds to minutes. Same-tract distance uses the original centroid-distance fallback. Failed routes remain missing, not zero.

## Details still needed for exact reconstruction

The reviewed log and project documentation do not specify the Docker image tag/digest, OSRM release, extraction Lua profile and its modifications, full preprocessing commands/server flags, or the PBF checksum. The `driving` URL label alone does not establish which extraction profile was used. No local PBF or original server configuration was recovered in this documentation search.

The map filename and MLD algorithm are now known. To certify exact fresh-route replication, recover the original image/configuration or archived route lookup, and compare regenerated routes and aggregate outcomes. The archived map may be sought through [Geofabrik's US download page](https://download.geofabrik.de/north-america/us.html); current availability of this exact historical file has not been verified here. Do not silently substitute a current map.

The log also contains earlier event-study estimates. Those are not the final state-matched paper targets and are deliberately not substituted for the current regression reference CSV.
