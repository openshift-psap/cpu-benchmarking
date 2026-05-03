# Usage examples

This file complements [README.md](README.md) (overview, troubleshooting) and [README_CODE.md](README_CODE.md) (internals). All commands assume your current working directory is the `cpu-benchmarking` repo root.

## 1. CLI-only benchmark (no JSON)

Uses defaults from `python3 cpu_vllm_bench.py --help`. Container variables come from the orchestrator (`kv_cache_gb`, `hf_home`, `hf_home_container`, etc.); the CLI passes an empty `environment` object internally.

```bash
python3 cpu_vllm_bench.py \
  --model Qwen/Qwen3-1.7B \
  --vllm-image docker.io/vllm/vllm-openai-cpu:v0.18.0 \
  --hf-home /data/huggingface:/models \
  --hf-home-container /models \
  --kv-cache-gb 32 \
  --isl 128 --osl 128 \
  --rate "1,2" \
  --max-seconds 120 \
  --output-base ./results/cli_runs
```

Use Docker instead of Podman:

```bash
CONTAINER_RUNTIME=docker python3 cpu_vllm_bench.py \
  --model Qwen/Qwen3-1.7B \
  --hf-home /data/huggingface:/models \
  --output-base ./results/docker_runs
```

## 2. Suite JSON (`--config`)

Pass one or more suite files; each `runs[]` entry is executed in order.

```bash
python3 cpu_vllm_bench.py \
  --config configs/examples/minimal-suite.json \
  --output-base ./results
```

Multiple configs:

```bash
python3 cpu_vllm_bench.py \
  --config configs/smoke/environment-minimal.json \
  --config configs/smoke/legacy-container-env.json \
  --output-base ./results/smoke_batch
```

## 3. Container environment in JSON (`environment`)

Put Hugging Face and vLLM-related variables in **`environment`** (merged from `defaults`, suite root, then each run). The orchestrator still **overrides** `VLLM_CPU_KVCACHE_SPACE` (from `kv_cache_gb`), inner **`HF_HOME`** (from `hf_home_container`), and `VLLM_CPU_OMP_THREADS_BIND` (from `vllm_omp_threads_bind`) so JSON cannot accidentally point the cache at the wrong path.

Minimal pattern:

```json
{
  "experiment": "my-exp",
  "defaults": {
    "hf_home": "/data/huggingface:/models",
    "hf_home_container": "/models",
    "output_dir": "./results",
    "environment": {
      "HF_TOKEN": "hf_xxx",
      "HF_HUB_OFFLINE": "0",
      "VLLM_CPU_OMP_THREADS_BIND": "auto"
    }
  },
  "runs": [
    {
      "run_name": "qwen-smoke",
      "model": "Qwen/Qwen3-1.7B",
      "kv_cache_gb": 32,
      "isl": 128,
      "osl": 128,
      "rate": "1,2"
    }
  ]
}
```

Per-run override (later layer wins on the same key):

```json
{
  "defaults": {
    "environment": { "HF_HUB_OFFLINE": "1" }
  },
  "runs": [
    {
      "run_name": "offline",
      "model": "Qwen/Qwen3-1.7B"
    },
    {
      "run_name": "online",
      "model": "Qwen/Qwen3-1.7B",
      "environment": { "HF_HUB_OFFLINE": "0" }
    }
  ]
}
```

## 4. Volume bind vs in-container `HF_HOME`

- **`hf_home`** (JSON or `--hf-home`): full **`-v`** argument, e.g. `/host/cache:/models`.
- **`hf_home_container`**: directory **inside** the container used as `-e HF_HOME=...` (typically `/models`).
- **`launch_env`** keys **`HF_HOME`** / **`HF_HOME_CONTAINER`**: override the bind string and inner path only; they are **not** passed as arbitrary extra `-e` values for those two keys (avoids confusing the bind with the inner cache path).

Example:

```json
{
  "defaults": {
    "hf_home": "/default/host:/models",
    "hf_home_container": "/models",
    "launch_env": {
      "HF_HOME": "/special/host:/models",
      "HF_HOME_CONTAINER": "/models"
    },
    "environment": {
      "HF_TOKEN": "hf_xxx"
    }
  },
  "runs": [{ "run_name": "r1", "model": "Qwen/Qwen3-1.7B" }]
}
```

## 5. Legacy keys (`container_env`, `launch_env`)

- **`container_env`**: still merged into the same container env map as `environment` (treat as deprecated; prefer `environment`).
- **`launch_env`**: merged for container `-e` **except** `HF_HOME` / `HF_HOME_CONTAINER`, which only affect bind / inner path as above.

