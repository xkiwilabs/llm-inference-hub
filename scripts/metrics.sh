# Called by hub metrics
# Shows key performance metrics from vLLM's Prometheus endpoint.

echo "=== Inference Hub Metrics ==="
echo ""

# Extract a gauge/counter value (handles labels like {engine="0",model_name="..."})
get_val() {
    local data="$1" metric="$2"
    echo "$data" | grep "^${metric}[{ ]" | grep -v "^#" | head -1 | awk '{print $NF}'
}

# Extract histogram sum and count, compute average
get_avg() {
    local data="$1" metric="$2"
    local sum count
    sum=$(echo "$data" | grep "^${metric}_sum[{ ]" | head -1 | awk '{print $NF}')
    count=$(echo "$data" | grep "^${metric}_count[{ ]" | head -1 | awk '{print $NF}')
    if [[ -n "$sum" && -n "$count" && "$count" != "0" && "$count" != "0.0" ]]; then
        python3 -c "print(f'{$sum / $count:.3f}')" 2>/dev/null || echo "n/a"
    fi
}

show_model_metrics() {
    local data="$1" name="$2" model="$3"

    echo "--- $name ($model) ---"
    echo ""

    # Requests
    local running queued
    running=$(get_val "$data" "vllm:num_requests_running")
    queued=$(get_val "$data" "vllm:num_requests_waiting")

    # Total requests (sum all finished reasons)
    local total_requests
    total_requests=$(echo "$data" | grep "^vllm:request_success_total{" | grep -v "^#" | awk '{s+=$NF} END {printf "%.0f", s}')

    printf "  %-40s %s\n" "Requests running:" "${running:-0}"
    printf "  %-40s %s\n" "Requests queued:" "${queued:-0}"
    printf "  %-40s %s\n" "Total requests served:" "${total_requests:-0}"

    # Tokens
    local prompt_total gen_total
    prompt_total=$(get_val "$data" "vllm:prompt_tokens_total")
    gen_total=$(get_val "$data" "vllm:generation_tokens_total")

    printf "  %-40s %s\n" "Prompt tokens processed:" "${prompt_total:-0}"
    printf "  %-40s %s\n" "Tokens generated:" "${gen_total:-0}"

    # Latency
    local e2e ttft tpot
    e2e=$(get_avg "$data" "vllm:e2e_request_latency_seconds")
    ttft=$(get_avg "$data" "vllm:time_to_first_token_seconds")
    tpot=$(get_avg "$data" "vllm:time_per_output_token_seconds")

    [[ -n "$e2e" ]] && printf "  %-40s %s s\n" "Avg request latency:" "$e2e"
    [[ -n "$ttft" ]] && printf "  %-40s %s s\n" "Avg time to first token:" "$ttft"
    [[ -n "$tpot" ]] && printf "  %-40s %s s\n" "Avg time per output token:" "$tpot"

    # Tokens per second
    if [[ -n "$tpot" && "$tpot" != "0.000" ]]; then
        local tps
        tps=$(python3 -c "print(f'{1/$tpot:.1f}')" 2>/dev/null)
        [[ -n "$tps" ]] && printf "  %-40s %s tok/s\n" "Avg generation speed:" "$tps"
    fi

    # GPU KV cache
    local cache
    cache=$(get_val "$data" "vllm:gpu_cache_usage_perc")
    if [[ -n "$cache" ]]; then
        local cache_pct
        cache_pct=$(python3 -c "print(f'{$cache * 100:.2f}%')" 2>/dev/null)
        printf "  %-40s %s\n" "GPU KV cache usage:" "${cache_pct:-$cache}"
    fi

    echo ""
}

# --- Small model ---
SMALL_DATA=$(curl -sf --max-time 5 "http://localhost:8001/metrics" 2>/dev/null || echo "")

if [[ -n "$SMALL_DATA" ]]; then
    show_model_metrics "$SMALL_DATA" "vllm-small" "${SMALL_MODEL:-unknown}"
else
    echo "--- vllm-small: not responding ---"
    echo ""
fi

# --- Large model ---
if [[ -n "${LARGE_MODEL:-}" ]]; then
    LARGE_DATA=$(curl -sf --max-time 5 "http://localhost:8002/metrics" 2>/dev/null || echo "")

    if [[ -n "$LARGE_DATA" ]]; then
        show_model_metrics "$LARGE_DATA" "vllm-large" "${LARGE_MODEL:-unknown}"
    else
        echo "--- vllm-large: not responding ---"
        echo ""
    fi
fi
