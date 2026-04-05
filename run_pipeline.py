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
# ── Main ──────────────────────────────────────────────────────────────────────
def main():
    args = sys.argv[1:]
    if args and args[0].endswith(".yaml"):
        yaml_file = args[0]
        target    = args[1] if len(args) > 1 else None
    else:
        yaml_file = "pipeline.yaml"
        target    = args[0] if args else None
    print(f"Loading pipeline from: {yaml_file}")
    with open(yaml_file) as f:
        pipeline = yaml.safe_load(f)
    settings   = pipeline.get("settings", {})
    verbose    = settings.get("verbose", True)
    shell_init = settings.get("shell_init", "")    # ← read it once here
    if shell_init:
        log(f"shell_init active: {shell_init}", verbose)
    if settings.get("sudo_keepalive", False):
        sudo_keepalive(verbose)
    steps = pipeline.get("steps", [])
    if target:
        steps = [s for s in steps if s.get("name") == target]
        if not steps:
            print(f"ERROR: No step named '{target}' found in {yaml_file}",
                  file=sys.stderr)
            sys.exit(1)
        print(f"Running single task: {target}\n")
    else:
        print(f"Found {len(steps)} step(s). Starting pipeline...\n")
    for step in steps:
        name   = step.get("name", "unnamed")
        mode   = step.get("mode", "foreground")
        runner = RUNNERS.get(mode)
        if not runner:
            print(f"ERROR: Unknown mode '{mode}' in step '{name}'",
                  file=sys.stderr)
            sys.exit(1)
        runner(step, verbose, shell_init)    # ← pass shell_init to every runner
    print("\nPipeline complete. Background jobs may still be running.")
    print("Check log files for their output.")
if __name__ == "__main__":
    main()
