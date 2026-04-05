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
    sys.argv.remove("--force")
# ── Helpers ───────────────────────────────────────────────────────────────────
def log(message: str, verbose: bool = True):
    if verbose:
        timestamp = datetime.now().strftime("%H:%M:%S")
        print(f"[{timestamp}] + {message}", flush=True)
def sudo_keepalive(verbose: bool):
    log("sudo -v  (refreshing sudo credentials)", verbose)
    result = subprocess.run(["sudo", "-v"])
    if result.returncode != 0:
        print("ERROR: sudo -v failed. Do you have sudo rights?", file=sys.stderr)
        sys.exit(1)
def build_dated_command(script: str, log_file: str) -> str:
    return (
        f"(date ; time {script} ; date) "
        f"1> {log_file} 2>&1"
    )
# ── NEW: Script wrapper ───────────────────────────────────────────────────────
def wrap_script(script: str, shell_init: str) -> str:
    """
    Prepend shell_init to any script before execution.
    This is the facade pattern in action — the caller (YAML step) just
    says 'cleanup', and this function ensures the shell knows what
    'cleanup' means before it tries to run it.
    If shell_init is empty, the script is returned unchanged — so
    existing behavior is 100% preserved when shell_init is not set.
    """
    if not shell_init:
        return script
    return f"{shell_init}\n{script}"
# ── Step Runners ──────────────────────────────────────────────────────────────
def run_foreground(step: dict, verbose: bool, shell_init: str = ""):
    script = step["script"]
    work_dir = step.get("cwd", os.getcwd()) 
    script = wrap_script(script, shell_init)
    log(f"[foreground] {step['name']} in {work_dir}", verbose)
    result = subprocess.run(
        script,
        shell=True,
        executable="/bin/bash",
        cwd=work_dir
    )
    if result.returncode != 0:
        print(
            f"ERROR: Step '{step['name']}' failed with exit code {result.returncode}",
            file=sys.stderr,
        )
        sys.exit(result.returncode)
def run_background(step: dict, verbose: bool, shell_init: str = ""):  # ← added shell_init
    script   = step["script"]
    log_file = step.get("log", f"{step['name']}_out.txt")
    wrap     = step.get("wrap_with_dates", False)
    if wrap:
        cmd = build_dated_command(script, log_file)
    else:
        cmd = f"{script} 1> {log_file} 2>&1"
    cmd = wrap_script(cmd, shell_init)                                 # ← wrap it
    log(f"[background] {step['script']}", verbose)                     # ← log original
    proc = subprocess.Popen(
        cmd,
        shell=True,
        executable="/bin/bash"    # ← force bash here too
    )
    print(f"  → '{step['name']}' running in background (PID {proc.pid}), "
          f"logging to {log_file}")
    print("  …")
def run_source(step: dict, verbose: bool, shell_init: str = ""):      # ← added for consistency
    """
    Source mode already uses 'bash -c' explicitly.
    shell_init is accepted for signature consistency but source
    scripts typically manage their own environment.
    """
    script = step["script"]
    log(f"[source] . {script}", verbose)
    if not Path(script).exists():
        print(f"WARNING: Source script '{script}' not found — skipping.",
              file=sys.stderr)
        return
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
    new_vars_count = 0
    for line in result.stdout.splitlines():
        if "=" in line:
            key, _, value = line.partition("=")
            if os.environ.get(key) != value:
                os.environ[key] = value
                new_vars_count += 1
    log(f"  → sourced '{script}', absorbed {new_vars_count} env var(s)", verbose)
# ── Dispatch Table ────────────────────────────────────────────────────────────
RUNNERS = {
    "foreground": run_foreground,
    "background": run_background,
    "source":     run_source,
}
def main():
    args = sys.argv[1:]
    
    # 1. Determine the YAML file and the list of requested targets
    if args and args[0].endswith(".yaml"):
        yaml_file = args[0]
        requested_targets = args[1:] # Everything after the YAML file
    else:
        yaml_file = "pipeline.yaml"
        requested_targets = args     # Everything provided
    print(f"Loading pipeline from: {yaml_file}")
    with open(yaml_file) as f:
        pipeline = yaml.safe_load(f)
    settings   = pipeline.get("settings", {})
    verbose    = settings.get("verbose", True)
    shell_init = settings.get("shell_init", "")
    
    if shell_init:
        log(f"shell_init active: {shell_init}", verbose)
    if settings.get("sudo_keepalive", False):
        sudo_keepalive(verbose)
    all_steps = pipeline.get("steps", [])
    # 2. Filter steps based on targets
    if requested_targets:
        # We filter the steps but keep them in the order they appear in the YAML
        steps_to_run = [s for s in all_steps if s.get("name") in requested_targets]
        
        # Validation: Check if any requested target doesn't exist in the YAML
        found_names = [s.get("name") for s in steps_to_run]
        for t in requested_targets:
            if t not in found_names:
                print(f"ERROR: No step named '{t}' found in {yaml_file}", file=sys.stderr)
                sys.exit(1)
        
        print(f"Running tasks: {', '.join(requested_targets)}\n")
    else:
        steps_to_run = all_steps
        print(f"Found {len(steps_to_run)} step(s). Starting pipeline...\n")
    # 3. Execution Loop
    for step in steps_to_run:
        name   = step.get("name", "unnamed")
        mode   = step.get("mode", "foreground")
        runner = RUNNERS.get(mode)
        if not runner:
            print(f"ERROR: Unknown mode '{mode}' in step '{name}'", file=sys.stderr)
            sys.exit(1)
        runner(step, verbose, shell_init)
    print("\nPipeline complete. Background jobs may still be running.")
    print("Check log files for their output.")
if __name__ == "__main__":
    main()
