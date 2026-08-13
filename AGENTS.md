# AGENTS.md — Build Guide for ComfyUI Docker Images

Instructions for AI agents working on this repository. Read before making any changes.

## Overview

This repo builds two Docker images for ComfyUI-based media generation:

| Image | GHCR Tag | Purpose | Size |
|---|---|---|---|
| `ghcr.io/slaid099/image-gen:latest` | `:latest` | Flux image generation (t2i/i2i) | ~33 GB |
| `ghcr.io/slaid099/video-gen:latest` | `:latest` | Wan2.1 video generation (i2v) | ~35 GB |

Images are **public** on GitHub Container Registry (GHCR) under account `slaid099`.

**Builds run on GitHub Actions runners** (not locally). Workflows are triggered manually via `workflow_dispatch`.

## Hard Lessons (DO NOT repeat these mistakes)

### 1. aria2c is FORBIDDEN — use `curl -L -o`
- HuggingFace XET bridge CDN returns **403** for aria2c parallel connections
- Civitai download endpoint returns **307 redirect** — aria2c fails with `0B/s|ERR`
- **Always use `curl -L -o <path> "<url>"`** for all model downloads
- `aria2` package should NOT be installed in Dockerfile

### 2. PowerShell heredoc corrupts YAML
- `@'...'@` heredoc in PowerShell inserts **mid-word newlines** into YAML/JSON
- File looks fine in terminal but is broken on GitHub
- **Use `[System.IO.File]::ReadAllBytes()` + base64 + GitHub Contents API** for commits
- Example commit pattern:
```powershell
$b64 = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($path))
$json = '{"message":"...","content":"' + $b64 + '","sha":"<SHA>","branch":"main"}'
[System.IO.File]::WriteAllText($jsonPath, $json, [System.Text.UTF8Encoding]::new($false))
gh api -X PUT "/repos/slaid099/image-mirror/contents/<path>" --input $jsonPath --jq '.commit.sha'
```

### 3. comfy-kitchen version — sed pattern must be universal
- ComfyUI `requirements.txt` pins `comfy-kitchen` with varying format over time:
  - `comfy-kitchen>=0.2.7` (older)
  - `comfy-kitchen==0.2.28` (current)
- **Use `sed -E 's/^comfy-kitchen.*/comfy-kitchen==0.2.7/'`** — matches ANY version operator
- Do NOT use `sed 's/comfy-kitchen>=.*/.../'` — breaks when format changes to `==`
- See "Version Pinning" section below for why 0.2.7

### 4. Do NOT use `--password-stdin` for GHCR login in Actions
- PAT `ghp_...` fails `docker login ghcr.io --password-stdin` in GitHub Actions (`denied: denied`)
- **Use `-p` flag**: `docker login ghcr.io -u slaid099 -p ${{ secrets.GHCR_PAT }}`

