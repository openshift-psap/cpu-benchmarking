 python3 gpu_vllm_bench.py --config upstream-qwen3-4b-more.json     \
 --dashboard-csv prefill-decode-study-Llama-sweep-L4-maxmodellen-32768.csv \
  --dashboard-accelerator "L4" \
  --mlflow \
  --output-base L4/Prefill-Decode-Sweep
