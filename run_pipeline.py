#!/usr/bin/env python3
"""
run_pipeline.py
Reads pipeline.yaml and executes each step according to its configuration.
Think of this as the "engine" that drives the recipe card (the YAML).
"""
import yaml
import subprocess
import sys
import os
from datetime import datetime
from pathlib import Path

if "--force" in sys.argv:
    os.environ["FORCE_REBUILD"] = "true"
    print("🧨 Force Rebuild enabled via command line flag.")
    # 2. REMOVE the flag from sys.argv so the pipeline parser doesn't see it
    sys.argv.remove("--force")

# ── Helpers ──────────────────────────────────────────────────────────────────
def log(message: str, verbose: bool = True):
    """Print a timestamped status message — mimics `set -x` visibility."""
    if verbose:
        timestamp = datetime.now().strftime("%H:%M:%S")
        print(f"[{timestamp}] + {message}", flush=True)
def sudo_keepalive(verbose: bool):
    """
    Equivalent to `sudo -v` — refreshes the sudo timestamp so background
    processes don't get prompted for a password mid-run.
    """
    log("sudo -v  (refreshing sudo credentials)", verbose)
    result = subprocess.run(["sudo", "-v"])
    if result.returncode != 0:
        print("ERROR: sudo -v failed. Do you have sudo rights?", file=sys.stderr)
        sys.exit(1)
def build_dated_command(script: str, log_file: str) -> str:
    """
    Builds a shell command equivalent to:
        (date ; time ./script.sh ; date) 1> out.txt 2>&1 &
    We wrap in a subshell string to hand off to bash.
    """
    return (
        f"(date ; time {script} ; date) "
        f"1> {log_file} 2>&1"
    )
# ── Step Runners ─────────────────────────────────────────────────────────────
def run_foreground(step: dict, verbose: bool):
    """Blocking execution. Pipeline waits for this to finish."""
    script = step["script"]
    log(f"[foreground] {script}", verbose)
    result = subprocess.run(script, shell=True)
    if result.returncode != 0:
        print(
            f"ERROR: Step '{step['name']}' failed with exit code {result.returncode}",
            file=sys.stderr,
        )
        sys.exit(result.returncode)
def run_background(step: dict, verbose: bool):
    """
    Non-blocking execution. Fires the process and immediately moves on —
    equivalent to appending `&` in bash.
    Uses Popen instead of run() so we don't block.
    """
    script   = step["script"]
    log_file = step.get("log", f"{step['name']}_out.txt")
    wrap     = step.get("wrap_with_dates", False)
    if wrap:
        cmd = build_dated_command(script, log_file)
    else:
        cmd = f"{script} 1> {log_file} 2>&1"
    log(f"[background] {cmd}", verbose)
    # Popen launches and returns immediately — the process runs independently
    proc = subprocess.Popen(cmd, shell=True)
    print(f"  → '{step['name']}' running in background (PID {proc.pid}), "
          f"logging to {log_file}")
    print("  …")
def run_source(step: dict, verbose: bool):
    """
    Mimics `. ./script` (sourcing) — executes the script and then
    re-exports any environment changes back into this Python process.
    HOW IT WORKS:
      We ask bash to source the file, then print all env vars afterward.
      Python then reads those and updates os.environ — effectively
      'inheriting' whatever the sourced script exported.
    """
    script = step["script"]
    log(f"[source] . {script}", verbose)
    if not Path(script).exists():
        print(f"WARNING: Source script '{script}' not found — skipping.",
              file=sys.stderr)
        return
    # Run: bash -c "source ./script && env"
    # The `env` at the end dumps all variables so we can harvest them
    result = subprocess.run(
        f"bash -c 'source {script} && env'",
        shell=True,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"ERROR: Sourcing '{script}' failed:\n{result.stderr}",
              file=sys.stderr)
        sys.exit(1)
    # Parse the env output and apply changes to our current process
    new_vars_count = 0
    for line in result.stdout.splitlines():
        if "=" in line:
            key, _, value = line.partition("=")
            if os.environ.get(key) != value:
                os.environ[key] = value
                new_vars_count += 1
    log(f"  → sourced '{script}', absorbed {new_vars_count} env var(s)", verbose)
# ── Dispatch Table ────────────────────────────────────────────────────────────
# Maps mode strings from YAML → the function that handles them.
# Adding a new mode is as simple as writing a function and adding it here.
RUNNERS = {
    "foreground": run_foreground,
    "background":  run_background,
    "source":      run_source,
}
# ── Main ──────────────────────────────────────────────────────────────────────
def main():
    # Argument parsing:
    #   python3 run_pipeline.py                        → runs full pipeline
    #   python3 run_pipeline.py k8s_rebuild            → runs single task
    #   python3 run_pipeline.py pipeline.yaml          → runs full pipeline from named file
    #   python3 run_pipeline.py pipeline.yaml k8s_rebuild → single task from named file
    args = sys.argv[1:]
    # Sniff whether the first arg looks like a yaml file or a task name
    if args and args[0].endswith(".yaml"):
        yaml_file  = args[0]
        target     = args[1] if len(args) > 1 else None
    else:
        yaml_file  = "pipeline.yaml"
        target     = args[0] if args else None
    print(f"Loading pipeline from: {yaml_file}")
    with open(yaml_file) as f:
        pipeline = yaml.safe_load(f)
    settings = pipeline.get("settings", {})
    verbose  = settings.get("verbose", True)
    if settings.get("sudo_keepalive", False):
        sudo_keepalive(verbose)
    steps = pipeline.get("steps", [])
    # If a target was given, filter down to just that one step
    if target:
        steps = [s for s in steps if s.get("name") == target]
        if not steps:
            print(f"ERROR: No step named '{target}' found in {yaml_file}", file=sys.stderr)
            sys.exit(1)
        print(f"Running single task: {target}\n")
    else:
        print(f"Found {len(steps)} step(s). Starting pipeline...\n")
    for step in steps:
        name   = step.get("name", "unnamed")
        mode   = step.get("mode", "foreground")
        runner = RUNNERS.get(mode)
        if not runner:
            print(f"ERROR: Unknown mode '{mode}' in step '{name}'", file=sys.stderr)
            sys.exit(1)
        runner(step, verbose)
    print("\nPipeline complete. Background jobs may still be running.")
    print("Check log files for their output.")
if __name__ == "__main__":
    main()