### 5. ComfyUI HEAD after 11 Aug 2026 requires `comfy_kitchen.int8_attention_is_available()`
- ComfyUI PR #15479 (commit `bf4c9a08`, merged 11 Aug 2026) calls `comfy_kitchen.int8_attention_is_available()` at startup
- This function does **not exist** in pinned `comfy-kitchen==0.2.7` → `AttributeError` → ComfyUI crash
- `comfy-kitchen==0.2.30+` has the function, but **breaks on torch 2.6.0** (`list[int]` PEP 585 bug in `na.py`)
- **Fix**: pin ComfyUI itself to commit `4f3544d1` (last commit before PR #15479) via `git checkout` after clone
- See "Version Pinning → ComfyUI commit pin" below for the exact Dockerfile pattern

## Version Pinning

### comfy-kitchen == 0.2.7 (CRITICAL)

| Version | requires_python | Date | Works with torch 2.6? |
|---|---|---|---|
| 0.1.0 | `>=3.12` | 2025-12-26 | NO (base image has Python 3.11.11) |
| **0.2.7** | **`>=3.10`** | **2026-01-17** | **YES — proven working** |
| 0.2.28 | `>=3.10` | 2026-08-07 | NO — `list[int]` bug in `na.py:163` |

**Bug in 0.2.28+**: `comfy_kitchen/backends/eager/na.py:163` uses PEP 585 `list[int]` annotation in `@torch.library.custom_op`. `torch.library.infer_schema` in torch 2.6.0 doesn't support `list[int]` (only `typing.List[int]`/`typing.Sequence[int]`). Result: `ValueError` at import → ComfyUI never starts. (0.2.27 is working — the bug in `na.py` appeared only in 0.2.28.)

**0.2.7 is the last working version** — proven in `video-gen:v2` (built Feb 28 2026, used successfully through Aug 2026).

### ComfyUI commit pin (CRITICAL — after 11 Aug 2026)

ComfyUI `HEAD` on `master` after 11 Aug 2026 (PR #15479, commit `bf4c9a08`) calls `comfy_kitchen.int8_attention_is_available()` at startup. This function doesn't exist in pinned `comfy-kitchen==0.2.7` → `AttributeError`. Versions `0.2.30+` have the function but break on torch 2.6.0 (see comfy-kitchen table above). **Pin ComfyUI itself** to commit `4f3544d1` (last commit before PR #15479):

```dockerfile
WORKDIR /workspace/ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI . && \
    git checkout 4f3544d131652678c8070b306f01cce392465cb5
```

Do NOT use `git clone --depth 1` — shallow clones may not contain the pinned commit. Full clone + checkout is ~5 MB extra, negligible vs the 33 GB image.

### torch/torchvision/torchaudio — keep 2.6.0 from base image

Base image `pytorch/pytorch:2.6.0-cuda12.6-cudnn9-runtime` ships torch 2.6.0+cu126 (Python 3.11.11, conda). This tag is **stable since Jan 2025** (digest `sha256:f894dae26e1ee8557c544f9cfdb9dc011b1552bf3c1e656b422f2e221d380e40`, never changed).

ComfyUI `requirements.txt` says just `torch` (no version) → pip/uv installs latest 2.9.1 → comfy-kitchen 0.2.7 may break on newer torch.

**Remove torch from requirements before install:**
```dockerfile
RUN sed -i -E 's/^comfy-kitchen.*/comfy-kitchen==0.2.7/' requirements.txt && \
    sed -i '/^torch$/d;/^torchvision$/d;/^torchaudio$/d' requirements.txt && \
    uv pip install --system --break-system-packages -r requirements.txt
```

UV is the package manager (NOT pip). Keep `uv pip install --system --break-system-packages`.

## Build Workflows

### build-image-gen.yml
- Trigger: `workflow_dispatch` (manual)
- Runner: `ubuntu-latest`
- Steps: checkout → download LoRA from Forgejo → copy Dockerfile+start.sh → `docker build --build-arg CIVITAI_TOKEN=...` → login GHCR (PAT) → push
- ~12 min build + ~5 min push (33 GB)

### build-video-gen.yml
- Same structure as image-gen
- No Forgejo LoRA download (video-gen uses Civitai LoRAs only)
- ~15 min build + ~5 min push (35 GB)

### test-push.yml
- Dummy alpine build + push to `ghcr.io/slaid099/image-gen:latest`
- Verifies GHCR_PAT works in Actions before running full build
- Use after changing PAT or login method

### mirror.yml
- Mirrors GHCR images to Docker Hub (`slaid098/image-gen:latest`, `slaid098/video-gen:latest`)
- Uses `DOCKERHUB_USERNAME` + `DOCKERHUB_TOKEN` secrets

## Secrets (names only — values via `gh secret set`)

| Secret | Used by | Purpose |
|---|---|---|
| `GHCR_PAT` | build-image-gen, build-video-gen, test-push | Push to GHCR (PAT with `write:packages` scope) |
| `CIVITAI_TOKEN` | build-image-gen, build-video-gen | Download models from Civitai (`?token=...` in URL) |
| `FORGEJO_TOKEN` | build-image-gen | Download LoRA from Forgejo Packages (`Authorization: token ...` header) |
| `DOCKERHUB_USERNAME` | mirror | Docker Hub account |
| `DOCKERHUB_TOKEN` | mirror | Docker Hub access token |

## Repository Structure

```
slaid099/image-mirror/
├── AGENTS.md                          # This file
├── build/
│   ├── image-gen/
│   │   ├── Dockerfile                 # Flux image-gen (Dockerfile.full + fixes)
│   │   └── start.sh                    # ComfyUI startup (SSH + env + python main.py)
│   └── video-gen/
│       ├── Dockerfile                 # Wan2.1 video-gen (Dockerfile.fast + fixes)
│       └── start.sh                   # ComfyUI startup (same structure)
└── .github/
    └── workflows/
        ├── build-image-gen.yml         # Manual build + push to GHCR
        ├── build-video-gen.yml         # Manual build + push to GHCR
        ├── test-push.yml              # PAT verification (dummy alpine)
        └── mirror.yml                  # GHCR → Docker Hub mirror
```

## Model Downloads

### image-gen (Flux)

| Model | Destination | Source | Civitai version ID |
|---|---|---|---|
| flux1-dev-fp8.safetensors | `unet/` | `https://huggingface.co/Kijai/flux-fp8/resolve/main/flux1-dev-fp8.safetensors` | — |
| t5xxl_fp8_e4m3fn.safetensors | `clip/` | `https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors` | — |
| clip_l.safetensors | `clip/` | `https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors` | — |
| ae.safetensors | `vae/` | `https://huggingface.co/SicariusSicariiStuff/FLUX.1-dev/resolve/main/ae.safetensors` | — |
| n0k1a.safetensors | `loras/` | `https://civitai.com/api/download/models/2046810?type=Model&format=SafeTensor&token=${CIVITAI_TOKEN}` | 2046810 |
| real_skin.safetensors | `loras/` | `https://civitai.com/api/download/models/1026423?token=${CIVITAI_TOKEN}` | 1026423 |
| hyper_flux_8step.safetensors | `loras/` | `https://huggingface.co/ByteDance/Hyper-SD/resolve/main/Hyper-FLUX.1-dev-8steps-lora.safetensors` | — |
| FemaleBody_milf_9.safetensors | `loras/` | Forgejo Packages: `https://git.slaid098.dev/api/packages/slaid098/generic/loras/1.0.0/FemaleBody_milf_9.safetensors` (header: `Authorization: token ${FORGEJO_TOKEN}`) | — |
| 4x-UltraSharp.pth | `upscale_models/` | `https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth` | — |

### video-gen (Wan2.1)

| Model | Destination | Source | Civitai version ID |
|---|---|---|---|
| wanLOVELowVRAMImageTo_i2v14BFp8.safetensors | `checkpoints/` | `https://civitai.com/api/download/models/2129615?token=${CIVITAI_TOKEN}` | 2129615 |
| intimate_handheld_grainy_video.safetensors | `loras/` | `https://civitai.com/api/download/models/1865295?token=${CIVITAI_TOKEN}` | 1865295 |
| motion_craft.safetensors | `loras/` | `https://civitai.com/api/download/models/1599906?token=${CIVITAI_TOKEN}` | 1599906 |
| round_body_rotation.safetensors | `loras/` | `https://civitai.com/api/download/models/1683094?token=${CIVITAI_TOKEN}` | 1683094 |
| 4x-UltraSharp.pth | `upscale_models/` | `https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth` | — |
| codeformer.pth | `facerestore_models/` | `https://github.com/sczhou/CodeFormer/releases/download/v0.1.0/codeformer.pth` | — |
| rife47.pth | `custom_nodes/ComfyUI-Frame-Interpolation/ckpts/rife/` | `https://huggingface.co/jasonot/mycomfyui/resolve/main/rife47.pth` | — |
| clip_vision_h.safetensors | `clip_vision/` | `https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors` | — |

### Custom nodes (video-gen only)

| Node | Repo |
|---|---|
| ComfyUI-Manager | `https://github.com/ltdrdata/ComfyUI-Manager.git` |
| ComfyUI-WanVideoWrapper | `https://github.com/Kijai/ComfyUI-WanVideoWrapper.git` |
| ComfyUI-VideoHelperSuite | `https://github.com/Kijai/ComfyUI-VideoHelperSuite.git` |
| ComfyUI-Frame-Interpolation | `https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git` |
| facerestore_cf | `https://github.com/mav-rik/facerestore_cf.git` |
| ComfyUI-KJNodes | `https://github.com/kijai/ComfyUI-KJNodes.git` |

## Vast.ai — Testing New Models

### Workflow: test → pin → rebuild

1. **Rent instance** via Vast.ai REST API
2. **Wait for image pull** (~5-10 min, 33-35 GB) — check `status_msg` for `success, running`
3. **SSH into instance**: `ssh -o StrictHostKeyChecking=no root@<ssh_host> -p <ssh_port>`
4. **Download new model**: `curl -L -o /workspace/ComfyUI/models/<dest>/<name> "<url>"`
5. **Verify ComfyUI**: `curl -s -o /dev/null -w '%{http_code}' http://localhost:8188/` → 200
6. **User tests in browser**: `http://<public_ip>:<direct_port>` (port 8188 mapped to direct port)
7. **If works** → add `curl -L` line to Dockerfile → trigger build workflow
8. **Kill instance** via REST API

### Vast.ai REST API

```
API key: stored in secret (ask user)
Base URL: https://console.vast.ai/api/v0/

List instances:
  GET /instances/
  Headers: { "Authorization": "Bearer <API_KEY>" }

Kill instance:
  DELETE /instances/<id>/
  Body: { "id": <id> }
  Headers: { "Authorization": "Bearer <API_KEY>" }
```

### Instance fields (from list response)

| Field | Meaning |
|---|---|
| `id` | Instance ID (for kill) |
| `gpu_name` | GPU model (L40S, RTX 4090, RTX 6000Ada, etc.) |
| `cur_state` | `running` / `loading` |
| `status_msg` | Docker pull progress or `success, running <image>` |
| `public_ipaddr` | Public IP for browser access |
| `ssh_host` + `ssh_port` | SSH endpoint (`ssh root@<host> -p <port>`) |
| `ports.8188/tcp[0].HostPort` | Direct port for ComfyUI web UI |

### GPU presets (from digital_factory)

| Preset | GPUs | Use case |
|---|---|---|
| FAST | L40S, RTX 4090 | Fastest generation |
| DEFAULT | L40, RTX 6000Ada, RTX 5880Ada, RTX 5000Ada, RTX A6000, RTX PRO 6000 S/WS | Cheaper, slower |

Search filters: `num_gpus=1, gpu_ram>=30, rentable=true, verified=true, inet_down>=500, reliability>=0.90, dph_total<=0.8`

### SSH config

SSH key: use key from `D:\Python projects\opencode\config\ssh\id_ed25519` (or equivalent on agent's VPS).

```
ssh -o StrictHostKeyChecking=no -i <key> root@<ssh_host> -p <ssh_port>
```

## Adding a New Model — Step by Step

### User provides:
1. Model URL (Civitai / HuggingFace / other)
2. Destination: `loras/`, `checkpoints/`, `unet/`, `vae/`, `clip/`, `clip_vision/`, `upscale_models/`, `facerestore_models/`
3. Which image: `image-gen` or `video-gen`

### Agent steps:

1. **Determine Civitai version ID** (if Civitai URL):
   ```bash
   curl -s "https://civitai.com/api/v1/models/<model_id>" | jq '.modelVersions[0].id'
   ```
   Download URL format: `https://civitai.com/api/download/models/<version_id>?token=${CIVITAI_TOKEN}`

2. **Rent Vast.ai instance** (FAST preset: L40S or RTX 4090)

3. **Wait for boot** — poll `status_msg` until `success, running`

4. **SSH + download model into running container**:
   ```bash
   ssh root@<ssh_host> -p <ssh_port> \
     "curl -L -o /workspace/ComfyUI/models/<dest>/<filename> '<url>'"
   ```

5. **Verify ComfyUI responds** (HTTP 200)

6. **Tell user**: `http://<public_ip>:<direct_port>` — test in browser

7. **If user confirms working**:
   - Add `RUN curl -L -o <dest>/<filename> "<url>"` to `build/<image>/Dockerfile`
   - Commit via Contents API (base64)
   - Trigger `build-<image>-gen.yml` workflow
   - Wait for build + push (~15-20 min)
   - New `:latest` tag on GHCR now includes the model

8. **Kill test instance** (economy)

### If model is 18+ (NSFW)
- Upload to Forgejo Packages (generic): `PUT /api/packages/slaid098/generic/loras/1.0.0/<filename>`
- In Dockerfile: download via `curl -L -H "Authorization: token ${FORGEJO_TOKEN}" -o <dest>/<filename> "<forgejo_url>"`
- Forgejo base URL: `https://git.slaid098.dev`

## GHCR Notes

- Packages are **user-namespace** (`ghcr.io/slaid099/<name>`), not repo-namespace
- `image-gen` package has `repository: null` (not linked to any repo) — `GITHUB_TOKEN` CANNOT push to it (`permission_denied: write_package`)
- REST API to link package returns 404 for user-namespace packages — only web UI can link
- **Always use `GHCR_PAT` secret** for push, never `GITHUB_TOKEN`
- Package visibility: **public** (free, no storage limit)
- Versions accumulate — old untagged versions can be deleted via API if needed

## Commits

Use Conventional Commits style:
- `feat(video-gen): add Dockerfile with comfy-kitchen==0.2.7 pin`
- `fix(image-gen): pin comfy-kitchen==0.2.7 (0.2.x crashes on torch 2.6.0)`
- `chore: update model URLs`

## What NOT to do

- Do NOT use `aria2c` for any downloads (HF or Civitai) — use `curl -L -o`
- Do NOT use PowerShell heredoc for YAML/JSON commits — use base64 + Contents API
- Do NOT use `GITHUB_TOKEN` for GHCR push — use `GHCR_PAT` secret with `-p` flag
- Do NOT use `--password-stdin` for docker login in Actions — use `-p` flag
- Do NOT pin `comfy-kitchen==0.1.0` — it requires Python>=3.12 (base image has 3.11.11)
- Do NOT leave torch/torchvision/torchaudio in requirements.txt — remove via sed, keep 2.6.0 from base
- Do NOT use `sed 's/comfy-kitchen>=.*/.../'` — format changes; use `sed -E 's/^comfy-kitchen.*/.../'`
- Do NOT install `aria2` package in Dockerfile — not needed with curl