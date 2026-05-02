# cpu-benchmarking

Orchestration for **vLLM in Podman** (or Docker via `CONTAINER_RUNTIME`) plus **GuideLLM** load tests: start the server, sample host metrics, run GuideLLM, stop the container, optionally write dashboard CSV / plots and upload to MLflow.

For a file-by-file map of `cpu_vllm_bench.py`, see [README_CODE.md](README_CODE.md).

## Layout

Place **`run_podman.sh`** in the same directory as `cpu_vllm_bench.py`, or in your current working directory when you launch the benchmark. The script picks the first existing path in this order: next to `cpu_vllm_bench.py`, then `./run_podman.sh` under the process CWD, then `~/run_podman.sh`. Override with `--run-podman-script` or JSON `run_podman_script`.

Similarly, **`guidellm_env/bin/guidellm`** next to `cpu_vllm_bench.py` is preferred over `~/guidellm_env/bin/guidellm`. Override with `--guidellm-bin`, `guidellm_bin`, or `guidellm_venv` in JSON.

## Prerequisites

- **Container runtime**: Podman (default) or Docker; set `CONTAINER_RUNTIME` if not using Podman.
- **Host tools**: `numactl` (GuideLLM is launched under NUMA bind), `bash`, Python 3.
- **GuideLLM**: install the CLI and ensure the binary exists (see defaults above).
- **vLLM image**: e.g. `vllm/vllm-openai-cpu:v0.18.0` (override with `--vllm-image` or JSON `vllm_image`).
- **Models**: `run_podman.sh` uses **`HF_HOME`** as the **`-v` bind** in `host_path:container_path` form, and **`HF_HOME_CONTAINER`** as the directory inside the container (see examples below). Set these from JSON (`hf_home`, `hf_home_container`) or CLI (`--hf-home`, `--hf-home-container`).

Optional:

- **MLflow**: `pip install mlflow`; set `MLFLOW_TRACKING_URI` (e.g. `http://127.0.0.1:5000`) to match `mlflow server`.
- **Dashboard CSV / graphs**: performance-dashboard `import_manual_runs_json_v2.py` path via `--import-script`; graphs need `matplotlib` and `pandas`.

## Quick start (CLI only)

From this directory:

```bash
python3 cpu_vllm_bench.py \
  --model Qwen/Qwen3-1.7B \
  --vllm-image vllm/vllm-openai-cpu:v0.18.0 \
  --hf-home /path/on/host:/models \
  --isl 128 --osl 128 --rate "1,2" \
  --output-base ./results
```

Add `--mlflow` (and/or `--mlflow-tracking-uri`) to log a run. Use `--no-mlflow` to force-disable when the env sets `MLFLOW_TRACKING_URI`.

## Suite JSON (`--config`)

Pass one or more JSON files; each file is executed in order. Every file must contain a **`runs`** array. Optional top-level keys:

| Key | Purpose |
| --- | --- |
| `defaults` | Merged into each run before run-specific fields. |
| `experiment` | Default MLflow experiment name. |
| `mlflow_tags` | Default tags (merged with per-run `mlflow_tags`). |
| `guidellm_bin` | Path to the `guidellm` executable (string). |
| `guidellm_venv` | Virtualenv root; binary used is `<venv>/bin/guidellm` if `guidellm_bin` is not set. |
| `guidellm_env` | Object of extra environment variables for the GuideLLM subprocess only (e.g. `PATH`, `HTTP_PROXY`). |
| `run_podman_script` | Path to `run_podman.sh`. |
| `hf_home` | Volume bind passed to `run_podman.sh` as `HF_HOME` (string `host:container`, e.g. `/data/hf:/models`). |
| `hf_home_container` | In-container cache path; passed as `HF_HOME_CONTAINER` (default often `/models`). |
| `hf_cache_volume` | Deprecated alias for `hf_home` (same as in CLI). |

