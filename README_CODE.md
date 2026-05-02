# Code map: `cpu_vllm_bench.py`

This document describes how the orchestrator is structured so you can change behavior without reading the whole file.

## Entry and modes

- **`main()`** — Parses CLI (`parse_args()`), then either:
  - **`run_suite_from_json_path()`** for each `--config` file, or
  - Builds a one-off `cfg` dict from CLI defaults and calls **`single_benchmark()`**.
- **`single_benchmark()`** — Calls **`resolve_run()`**, validates `run_podman_script` and `guidellm_bin`, enables **`tee_stdout_stderr_to_run_dir()`**, then **`execute_benchmark_phase()`** and **`finalize_after_benchmark()`**.

## Configuration resolution

- **`resolve_run(cfg, args)`** — Single source of truth for a run. Reads benchmark fields from `cfg` with fallbacks to `args`. Important paths and env:
  - **`hf_home`** / **`hf_home_container`** — Passed through to `run_podman.sh` as `HF_HOME` (the **`-v`** bind string) and `HF_HOME_CONTAINER` (inner `HF_HOME`). Values are **not** rewritten; optional **`launch_env`** entries `HF_HOME` / `HF_HOME_CONTAINER` override the top-level JSON keys after merge.
  - **`launch_env`** — Merged from `defaults.launch_env`, suite-root `launch_env`, and per-run `launch_env` via **`merge_launch_env_from_json_layers()`**, then applied in **`resolve_run()`** with **`podman_env.update(launch_env_user)`** (after which `DETACHED`, `REPLACE_CONTAINER`, and `CONTAINER_NAME` are forced for orchestration).
  - Suite JSON shallow merge: `defaults` → suite-level keys (`guidellm_*`, `run_podman_script`, **`hf_home`**, …) → each **`runs`** entry; **`launch_env`** uses the separate deep merge above.
- **`ResolvedRun`** — Immutable-ish snapshot used for the rest of the pipeline (`run_dir`, `podman_env`, `guidellm_bin`, etc.).

## Benchmark phase (container + GuideLLM)

- **`execute_benchmark_phase()`** — Order of operations:
  1. Write **`run_config.json`** (input `cfg`).
  2. **`materialize_merged_extra_env()`** — If JSON `container_env` is set, may write `container_extra_env_merged.env` and set `podman_env["EXTRA_ENV_FILE"]`.
  3. Write **`run_manifest.json`** (resolved fields + `podman_launch_env`).
  4. **`capture_system_pre_run_snapshot()`** — `lscpu`, `numactl`, `free`, etc.
  5. **`log_podman_launch_preview()`** — Prints and writes **`podman_launch_preview.txt`** (orchestrator env + reconstructed `podman run` line; see below).
  6. **`run_podman_detached()`** — `bash run_podman.sh` with `rr.podman_env` merged into `os.environ`, `cwd` = script directory.
  7. **`start_log_follower()`** — Streams `podman logs -f` (or docker) to **`vllm_server.log`**.
  8. **`metrics_sampler`** thread — Appends to **`host_samples.tsv`**.
  9. **`wait_for_server()`** — Polls `/health` and `/v1/models`.
  10. **`run_guidellm()`** — `numactl` + GuideLLM CLI; optional **`guidellm_subprocess_env`** merged into the subprocess environment.
  11. On exit: stop sampler, snapshot full container logs, **`stop_container()`**.

## Podman launch preview vs `run_podman.sh`

- **`format_podman_launch_preview()`** / **`_podman_run_argv_from_env()`** / **`_numactl_launch_prefix_argv()`** — Reconstruct the effective **`podman|docker run ...`** argv to match **`run_podman.sh`**. They do **not** expand `EXTRA_ENV_FILE` or `EXTRA_DOCKER_RUN_FILE` line-by-line; comments in the preview note those additions.
- If you change **`run_podman.sh`**, update these Python helpers (or accept preview drift) so logged commands stay accurate.

## Post-benchmark

- **`finalize_after_benchmark()`** — If GuideLLM JSON exists: **`append_dashboard_csv()`**, optional plots via **`write_dashboard_benchmark_plots()`**, then optional **`upload_mlflow_run()`** with artifacts from **`iter_benchmark_artifact_paths()`**.

## MLflow and dashboard

- **`build_auto_mlflow_tags()`** / **`merge_tags()`** — Auto tags plus user overrides from JSON `mlflow_tags`.
- **`guidellm_json_to_mlflow_metrics()`** — Flattens GuideLLM JSON metrics for MLflow.
- **`append_dashboard_csv()`** — Invokes external **`import_manual_runs_json_v2.py`** when present.

## Related files

- **`run_podman.sh`** — Builds the real container command; documents env vars in its header comments.
- **`README.md`** — Operator-facing setup, JSON examples, and **`run_podman.sh`** usage examples.
