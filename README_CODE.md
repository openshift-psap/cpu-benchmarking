# Code map: `cpu_vllm_bench.py`

How the orchestrator is structured so you can change behavior without reading the whole file.

## Entry and modes

- **`main()`** — Parses CLI (`parse_args()`), then either:
  - **`run_suite_from_json_path()`** for each `--config` file, or
  - Builds a one-off `cfg` dict from CLI defaults and calls **`single_benchmark()`**.
- **`single_benchmark()`** — Calls **`resolve_run()`**, checks the container runtime is on `PATH` (`shutil.which`), validates **`guidellm_bin`**, enables **`tee_stdout_stderr_to_run_dir()`**, then **`execute_benchmark_phase()`** and **`finalize_after_benchmark()`**.

## Configuration resolution

- **`resolve_run(cfg, args)`** — Single source of truth for a run. Reads benchmark fields from `cfg` with fallbacks to `args`.
  - **`hf_home`** / **`hf_home_container`** — JSON or CLI; used for **`podman|docker run -v ${hf_home}`** and **`-e HF_HOME=${hf_home_container}`** (after merges). Optional **`launch_env`** keys **`HF_HOME`** / **`HF_HOME_CONTAINER`** override those two when merged via **`merge_launch_env_from_json_layers()`**.
  - **`environment`** (canonical), plus deprecated **`container_env`**, plus **`launch_env`** except `HF_HOME` / `HF_HOME_CONTAINER`, are merged across suite layers by **`merge_environment_from_json_layers()`** into **`cfg["environment"]`**. Per-run resolution uses **`resolved_json_environment(cfg)`**.
  - **`effective_container_env()`** — Applies optional **`extra_env_file`**, then JSON env, then **forces** orchestrator values: `VLLM_CPU_KVCACHE_SPACE` (from `kv_cache_gb`), inner `HF_HOME`, `VLLM_CPU_OMP_THREADS_BIND`, and optional `CPU_VISIBLE_MEMORY_NODES` / `OMP_NUM_THREADS` from dedicated JSON/CLI fields.
  - Suite shallow merge: `defaults` → suite-level tooling keys (`guidellm_*`, `run_podman_script` passthrough, `hf_home`, …) → each **`runs`** entry. Then **`merge_launch_env_from_json_layers()`** sets merged **`launch_env`**, and **`merge_environment_from_json_layers()`** sets merged **`environment`**; **`container_env`** is removed from the merged dict after folding so **`run_config.json`** does not duplicate env.
- **`ResolvedRun`** — Dataclass snapshot: `run_dir`, `container_env` (final `-e` map), `environment_from_json` (pre-override JSON merge), `extra_docker_run_argv`, `vllm_use_image_entrypoint`, `guidellm_bin`, etc. No `podman_env` or `run_podman_script`.

## Benchmark phase (container + GuideLLM)

- **`execute_benchmark_phase()`** — Order of operations:
  1. Write **`run_config.json`** (input `cfg`).
  2. **`write_resolved_environment_artifact()`** — Writes redacted **`container_environment_resolved.env`** under `run_dir`.
  3. Write **`run_manifest.json`** (resolved fields, redacted env, **`container_run_argv`** one-liner).
  4. **`capture_system_pre_run_snapshot()`** — `lscpu`, `numactl`, `free`, etc.
  5. **`log_podman_launch_preview()`** — Prints and writes **`podman_launch_preview.txt`** (full argv from **`format_podman_launch_preview()`**).
  6. **`launch_vllm_container()`** — For Docker + replace semantics, **`docker rm -f`** first; then **`subprocess.run`** on **`_numactl_launch_prefix_argv(rr) + build_container_run_argv(rr)`** (no shell, no `run_podman.sh`).
  7. **`start_log_follower()`** — Streams `podman logs -f` (or docker) to **`vllm_server.log`**.
  8. **`metrics_sampler`** thread — Appends to **`host_samples.tsv`**.
  9. **`wait_for_server()`** — Polls `/health` and `/v1/models`.
  10. **`run_guidellm()`** — `numactl` + GuideLLM CLI; optional **`guidellm_subprocess_env`** merged into the subprocess environment.
  11. On exit: stop sampler, snapshot full container logs, **`stop_container()`**.

## Container argv construction

- **`build_container_run_argv()`** — Builds `podman|docker run` arguments: security options, `--shm-size`, port publish, `--name`, podman `--replace`, `-d`, sorted **`-e k=v`** for every entry in **`rr.container_env`**, **`extra_docker_run_argv`** from **`_parse_extra_docker_run_file()`**, **`-v`**, then either **`IMAGE MODEL`** when **`vllm_use_image_entrypoint`** is true, or **`--entrypoint vllm IMAGE serve MODEL`**, then **`shlex.split(vllm_extra_args)`**.
- **`_numactl_launch_prefix_argv()`** — `numactl --cpunodebind/--membind` from `server_numa`, optionally prefixed with **`taskset -c`** when `server_cpulist` is set.

Changing container flags should be done **here** (and reflected in docs); **`run_podman.sh`** is legacy/manual only.

## Post-benchmark

- **`finalize_after_benchmark()`** — If GuideLLM JSON exists: **`append_dashboard_csv()`**, optional plots via **`write_dashboard_benchmark_plots()`**, then optional **`upload_mlflow_run()`** with artifacts from **`iter_benchmark_artifact_paths()`**.

## MLflow and dashboard

- **`build_auto_mlflow_tags()`** / **`merge_tags()`** — Auto tags plus user overrides from JSON `mlflow_tags`.
- **`guidellm_json_to_mlflow_metrics()`** — Flattens GuideLLM JSON metrics for MLflow.
- **`append_dashboard_csv()`** — Invokes external **`import_manual_runs_json_v2.py`** when present.

## Related files

- **`run_podman.sh`** — Optional manual/ad-hoc launcher; **not** invoked by `cpu_vllm_bench.py`.
- **[README.md](README.md)** — Operator overview and troubleshooting.
- **[README_USAGE.md](README_USAGE.md)** — Copy-paste examples (CLI, JSON, smoke configs).