Per-run objects in `runs` can override any of the above. Merge order: `defaults` → suite-level keys (`guidellm_*`, `run_podman_script`, `hf_home`, `hf_home_container`, `hf_cache_volume`) → each run entry.

Before each container start, the orchestrator **prints** (and saves under the run directory as **`podman_launch_preview.txt`**) the environment passed into `run_podman.sh` and a **reconstructed** `podman run` / `docker run` one-liner that should match `run_podman.sh` (file-based `EXTRA_ENV_FILE` / `EXTRA_DOCKER_RUN_FILE` expansions are called out in comments there).

## `run_podman.sh` usage examples

The script reads **environment variables** and runs **`numactl`** (and optionally **`taskset`**) in front of **`podman run`** or **`docker run`**. The orchestrator always sets `DETACHED=1` and `REPLACE_CONTAINER=1` when it calls the script.

### Minimal foreground run (same shell, logs attached)

```bash
cd /path/to/cpu-benchmarking
MODEL=Qwen/Qwen3-1.7B \
VLLM_CPU_KVCACHE_SPACE=64 \
HF_HOME=/srv/huggingface:/models \
HF_HOME_CONTAINER=/models \
bash run_podman.sh
```

### Detached server (what the Python orchestrator emulates)

```bash
MODEL=Qwen/Qwen3-1.7B \
VLLM_IMAGE=vllm/vllm-openai-cpu:v0.18.0 \
VLLM_EXTRA_ARGS='--dtype=bfloat16 --max-model-len 4096' \
PORT=8000 \
SHM_SIZE=8g \
HF_HOME=/srv/huggingface:/models \
HF_HOME_CONTAINER=/models \
VLLM_CPU_KVCACHE_SPACE=128 \
SERVER_NUMA_NODE=1 \
CONTAINER_NAME=vllm-bench-001 \
DETACHED=1 \
REPLACE_CONTAINER=1 \
bash run_podman.sh
```

### Pin server CPUs on the NUMA node (`taskset`)

```bash
MODEL=Qwen/Qwen3-1.7B \
SERVER_NUMA_NODE=1 \
SERVER_CPULIST=8-15 \
HF_HOME=/srv/huggingface:/models \
DETACHED=1 \
REPLACE_CONTAINER=1 \
CONTAINER_NAME=vllm-cpupin \
bash run_podman.sh
```

### Extra container env from a file (`-e` per line)

```bash
# my.env lines look like: FOO=bar
MODEL=Qwen/Qwen3-1.7B \
EXTRA_ENV_FILE=./my.env \
HF_HOME=/srv/huggingface:/models \
DETACHED=1 \
REPLACE_CONTAINER=1 \
CONTAINER_NAME=vllm-extraenv \
bash run_podman.sh
```

### Docker instead of Podman

```bash
CONTAINER_RUNTIME=docker \
MODEL=Qwen/Qwen3-1.7B \
HF_HOME=/srv/huggingface:/models \
DETACHED=1 \
REPLACE_CONTAINER=1 \
CONTAINER_NAME=vllm-docker \
bash run_podman.sh
```

### Match the orchestrator’s environment (illustrative)

The Python code merges your JSON/CLI into variables such as `MODEL`, `VLLM_IMAGE`, `PORT`, `HF_HOME`, `HF_HOME_CONTAINER`, `VLLM_CPU_KVCACHE_SPACE`, `SERVER_NUMA_NODE`, `CONTAINER_NAME`, `VLLM_CPU_OMP_THREADS_BIND`, optional `SERVER_CPULIST`, `CPU_VISIBLE_MEMORY_NODES`, `OMP_NUM_THREADS`, `EXTRA_ENV_FILE`, `EXTRA_DOCKER_RUN_FILE`, `VLLM_USE_IMAGE_ENTRYPOINT`, then runs `bash run_podman.sh` with `DETACHED=1` and `REPLACE_CONTAINER=1`. Inspect **`podman_launch_preview.txt`** in a run directory for the exact values for that run.

### Example JSON files (in-repo)

