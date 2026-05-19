 python3 cpu_vllm_bench.py --config downstream.json \
 --dashboard-csv prefill-decode-study-Qwen3-4B-8B-sweep.csv \
  --dashboard-accelerator "SPR" \
  --mlflow \
  --output-base SPR/Prefill-Decode-Sweep
