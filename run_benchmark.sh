# Use the same store as `mlflow server`, e.g.:
#   export MLFLOW_TRACKING_URI=http://127.0.0.1:5000
python3 cpu_vllm_bench.py \
  --config test.json  \
  --dashboard-csv results.csv \
  --vllm-image docker.io/vllm/vllm-openai-cpu:v0.18.0  \
  --dashboard-version "RHAIIS-3.4-GA-Downstream" \
  --mlflow \
  --output-base ${DIR}/socket1-cpu-RHAIIS-3.4-GA-Downstream
