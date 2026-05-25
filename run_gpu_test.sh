 python3 gpu_vllm_bench.py --config upstream-llama-8b.json  --config upstream-llama-3b.json    \
 --dashboard-csv prefill-decode-study-Llama-sweep-L4-maxmodellen-4096.csv \
  --dashboard-accelerator "L4" \
  --mlflow \
  --output-base L4/Prefill-Decode-Sweep