| File | Purpose |
| --- | --- |
| [`configs/examples/minimal-suite.json`](configs/examples/minimal-suite.json) | Smallest suite: shared `defaults`, one run. Edit `hf_home`, `output_dir`, and model paths for your host. |
| [`configs/examples/suite-with-tooling-paths.json`](configs/examples/suite-with-tooling-paths.json) | Same idea plus suite-level `run_podman_script`, `guidellm_venv`, `guidellm_env`, and a per-run `guidellm_bin` override on the second entry. Replace placeholder paths. |

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
    "vllm_image": "vllm/vllm-openai-cpu:v0.18.0",
    "vllm_extra_args": "--dtype=bfloat16",
    "hf_home": "/path/on/host/models:/models",
    "output_dir": "./results"
  },
  "runs": [
    { "run_name": "example-qwen-smoke", "model": "Qwen/Qwen3-1.7B" }
  ]
}
```

Suite with explicit GuideLLM / Podman paths (inline copy; adjust paths):

```json
{
  "experiment": "example-tooling",
  "run_podman_script": "/path/to/cpu-benchmarking/run_podman.sh",
  "guidellm_venv": "/path/to/guidellm_env",
  "guidellm_env": {
    "PATH": "/path/to/guidellm_env/bin:/usr/bin:/bin"
  },
  "defaults": {
    "server_numa": 1,
    "client_numa": 0,
    "max_seconds": 120,
    "isl": 128,
    "osl": 128,
    "rate": "1,2,4",
    "kv_cache_gb": 64,
    "vllm_image": "vllm/vllm-openai-cpu:v0.18.0",
    "vllm_extra_args": "--dtype=bfloat16",
    "hf_home": "/path/on/host/models:/models",
    "output_dir": "./results"
  },
  "runs": [
    { "run_name": "run-a", "model": "Qwen/Qwen3-1.7B" },
    {
      "run_name": "run-b-other-guidellm",
      "model": "Qwen/Qwen3-1.7B",
      "guidellm_bin": "/opt/other_venv/bin/guidellm"
    }
  ]
}
```

Run a bundled example (after editing paths inside the JSON):

```bash
python3 cpu_vllm_bench.py \
  --config configs/examples/minimal-suite.json \
  --output-base ./results
```

Existing smoke config:

```bash
python3 cpu_vllm_bench.py \
  --config configs/smoke/test1.json \
  --output-base ./results \
  --mlflow
```

## Useful CLI flags

- **`--run-podman-script`**: explicit `run_podman.sh`.
- **`--guidellm-bin`**: explicit GuideLLM binary.
- **`--container-runtime`**: `podman` or `docker` (or env `CONTAINER_RUNTIME`).
- **`--server-numa` / `--client-numa`**: NUMA node for vLLM vs GuideLLM client.
- **`--kv-cache-gb`**: integer GiB for `VLLM_CPU_KVCACHE_SPACE`.
- **`--ready-timeout`**: seconds to wait for `/health` or `/v1/models`.
- **`--dashboard-csv`**: append dashboard-format rows to a shared CSV (each run still writes `dashboard_benchmark.csv` under its run directory when GuideLLM JSON exists).
- **`--import-script`**, **`--dashboard-version`**, **`--dashboard-tp`**, **`--dashboard-accelerator`**, **`--dashboard-guidellm-version`**: passed through to the dashboard import helper.

Run `python3 cpu_vllm_bench.py --help` for the full list.

## Wrapper script

`run_benchmark.sh` is an example that passes `--config`, dashboard CSV, image tag, and MLflow-related flags. Edit paths and variables before use.

## Artifacts per run

Under each run directory (under `--output-base` / `output_dir` + run slug): GuideLLM JSON and logs, `run_config.json`, `run_manifest.json`, `podman_launch_preview.txt` (orchestrator env + reconstructed container CLI), `vllm_server.log`, `host_samples.tsv`, system capture files, optional `dashboard_benchmark.csv` and PNG graphs.
