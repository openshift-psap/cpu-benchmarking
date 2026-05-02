# cpu-benchmarking

Orchestration for **vLLM in Podman** (or Docker via `CONTAINER_RUNTIME`) plus **GuideLLM** load tests: start the server, sample host metrics, run GuideLLM, stop the container, optionally write dashboard CSV / plots and upload to MLflow.

## Layout

Place **`run_podman.sh`** in the same directory as `cpu_vllm_bench.py`, or in your current working directory when you launch the benchmark. The script picks the first existing path in this order: next to `cpu_vllm_bench.py`, then `./run_podman.sh` under the process CWD, then `~/run_podman.sh`. Override with `--run-podman-script` or JSON `run_podman_script`.

Similarly, **`guidellm_env/bin/guidellm`** next to `cpu_vllm_bench.py` is preferred over `~/guidellm_env/bin/guidellm`. Override with `--guidellm-bin`, `guidellm_bin`, or `guidellm_venv` in JSON.

## Prerequisites

- **Container runtime**: Podman (default) or Docker; set `CONTAINER_RUNTIME` if not using Podman.
- **Host tools**: `numactl` (GuideLLM is launched under NUMA bind), `bash`, Python 3.
- **GuideLLM**: install the CLI and ensure the binary exists (see defaults above).
- **vLLM image**: e.g. `vllm/vllm-openai-cpu:v0.18.0` (override with `--vllm-image` or JSON `vllm_image`).
- **Models**: `run_podman.sh` / `HF_HOME` must expose weights to the container (see `--hf-home` and your script’s volume mounts).

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

Per-run objects in `runs` can override any of the above. Merge order: `defaults` → suite-level tooling keys (`guidellm_*`, `run_podman_script`) → each run entry.

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

Under each run directory (under `--output-base` / `output_dir` + run slug): GuideLLM JSON and logs, `run_config.json`, `run_manifest.json`, `vllm_server.log`, `host_samples.tsv`, system capture files, optional `dashboard_benchmark.csv` and PNG graphs.
