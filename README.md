# cpu-benchmarking

Orchestration for **vLLM in Podman** (or Docker via `CONTAINER_RUNTIME`) plus **GuideLLM** load tests: build the `podman|docker run` argv in Python, start the server detached, sample host metrics, run GuideLLM, stop the container, optionally write dashboard CSV / plots and upload to MLflow.

- **Code structure**: [README_CODE.md](README_CODE.md)
- **Copy-paste examples**: [README_USAGE.md](README_USAGE.md)

## Layout

- **`cpu_vllm_bench.py`** — Orchestrator; constructs the container command and runs it via `subprocess` (no `bash run_podman.sh` in the default path).
- **`guidellm_env/bin/guidellm`** next to this script is preferred over `~/guidellm_env/bin/guidellm`. Override with `--guidellm-bin`, JSON `guidellm_bin`, or `guidellm_venv`.
- **`run_podman.sh`** — Optional **manual** launcher for debugging; see [Legacy run_podman.sh](#legacy-run_podmansh).

## Prerequisites

- **Container runtime**: Podman (default) or Docker on `PATH`; override with `--container-runtime` or `CONTAINER_RUNTIME`.
- **Host tools**: `numactl` (server and GuideLLM are launched under NUMA bind), Python 3.
- **GuideLLM**: install the CLI and ensure the binary exists (see above).
- **vLLM image**: e.g. `docker.io/vllm/vllm-openai-cpu:v0.18.0` (`--vllm-image` or JSON `vllm_image`).
- **Models / cache**: set **`hf_home`** (host:container bind for `podman run -v`) and **`hf_home_container`** (in-container cache root; passed as `-e HF_HOME=...`). Optionally override the bind with **`launch_env.HF_HOME`** / **`launch_env.HF_HOME_CONTAINER`** (merged across suite layers). Tokens and Hub flags belong in JSON **`environment`** (see below).

Optional:

- **MLflow**: `pip install mlflow`; set `MLFLOW_TRACKING_URI` (e.g. `http://127.0.0.1:5000`) to match `mlflow server`.
- **Dashboard CSV / graphs**: performance-dashboard `import_manual_runs_json_v2.py` via `--import-script`; graphs need `matplotlib` and `pandas`.

## Quick start (CLI only)

From this directory:

```bash
python3 cpu_vllm_bench.py \
  --model Qwen/Qwen3-1.7B \
  --vllm-image docker.io/vllm/vllm-openai-cpu:v0.18.0 \
  --hf-home /path/on/host:/models \
  --hf-home-container /models \
  --isl 128 --osl 128 --rate "1,2" \
  --output-base ./results
```

Add `--mlflow` (and/or `--mlflow-tracking-uri`) to log a run. Use `--no-mlflow` to force-disable when the env sets `MLFLOW_TRACKING_URI`.

More examples: [README_USAGE.md](README_USAGE.md).

## Suite JSON (`--config`)

Pass one or more JSON files; each file is executed in order. Every file must contain a **`runs`** array.

### Shallow merge (per run)

Merge order: **`defaults`** → suite-level tooling keys → each **`runs[]`** object. Tooling keys copied from the suite root include: `guidellm_bin`, `guidellm_venv`, `guidellm_env`, `run_podman_script` (ignored by the launcher; kept for documentation / old configs), `hf_home`, `hf_home_container`, `hf_cache_volume`.

### Deep merge: `launch_env` (bind overrides only for two keys)

**`launch_env`** is merged from `defaults`, suite root, and each run via **`merge_launch_env_from_json_layers()`**. Keys **`HF_HOME`** and **`HF_HOME_CONTAINER`** override the top-level `hf_home` / `hf_home_container` for the **volume bind** and **inner** `-e HF_HOME=...`. Other `launch_env` keys are **also** folded into the container **`environment`** merge (same as `environment` / `container_env`), except those two bind keys which are not duplicated as arbitrary `-e` values.

### Deep merge: `environment` (normal way for container `-e`)

Use the **`environment`** object for Hugging Face tokens, `HF_HUB_OFFLINE`, extra vLLM variables, etc. Merged across **`defaults`**, suite root, and each run (later wins on the same key). Deprecated alias: **`container_env`** (same merge).

The orchestrator **always** reapplies `kv_cache_gb` → `VLLM_CPU_KVCACHE_SPACE`, `hf_home_container` → inner `HF_HOME`, and `vllm_omp_threads_bind` after your JSON so benchmark settings stay consistent.

### Optional suite keys

| Key | Purpose |
| --- | --- |
| `defaults` | Merged into each run before run-specific fields. |
| `experiment` | Default MLflow experiment name. |
| `mlflow_tags` | Default tags (merged with per-run `mlflow_tags`). |
| `environment` | Container `-e` variables (merged across layers). |
| `container_env` | Deprecated; merged like `environment`. |
| `launch_env` | Bind overrides (`HF_HOME`, `HF_HOME_CONTAINER`) + other keys merged into container env (except the two bind keys as `-e`). |
| `guidellm_bin` / `guidellm_venv` / `guidellm_env` | GuideLLM binary and subprocess env. |
| `hf_home` / `hf_home_container` / `hf_cache_volume` | Volume bind and inner cache path (`hf_cache_volume` is a deprecated alias for `hf_home`). |
| `extra_docker_run_file` | File of extra `run` argv lines (parsed with `shlex`, inserted before `-v`). |
| `extra_env_file` | Host file of `KEY=value` lines merged into container env before JSON `environment`. |
| `vllm_use_image_entrypoint` | If `true`, run `IMAGE MODEL` only (use the image’s `ENTRYPOINT`/`CMD`). If `false` (default), run `--entrypoint vllm … serve MODEL` plus `vllm_extra_args`. See section 10 in [README_USAGE.md](README_USAGE.md). |

Before each container start, the orchestrator **prints** and saves **`podman_launch_preview.txt`**: the **exact argv** used (`numactl` / `taskset` + `podman|docker run ...`).

## Example JSON files (in-repo)

| File | Purpose |
| --- | --- |
| [configs/examples/minimal-suite.json](configs/examples/minimal-suite.json) | Smallest suite: shared `defaults`, one run. Edit `hf_home`, `output_dir`, model. |
| [configs/examples/suite-with-tooling-paths.json](configs/examples/suite-with-tooling-paths.json) | Suite-level paths for GuideLLM; optional `run_podman_script` is ignored by the Python launcher. |
| [configs/smoke/environment-minimal.json](configs/smoke/environment-minimal.json) | Smoke: canonical **`environment`**. |
| [configs/smoke/legacy-container-env.json](configs/smoke/legacy-container-env.json) | Smoke: deprecated **`container_env`**. |
| [configs/smoke/suite-root-environment.json](configs/smoke/suite-root-environment.json) | Smoke: suite root + per-run **`environment`**. |
| [configs/smoke/test1.json](configs/smoke/test1.json) | Larger Llama-style settings; set secrets locally. |
| [configs/examples/isl-sweep-single-cpu-osl1.json](configs/examples/isl-sweep-single-cpu-osl1.json) | Single CPU (`server_cpulist`, `omp_num_threads`), **OSL=1**, ISL grid **16–2048** (17 runs). |
| [configs/examples/entrypoint-image-default.json](configs/examples/entrypoint-image-default.json) | **`vllm_use_image_entrypoint`: true** — rely on image `ENTRYPOINT`/`CMD`. |

Minimal suite (inline copy):

```json
{
  "experiment": "example-minimal",
  "defaults": {
    "server_numa": 0,
    "client_numa": 0,
    "max_seconds": 60,
    "isl": 128,
    "osl": 128,
    "rate": "1,2",
    "kv_cache_gb": 32,
    "vllm_image": "docker.io/vllm/vllm-openai-cpu:v0.18.0",
    "vllm_extra_args": "--dtype=bfloat16",
    "hf_home": "/path/on/host/models:/models",
    "hf_home_container": "/models",
    "output_dir": "./results",
    "environment": {
      "HF_HUB_OFFLINE": "1"
    }
  },
  "runs": [
    { "run_name": "example-qwen-smoke", "model": "Qwen/Qwen3-1.7B" }
  ]
}
```

Run a bundled example (after editing paths inside the JSON):

```bash
python3 cpu_vllm_bench.py \
  --config configs/examples/minimal-suite.json \
  --output-base ./results
```

## Legacy run_podman.sh

The shell script is **not** used by `cpu_vllm_bench.py`. It remains useful for foreground or ad-hoc detached runs. It reads the same conceptual variables (`MODEL`, `HF_HOME`, `VLLM_CPU_KVCACHE_SPACE`, …); see the header comments in [run_podman.sh](run_podman.sh).

### Minimal foreground run

```bash
cd /path/to/cpu-benchmarking
MODEL=Qwen/Qwen3-1.7B \
VLLM_CPU_KVCACHE_SPACE=64 \
HF_HOME=/srv/huggingface:/models \
HF_HOME_CONTAINER=/models \
bash run_podman.sh
```

### Detached (similar flags to the Python path)

```bash
MODEL=Qwen/Qwen3-1.7B \
VLLM_IMAGE=docker.io/vllm/vllm-openai-cpu:v0.18.0 \
VLLM_EXTRA_ARGS='--dtype=bfloat16 --max-model-len 4096' \
PORT=8000 \
HF_HOME=/srv/huggingface:/models \
HF_HOME_CONTAINER=/models \
VLLM_CPU_KVCACHE_SPACE=128 \
SERVER_NUMA_NODE=1 \
CONTAINER_NAME=vllm-bench-001 \
DETACHED=1 \
REPLACE_CONTAINER=1 \
bash run_podman.sh
```

## Troubleshooting

### `LocalEntryNotFoundError` / “outgoing traffic has been disabled”

From Hugging Face Hub when **`HF_HUB_OFFLINE=1`** is set in **`environment`** (or legacy `container_env`) **and** the model is not fully cached under your mount.

- **Offline**: pre-populate the cache under the host path you bind into the container.
- **Online**: set **`HF_HUB_OFFLINE`** to `0` or remove it from **`environment`**.

### Wrong or missing model files in the container

Ensure **`hf_home`** is the exact **`host:container`** string for **`podman run -v`**, and **`hf_home_container`** matches the in-container layout Hub/vLLM expect (often `/models`). Inner **`HF_HOME`** in the container is set from **`hf_home_container`**, not from a bind string in **`environment`**.

## Useful CLI flags

- **`--guidellm-bin`**: explicit GuideLLM binary.
- **`--container-runtime`**: `podman` or `docker` (or env `CONTAINER_RUNTIME`).
- **`--server-numa` / `--client-numa`**: NUMA node for vLLM vs GuideLLM client.
- **`--kv-cache-gb`**: integer GiB for `VLLM_CPU_KVCACHE_SPACE`.
- **`--ready-timeout`**: seconds to wait for `/health` or `/v1/models`.
- **`--extra-env-file`**: host file of `KEY=value` lines merged into container env.
- **`--extra-docker-run-file`**: extra `run` argv lines (before `-v`).
- **`--dashboard-csv`**: append dashboard-format rows to a shared CSV (each run still writes `dashboard_benchmark.csv` under its run directory when GuideLLM JSON exists).
- **`--import-script`**, **`--dashboard-version`**, **`--dashboard-tp`**, **`--dashboard-accelerator`**, **`--dashboard-guidellm-version`**: passed through to the dashboard import helper.

Run `python3 cpu_vllm_bench.py --help` for the full list.

## Wrapper script

`run_benchmark.sh` is an example that passes `--config`, dashboard CSV, image tag, and MLflow-related flags. Edit paths and variables before use.

## Artifacts per run

Under each run directory (`output_dir` / `--output-base` + run slug): GuideLLM JSON and logs, `run_config.json`, `run_manifest.json`, `podman_launch_preview.txt` (full argv), `container_environment_resolved.env` (redacted), `vllm_server.log`, `host_samples.tsv`, system capture files, optional `dashboard_benchmark.csv` and PNG graphs.
