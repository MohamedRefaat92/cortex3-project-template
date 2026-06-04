# cortex3 project template

A reproducible scaffold for bioinformatics projects on the **cortex3** cluster
(Ludwig Institute, Oxford). Designed to make a clean separation between:

- **What the cluster does** — runs jobs on compute nodes via SLURM
- **What the container does** — provides R, Python, RStudio, Jupyter
- **What the scripts do** — wrap the messy ceremony into one-liners

## What this template gives you

- Apptainer-based container with R 4.5 + RStudio Server + Python + Jupyter Lab
- SLURM-aware launch scripts for **interactive** RStudio/Jupyter (auto-prints
  the SSH tunnel command you run on your Mac)
- SLURM-aware launch scripts for **batch** R scripts, Python scripts,
  and `targets` pipelines
- Sensible defaults for cortex3 (partition, account, resources)
- Project-level R package persistence via bind mounts
- Status / stop / logs utilities aware of SLURM and tunnels
- Builds the container on the cluster (no Mac→cluster image push needed)

## Quick start

```bash
# 1. Copy the template to a new project location
cp -r /path/to/cortex3-template /mnt/scratch/users/$USER/projects/my_first_project
cd /mnt/scratch/users/$USER/projects/my_first_project

# 2. Customize .env
cp .env.example .env
$EDITOR .env                          # set PROJECT_NAME, port assignments

# 3. Initialize Git
git init && git add . && git commit -m "Initial scaffold from cortex3-template"

# 4. Build the container (submits a SLURM job — takes 20-40 min the first time)
./scripts/build_container.sh

# 5. Launch an interactive RStudio session
./scripts/run_rstudio.sh
# -> prints SSH tunnel command. Run it on your Mac, open the URL.
```

## Daily workflow

### Interactive analysis

```bash
# On cortex3 (e.g. inside VS Code Remote-SSH terminal):
./scripts/run_rstudio.sh                  # default: 16 cpu, 96G, 8h
./scripts/run_rstudio.sh --time=12:00:00  # longer session
./scripts/run_rstudio.sh --mem=256G       # more memory

# Or Jupyter Lab:
./scripts/run_jupyter.sh

# Or just a shell on a compute node (for ad-hoc work):
./scripts/run_shell.sh
```

Each interactive launcher submits an `sbatch` job, waits for it to start,
and prints the `ssh -L` tunnel command for your Mac. **Run the tunnel
command in a Mac terminal**, then open `http://localhost:8801` (RStudio)
or `http://localhost:8802` (Jupyter) in your browser.

Alternatively, if you're connected to cortex3 via VS Code Remote-SSH, VS Code
will detect the port being used and offer to auto-forward it. No manual SSH
tunnel needed.

### Batch jobs

```bash
# Submit an R script to SLURM
./scripts/sbatch_rscript.sh src/preprocess.R

# With resource overrides
./scripts/sbatch_rscript.sh src/heavy_analysis.R \
    --time=12:00:00 --cpus=32 --mem=256G

# A long pipeline (auto-uses 'long' partition if time > 1 day)
./scripts/sbatch_targets.sh --time=2-0:00:00 --mem=128G

# Python jobs work the same way
./scripts/sbatch_python.sh src/scvelo_run.py --time=8:00:00 --mem=128G
```

### Watching and stopping

```bash
./scripts/status.sh                  # all jobs + tunnels for this project
./scripts/logs.sh 1234567            # tail stdout+stderr of job 1234567
./scripts/logs.sh 1234567 --err      # only stderr
./scripts/logs.sh 1234567 --once     # print and exit

./scripts/stop.sh 1234567            # cancel one job
./scripts/stop.sh rstudio            # cancel all rstudio jobs for this project
./scripts/stop.sh all                # cancel all jobs for this project
```

### Recovering a tunnel after closing your terminal

If you ran `run_rstudio.sh` yesterday, then closed your laptop, then SSH'd
back today — the SLURM job is still running, but you've lost the tunnel
command. Re-print it:

```bash
./scripts/status.sh                          # find the job ID
./scripts/_setup_tunnel.sh <jobid>           # re-prints the tunnel command
```

## Directory layout

