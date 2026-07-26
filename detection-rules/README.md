# Detection Engineering with Sigma

Author, validate, and publish Sigma detection rules using this lab's telemetry.

## Layout

```
detection-rules/
├── sigma/                 # your Sigma rules (source of truth)
│   └── lin_fileless_memfd.yml
├── pipelines/             # pySigma field-mapping pipelines (Sigma -> our ECS)
│   └── falco-ecs-sigma.yml
├── fixtures/              # recorded clean baseline windows (generated)
│   └── baseline.env
├── validate.sh           # convert + TP/FP count against Elasticsearch
└── README.md
```

## One-time setup

```bash
# 1. Normalize Falco -> ECS in Elasticsearch (parses raw JSON, maps to ECS)
scripts/setup-detection-lab.sh

# 2. Install sigma-cli + the Elasticsearch backend
python3 -m pip install sigma-cli
sigma plugin install elasticsearch
```

## Workflow (per rule)

1. **Analyze** — detonate a sample in the sandbox, explore behavior in Kibana
   Discover (`logs-falco-*`, `logs-zeek-*`, FIM, osquery).
2. **Write** — add a rule under `sigma/` using generic Sigma field names
   (`Image`, `CommandLine`, `TargetFilename`, `DestinationIp`, ...).
3. **Record a baseline** (once, while the sandbox is idle):

   ```bash
   scripts/baseline-capture.sh 120
   ```

4. **Validate** — detonate the sample again, then:

   ```bash
   detection-rules/validate.sh detection-rules/sigma/lin_fileless_memfd.yml 30
   ```

   Expect `TP >= 1` (fires on the sample) and `FP == 0` (silent on the baseline).
5. **Publish** — `sigma check`, then open a PR to
   [SigmaHQ/sigma](https://github.com/SigmaHQ/sigma).

## Field mapping

Sigma rules use generic field names; `pipelines/falco-ecs-sigma.yml` maps them to
the ECS fields produced by `config/es/falco-ecs-pipeline.json`. Add a mapping
there whenever you use a Sigma field that isn't covered yet.
