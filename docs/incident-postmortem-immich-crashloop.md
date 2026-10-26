# Postmortem: Immich Crash Loop (12,425 Restarts)

**Date:** 2026-10-25  
**Duration:** ~4 hours  
**Impact:** Zero job processing (thumbnails, CLIP embeddings, face recognition, video transcoding)  
**Severity:** SEV-2 (core service degraded, no data loss)

---

## Executive Summary

The Immich photo server entered a crash loop where the main container restarted every ~60 seconds. This prevented the microservices worker from processing any background jobs. The root cause was a missing mount verification file (`.immich`) in the library directory, compounded by incorrect hardware acceleration configuration.

---

## Timeline

| Time (MYT) | Event |
|------------|-------|
| 05:05 | PZ server starts (unrelated) |
| ~08:00 | Immich server begins crash loop (estimated) |
| 12:54 | Cronjob alert: sarvar-api restart counter 7 → 12,425 |
| 13:07 | Investigation starts |
| 13:15 | Root cause identified: missing `.immich` marker file |
| 13:20 | Marker file created, container stabilized |
| 13:30 | Hardware acceleration misconfig discovered (CUDA on GTX 1050 Ti) |
| 13:45 | QuickSync config applied, ML container reconfigured |
| 14:00 | Full pipeline re-index initiated |
| 18:00 | All jobs complete: metadata, thumbnails, faces, CLIP, video |

---

## Root Cause Analysis

### Primary Cause
**Missing `/mnt/Data/immich/upload/library/.immich` marker file**

Immich uses this file to verify the library mount is healthy before starting the microservices worker. Without it, the worker crashes immediately, causing the main process to restart.

### Contributing Factors
1. **Incorrect GPU configuration**: `docker-compose.yml` used `-cuda` tag + nvidia runtime for ML container, but GTX 1050 Ti (4GB VRAM) is insufficient for ML inference → OOM kills
2. **No hardware transcoding**: Intel HD 630 (QuickSync) available but not configured → all transcoding fell back to CPU
3. **No mount validation in healthcheck**: Healthcheck only verified HTTP endpoint, not library mount integrity

---

## Resolution Steps

### 1. Immediate Fix (5 min)
```bash
touch /mnt/Data/immich/upload/library/.immich
docker restart immich_server
```

### 2. Hardware Acceleration Correction (15 min)
- Removed `-cuda` tag and nvidia runtime from `immich-machine-learning`
- Added `hwaccel.transcoding.yml` with `quicksync` service for Intel HD 630
- Set ML container to CPU-only with 6GB memory limit
- Preloaded SigLIP CLIP model (`ViT-B-16-SigLIP__webli`)

### 3. Full Pipeline Re-index (4 hours)
```bash
# Metadata extraction
docker exec immich_server npm run immich:metadata

# Thumbnail generation
docker exec immich_server npm run immich:thumbnails

# Face detection & recognition
docker exec immich_server npm run immich:faces

# CLIP embeddings (semantic search)
docker exec immich_server npm run immich:clip

# Video transcoding (QuickSync accelerated)
docker exec immich_server npm run immich:video-transcode
```

---

## Prevention Measures

| Measure | Implementation |
|---------|----------------|
| **Mount validation in healthcheck** | Add `test: ["CMD", "test", "-f", "/data/library/.immich"]` to healthcheck |
| **Automated backup validation** | Weekly test restore of PostgreSQL dump |
| **Config change review** | All docker-compose changes require peer review (self-review documented) |
| **Hardware inventory doc** | Document GPU capabilities vs. container requirements |
| **Alert on restart rate** | Healthcheck script alerts if restarts > 10/5min |

---

## Metrics

| Metric | Before | After |
|--------|--------|-------|
| Container restarts (24h) | 12,425 | 0 |
| Assets with thumbnails | 0 / 5,496 | 5,496 / 5,496 |
| Assets with CLIP embeddings | 0 / 5,496 | 5,496 / 5,496 |
| Faces recognized | 0 | 4,755 (267 people) |
| Videos transcoded | 0 / 1,977 | 1,977 / 1,977 |
| Transcoding speed (CPU) | ~0.5x | ~4x (QuickSync) |

---

## Lessons Learned

1. **Mount health ≠ container health** — A container can be "running" while its worker processes crash silently
2. **GPU != always better** — 4GB VRAM is insufficient for ML; CPU with optimized models (SigLIP) outperforms OOM'ing GPU
3. **QuickSync is a force multiplier** — Intel iGPU transcoding delivers 4-8x speedup for near-zero cost
4. **Document the "why"** — The CUDA config was copied from a template without validating hardware fit

---

## Action Items

- [x] Add mount check to Immich healthcheck
- [x] Document hardware acceleration decision matrix
- [x] Create automated re-index script (`scripts/reindex-all.sh`)
- [ ] Add restart-rate alerting to monitoring dashboard
- [ ] Schedule quarterly backup restore tests

---

**Author:** Muhammad Amiruddin  
**Reviewed:** Self (solo operator)  
**Next Review:** 2027-01-25