See [configs/smoke/legacy-container-env.json](configs/smoke/legacy-container-env.json).

## 6. Smoke configs (quick validation)

Small models and short `max_seconds` for pipeline checks (edit `hf_home` / paths for your machine):

| File | Notes |
| --- | --- |
| [configs/smoke/environment-minimal.json](configs/smoke/environment-minimal.json) | Uses canonical `environment`. |
| [configs/smoke/legacy-container-env.json](configs/smoke/legacy-container-env.json) | Uses `container_env` only. |
| [configs/smoke/suite-root-environment.json](configs/smoke/suite-root-environment.json) | Suite-level + per-run `environment`. |
| [configs/smoke/test1.json](configs/smoke/test1.json) | Heavier Llama settings; set tokens/paths locally. |

```bash
python3 cpu_vllm_bench.py --config configs/smoke/environment-minimal.json --output-base ./results/smoke
```

## 7. Optional files

**Extra `-e` from a host file** (merged before JSON `environment`; orchestrator overrides still win where applicable):

```bash
python3 cpu_vllm_bench.py \
  --config configs/examples/minimal-suite.json \
  --extra-env-file ./secrets.env \
  --output-base ./results
```

**Extra `podman run` arguments** (each non-comment line in the file is parsed with `shlex` and inserted **before** `-v`; same placement as the legacy shell script):

```json
{
  "defaults": {
    "extra_docker_run_file": "/path/to/extra_run.args"
  }
}
```

## 8. MLflow and dashboard

```bash
export MLFLOW_TRACKING_URI=http://127.0.0.1:5000
python3 cpu_vllm_bench.py \
  --config configs/examples/minimal-suite.json \
  --mlflow \
  --dashboard-csv ./results/consolidated_dashboard.csv
```

## 9. ISL sweep on one CPU (OSL fixed to 1)

Suite [configs/examples/isl-sweep-single-cpu-osl1.json](configs/examples/isl-sweep-single-cpu-osl1.json) runs **17** GuideLLM/vLLM cycles with **OSL = 1** and **ISL** stepping from **16** through **2048** (denser steps at small ISL). Defaults pin the server to **logical CPU 0** (`server_cpulist`, `omp_num_threads`, and `OMP_NUM_THREADS` / `VLLM_CPU_OMP_THREADS_BIND` in `environment`). **`vllm_extra_args`** sets `--max-model-len 8192` so the largest prompt fits.

```bash
python3 cpu_vllm_bench.py \
  --config configs/examples/isl-sweep-single-cpu-osl1.json \
  --output-base ./results/isl_sweep
```

Edit `hf_home`, `model`, `kv_cache_gb`, `max_seconds`, and Hub flags before running. To add more ISL points, duplicate a `runs[]` object and change `isl` / `run_name`.

## 10. Container entrypoint default vs image CMD

The orchestrator supports two shapes for the trailing part of `podman run` / `docker run` (see `build_container_run_argv` in [README_CODE.md](README_CODE.md)):

### Default (`vllm_use_image_entrypoint` omitted or `false`)

Equivalent to:

```text
… --entrypoint vllm <IMAGE> serve <MODEL> <vllm_extra_args…>
```

This matches the **vLLM OpenAI CPU** images where the image default entrypoint is not `vllm serve`. Example `defaults` snippet:

```json
{
  "vllm_use_image_entrypoint": false,
  "vllm_image": "docker.io/vllm/vllm-openai-cpu:v0.18.0",
  "vllm_extra_args": "--dtype=bfloat16 --max-model-len 4096"
}
```

### Use image `ENTRYPOINT` / `CMD` (`vllm_use_image_entrypoint`: `true`)

Equivalent to:

```text
… <IMAGE> <MODEL>
```

No `--entrypoint vllm` and no `serve` subcommand from the orchestrator; **`vllm_extra_args`** are still appended after the model id (often empty when the image CMD already includes all flags). The image **must** listen on the same port as **`port`** (default **8000**).

Full example suite: [configs/examples/entrypoint-image-default.json](configs/examples/entrypoint-image-default.json).

```bash
python3 cpu_vllm_bench.py --config configs/examples/entrypoint-image-default.json --output-base ./results
```

### Per-run override

Any run can set `"vllm_use_image_entrypoint": true` to override `defaults` for that entry only.

## 11. Manual container start (`run_podman.sh`)

The orchestrator **does not** call `run_podman.sh`. The script remains useful for interactive debugging; see comments at the top of [run_podman.sh](run_podman.sh) and the **Legacy run_podman.sh** section in [README.md](README.md).
