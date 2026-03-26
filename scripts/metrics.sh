# Called by hub metrics
# Shows key performance metrics from vLLM's Prometheus endpoint.

echo "=== Inference Hub Metrics ==="
echo ""

parse_metric() {
    local data="$1" metric="$2" label="$3"
    value=$(echo "$data" | grep "^${metric}" | grep -v "^#" | tail -1 | awk '{print $2}')
    if [[ -n "$value" ]]; then
        printf "  %-40s %s\n" "$label" "$value"
    fi
}

parse_histogram_avg() {
    local data="$1" metric="$2" label="$3"
    sum=$(echo "$data" | grep "^${metric}_sum " | awk '{print $2}')
    count=$(echo "$data" | grep "^${metric}_count " | awk '{print $2}')
    if [[ -n "$sum" && -n "$count" && "$count" != "0" && "$count" != "0.0" ]]; then
        avg=$(python3 -c "print(f'{$sum / $count:.3f}')" 2>/dev/null || echo "n/a")
        printf "  %-40s %s\n" "$label" "$avg"
    fi
}

# --- Small model ---
SMALL_DATA=$(curl -sf --max-time 5 "http://localhost:8001/metrics" 2>/dev/null || echo "")

if [[ -n "$SMALL_DATA" ]]; then
    echo "--- vllm-small (${SMALL_MODEL:-unknown}) ---"
    echo ""

    # Request throughput
    parse_metric "$SMALL_DATA" "vllm:num_requests_running" "Requests running:"
    parse_metric "$SMALL_DATA" "vllm:num_requests_waiting" "Requests queued:"
    parse_metric "$SMALL_DATA" "vllm:num_requests_total" "Total requests served:"

    # Token throughput
    prompt_total=$(echo "$SMALL_DATA" | grep "^vllm:prompt_tokens_total " | awk '{print $2}')
    gen_total=$(echo "$SMALL_DATA" | grep "^vllm:generation_tokens_total " | awk '{print $2}')
    if [[ -n "$prompt_total" ]]; then
        printf "  %-40s %s\n" "Prompt tokens processed:" "$prompt_total"
    fi
    if [[ -n "$gen_total" ]]; then
        printf "  %-40s %s\n" "Tokens generated:" "$gen_total"
    fi

    # Latency
    parse_histogram_avg "$SMALL_DATA" "vllm:e2e_request_latency_seconds" "Avg request latency (s):"
    parse_histogram_avg "$SMALL_DATA" "vllm:time_to_first_token_seconds" "Avg time to first token (s):"
    parse_histogram_avg "$SMALL_DATA" "vllm:time_per_output_token_seconds" "Avg time per output token (s):"

    # Tokens per second (from time per token)
    tpot_sum=$(echo "$SMALL_DATA" | grep "^vllm:time_per_output_token_seconds_sum " | awk '{print $2}')
    tpot_count=$(echo "$SMALL_DATA" | grep "^vllm:time_per_output_token_seconds_count " | awk '{print $2}')
    if [[ -n "$tpot_sum" && -n "$tpot_count" && "$tpot_count" != "0" && "$tpot_count" != "0.0" ]]; then
        tps=$(python3 -c "
tpot = $tpot_sum / $tpot_count
if tpot > 0:
    print(f'{1/tpot:.1f} tok/s')
else:
    print('n/a')
" 2>/dev/null || echo "n/a")
        printf "  %-40s %s\n" "Avg generation speed:" "$tps"
    fi

    # GPU cache
    parse_metric "$SMALL_DATA" "vllm:gpu_cache_usage_perc" "GPU KV cache usage:"
    echo ""
else
    echo "--- vllm-small: not responding ---"
    echo ""
fi

# --- Large model ---
if [[ -n "${LARGE_MODEL:-}" ]]; then
    LARGE_DATA=$(curl -sf --max-time 5 "http://localhost:8002/metrics" 2>/dev/null || echo "")

    if [[ -n "$LARGE_DATA" ]]; then
        echo "--- vllm-large (${LARGE_MODEL:-unknown}) ---"
        echo ""
        parse_metric "$LARGE_DATA" "vllm:num_requests_running" "Requests running:"
        parse_metric "$LARGE_DATA" "vllm:num_requests_waiting" "Requests queued:"
        parse_metric "$LARGE_DATA" "vllm:num_requests_total" "Total requests served:"

        prompt_total=$(echo "$LARGE_DATA" | grep "^vllm:prompt_tokens_total " | awk '{print $2}')
        gen_total=$(echo "$LARGE_DATA" | grep "^vllm:generation_tokens_total " | awk '{print $2}')
        if [[ -n "$prompt_total" ]]; then
            printf "  %-40s %s\n" "Prompt tokens processed:" "$prompt_total"
        fi
        if [[ -n "$gen_total" ]]; then
            printf "  %-40s %s\n" "Tokens generated:" "$gen_total"
        fi

        parse_histogram_avg "$LARGE_DATA" "vllm:e2e_request_latency_seconds" "Avg request latency (s):"
        parse_histogram_avg "$LARGE_DATA" "vllm:time_to_first_token_seconds" "Avg time to first token (s):"
        parse_histogram_avg "$LARGE_DATA" "vllm:time_per_output_token_seconds" "Avg time per output token (s):"

        tpot_sum=$(echo "$LARGE_DATA" | grep "^vllm:time_per_output_token_seconds_sum " | awk '{print $2}')
        tpot_count=$(echo "$LARGE_DATA" | grep "^vllm:time_per_output_token_seconds_count " | awk '{print $2}')
        if [[ -n "$tpot_sum" && -n "$tpot_count" && "$tpot_count" != "0" && "$tpot_count" != "0.0" ]]; then
            tps=$(python3 -c "
tpot = $tpot_sum / $tpot_count
if tpot > 0:
    print(f'{1/tpot:.1f} tok/s')
else:
    print('n/a')
" 2>/dev/null || echo "n/a")
            printf "  %-40s %s\n" "Avg generation speed:" "$tps"
        fi

        parse_metric "$LARGE_DATA" "vllm:gpu_cache_usage_perc" "GPU KV cache usage:"
        echo ""
    else
        echo "--- vllm-large: not responding ---"
        echo ""
    fi
fi
