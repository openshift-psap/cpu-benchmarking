#!/usr/bin/env bash
#
# Start vLLM (OpenAI API) in Podman/Docker with configurable NUMA placement, KV cache, and args.
#
# Key environment variables (all optional unless noted):
#   CONTAINER_RUNTIME     podman or docker (default: podman)
#   VLLM_IMAGE            container image (default: vllm/vllm-openai-cpu:v0.18.0)
#   MODEL                 HuggingFace model id (required for meaningful run)
#   VLLM_EXTRA_ARGS       extra CLI args after MODEL (default: --dtype=bfloat16)
#   PORT                  host/container port (default: 8000)
#   SHM_SIZE              --shm-size (default: 4g)
#   HF_HOME               -v bind host:container for model/cache (default: /home/naveen/models:/models)
#                         Deprecated alias: HF_CACHE_VOLUME (used if HF_HOME is unset)
#   HF_HOME_CONTAINER     value for -e HF_HOME inside container (default: /models)
#
#   VLLM_CPU_KVCACHE_SPACE   KV cache space for CPU backend in GiB, integer only (default: 128)
#
#   SERVER_NUMA_NODE      numactl --cpunodebind / --membind for the server (default: 1)
#   SERVER_CPULIST        if set, prefix with taskset -c CPULIST (limits CPUs on that node)
#
#   CONTAINER_NAME        --name (default: vllm-server-$$); use a fixed name for orchestration
#   DETACHED              if 1, run -d and print container name only (orchestrator use)
#   REPLACE_CONTAINER     if 1, add --replace (podman) / rm -f before run (docker handled separately)
#
#   EXTRA_ENV_FILE          path to a file of lines KEY=value, each becomes -e KEY=value
#   EXTRA_DOCKER_RUN_FILE   optional file: each non-comment line is split on whitespace and
#                           appended to `run` before -v (for extra -p, --ulimit, etc.)
#
#   VLLM_USE_IMAGE_ENTRYPOINT  if 1, do not set --entrypoint: use the image's ENTRYPOINT/CMD.
#                          Default 0: run with --entrypoint vllm and command "serve MODEL ...",
#                          so images whose default is not "vllm serve" still start the server.
#
#   VLLM_CPU_OMP_THREADS_BIND  (default: auto)
#   OMP_NUM_THREADS            passed through if set in environment
#   CPU_VISIBLE_MEMORY_NODES   passed through if set (vLLM CPU backend)
#
# Examples:
#   MODEL=Qwen/Qwen3-1.7B VLLM_CPU_KVCACHE_SPACE=64 bash run_podman.sh
#   SERVER_CPULIST=8-15 EXTRA_ENV_FILE=./my.env DETACHED=1 CONTAINER_NAME=vllm-bench bash run_podman.sh
#
set -euo pipefail

CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-podman}"
VLLM_IMAGE="${VLLM_IMAGE:-vllm/vllm-openai-cpu:v0.18.0}"
MODEL="${MODEL:-Qwen/Qwen3-1.7B}"
VLLM_EXTRA_ARGS="${VLLM_EXTRA_ARGS:---dtype=bfloat16}"
PORT="${PORT:-8000}"
SHM_SIZE="${SHM_SIZE:-4g}"
HF_HOME="${HF_HOME:-${HF_CACHE_VOLUME:-/home/naveen/models:/models}}"
HF_HOME_CONTAINER="${HF_HOME_CONTAINER:-/models}"
VLLM_CPU_KVCACHE_SPACE="${VLLM_CPU_KVCACHE_SPACE:-128}"
SERVER_NUMA_NODE="${SERVER_NUMA_NODE:-1}"
SERVER_CPULIST="${SERVER_CPULIST:-}"
CONTAINER_NAME="${CONTAINER_NAME:-vllm-server-$$}"
DETACHED="${DETACHED:-0}"
REPLACE_CONTAINER="${REPLACE_CONTAINER:-0}"
EXTRA_ENV_FILE="${EXTRA_ENV_FILE:-}"
EXTRA_DOCKER_RUN_FILE="${EXTRA_DOCKER_RUN_FILE:-}"
VLLM_USE_IMAGE_ENTRYPOINT="${VLLM_USE_IMAGE_ENTRYPOINT:-0}"
VLLM_CPU_OMP_THREADS_BIND="${VLLM_CPU_OMP_THREADS_BIND:-auto}"

