# Renders litellm/config.yaml from its template. The one render path: start.sh and set-model.sh both call
# render_litellm_config, so optional blocks survive a model change.
#
# Optional DecisiveLM route: DECISIVELM_URL is where LiteLLM reaches the DecisiveLM server (blank = no route).
# Hub keys are not checked by LiteLLM on this route (pass-through auth needs an Enterprise licence); the caller's
# Authorization header is forwarded and the DecisiveLM server checks the key against this gateway itself.
render_litellm_config() {
    if [[ -n "${DECISIVELM_URL:-}" ]]; then
        export DECISIVELM_PASSTHROUGH="  pass_through_endpoints:
    - path: /decisivelm/v1/systemone
      target: ${DECISIVELM_URL%/}/v1/systemone
      forward_headers: true
    - path: /decisivelm/v1/models
      target: ${DECISIVELM_URL%/}/v1/models
      forward_headers: true"
    else
        export DECISIVELM_PASSTHROUGH=""
    fi
    envsubst < "$HUB_DIR/litellm/config.template.yaml" > "$HUB_DIR/litellm/config.yaml"
}
