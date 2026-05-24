 python3 cpu_vllm_bench.py --config  upstream-qwen3-4b-v0.21.0.json --config   upstream-qwen3-8b-v0.21.0.json  \
 --dashboard-csv prefill-decode-study-Qwen3-4B-8B-sweep-SPR-upstreamonly-v0.21.0.csv \
  --dashboard-accelerator "SPR" \
  --mlflow \
  --output-base SPR/Prefill-Decode-Sweep-UpstreamOnly-v0.21.0-SingleSocket