```
project/
├── .env                          # per-project config (gitignored)
├── .env.example                  # template
├── .gitignore
├── README.md                     # this file (replace with project-specific docs)
│
├── container/
│   ├── bioinfo.def               # Apptainer recipe (versioned)
│   └── bioinfo.sif               # built image (gitignored, large)
│
├── scripts/
│   ├── _common.sh                # shared helpers, .env loader
│   ├── _setup_tunnel.sh          # re-print tunnel command
│   ├── build_container.sh        # srun-wrapped apptainer build
│   ├── run_rstudio.sh            # interactive RStudio (sbatch + tunnel info)
│   ├── run_jupyter.sh            # interactive Jupyter
│   ├── run_shell.sh              # interactive bash on compute node (srun)
│   ├── sbatch_rscript.sh         # batch R script
│   ├── sbatch_python.sh          # batch Python script
│   ├── sbatch_targets.sh         # batch targets pipeline
│   ├── status.sh                 # jobs + tunnels + container state
│   ├── stop.sh                   # cancel jobs
│   └── logs.sh                   # tail SLURM logs
│
├── slurm/
│   ├── logs/                     # job stdout/stderr (gitignored)
│   └── archive/                  # old logs you want to keep
│
├── R/                            # project R library (bind-mounted, gitignored)
├── src/                          # source code modules
├── notebooks/                    # Quarto .qmd / Jupyter .ipynb
├── analyses/                     # exploratory work
├── data/                         # gitignored
└── results/                      # gitignored
```

## Why this design

**Why does build_container.sh use srun?**
Building an Apptainer image involves apt-get, R package compilation, etc. —
easily uses several GB of RAM. Login nodes are shared and admins kill heavy
processes. Running the build via `srun` means it lands on a compute node
where heavy work is allowed.

**Why do interactive sessions use sbatch instead of srun?**
`srun --pty` would tie the session to your terminal. Closing the terminal
kills the job. Using `sbatch` makes the session a normal background job
that survives terminal closures — you reconnect via SSH tunnel and the
RStudio session is still there. Crucially: closing VS Code or losing wifi
does NOT kill your R session.

**Why /mnt/scratch instead of $HOME?**
On cortex3, `/users` (NFS, where `$HOME` lives) is meant for dotfiles and
small configs. `/mnt/scratch` is the 1.9 PB Lustre filesystem and the
intended location for project data, despite the name "scratch." `$HOME`
quotas would be hit within minutes by a container build.

**Why /tmp for APPTAINER_TMPDIR?**
Each cortex3 node has 11 TB of local NVMe at `/tmp`. Builds happen there
because Lustre's per-file metadata operations are slow; the build process
creates thousands of small files. After build, the .sif is moved to scratch.

**Why bind-mount R/ into the container?**
R packages installed via `install.packages()` go to
`/usr/local/lib/R/site-library` *inside* the container by default. The
container filesystem is read-only at runtime, so those installs would
fail — or if writable, would vanish on container restart. Binding
`<project>/R` to that path means installs persist on Lustre.

**Why per-project port numbers?**
You'll eventually have multiple projects running. If they all use 8787,
they collide on your Mac when tunneling. Pick a project-specific port
range in `.env` and never think about it again.

## Adapting this template for a new project

1. Decide on a unique port range (e.g. project 1 → 8811–8819)
2. Copy the directory under `/mnt/scratch/users/$USER/projects/`
3. Edit `.env` (PROJECT_NAME, port assignments)
4. (Optional) Customize `container/bioinfo.def` if this project needs
   different packages
5. Build the container with `./scripts/build_container.sh`
6. Initialize Git and start working

## Open issues / caveats

- **No SSH multiplexing assumed.** Every `ssh -L` tunnel triggers a fresh
  SSH connection to cortex3. On Ludwig that's instant (key-based auth);
  on BMRC it would re-prompt 2FA. If you adapt this for BMRC, add
  `ControlMaster auto` to your `~/.ssh/config`.

- **Single .sif per project.** If you need conflicting Python dependencies
  for different tools, you'd either need to maintain virtual environments
  inside the container or have multiple .def files. This template assumes
  one .sif per project.

- **GPU work not supported.** cortex3 has no GPUs. For CUDA-based tools
  you'd need a different cluster.

- **No automatic VS Code port forwarding setup.** VS Code does this on its
  own when it detects a listening port, but the popup behavior depends on
  your settings. Look for the "Ports" tab next to the integrated terminal.