if [[ -z "${MODEL}" ]]; then
  echo "MODEL must be set" >&2
  exit 1
fi

if [[ ! "${VLLM_CPU_KVCACHE_SPACE}" =~ ^[0-9]+$ ]]; then
  echo "VLLM_CPU_KVCACHE_SPACE must be a non-negative integer (GiB), got: ${VLLM_CPU_KVCACHE_SPACE}" >&2
  exit 1
fi

RUN_ARGS=(
  run
  --rm
  --network host
  --security-opt seccomp=unconfined
  --security-opt=label=disable
  --cap-add SYS_NICE
  --shm-size="${SHM_SIZE}"
  -p "${PORT}:8000"
  --name "${CONTAINER_NAME}"
  -e "VLLM_CPU_KVCACHE_SPACE=${VLLM_CPU_KVCACHE_SPACE}"
  -e "VLLM_CPU_OMP_THREADS_BIND=${VLLM_CPU_OMP_THREADS_BIND}"
  -e "HF_HOME=${HF_HOME_CONTAINER}"
)

if [[ "${REPLACE_CONTAINER}" == "1" ]]; then
  if [[ "${CONTAINER_RUNTIME}" == "podman" ]]; then
    RUN_ARGS+=(--replace)
  fi
fi

if [[ "${DETACHED}" == "1" ]]; then
  RUN_ARGS+=(-d)
fi

if [[ -n "${CPU_VISIBLE_MEMORY_NODES+x}" && -n "${CPU_VISIBLE_MEMORY_NODES:-}" ]]; then
  RUN_ARGS+=(-e "CPU_VISIBLE_MEMORY_NODES=${CPU_VISIBLE_MEMORY_NODES}")
fi

if [[ -n "${OMP_NUM_THREADS+x}" && -n "${OMP_NUM_THREADS:-}" ]]; then
  RUN_ARGS+=(-e "OMP_NUM_THREADS=${OMP_NUM_THREADS}")
fi

if [[ -n "${EXTRA_ENV_FILE}" && -f "${EXTRA_ENV_FILE}" ]]; then
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
    RUN_ARGS+=(-e "${line}")
  done < "${EXTRA_ENV_FILE}"
fi

if [[ -n "${EXTRA_DOCKER_RUN_FILE}" && -f "${EXTRA_DOCKER_RUN_FILE}" ]]; then
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
    read -r -a _extra_run <<< "${line}"
    RUN_ARGS+=("${_extra_run[@]}")
  done < "${EXTRA_DOCKER_RUN_FILE}"
fi

RUN_ARGS+=(-v "${HF_HOME}")
if [[ "${VLLM_USE_IMAGE_ENTRYPOINT}" == "1" ]]; then
  RUN_ARGS+=("${VLLM_IMAGE}" "${MODEL}")
else
  RUN_ARGS+=(--entrypoint "vllm" "${VLLM_IMAGE}" serve "${MODEL}")
fi

read -r -a EXTRA_VLLM <<< "${VLLM_EXTRA_ARGS}"
RUN_ARGS+=("${EXTRA_VLLM[@]}")

LAUNCH=(numactl "--cpunodebind=${SERVER_NUMA_NODE}" "--membind=${SERVER_NUMA_NODE}")
if [[ -n "${SERVER_CPULIST}" ]]; then
  LAUNCH=(taskset -c "${SERVER_CPULIST}" "${LAUNCH[@]}")
fi

if [[ "${CONTAINER_RUNTIME}" == "docker" && "${REPLACE_CONTAINER}" == "1" ]]; then
  docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
fi

if [[ "${DETACHED}" == "1" ]]; then
  "${LAUNCH[@]}" "${CONTAINER_RUNTIME}" "${RUN_ARGS[@]}"
  echo "${CONTAINER_NAME}"
else
  exec "${LAUNCH[@]}" "${CONTAINER_RUNTIME}" "${RUN_ARGS[@]}"
fi
