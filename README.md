# migration

### Step 0: Start experiments(`migration-3`) on cloudlab

### Step 1: Set up environment (QEMU, SeKVM, etc.)
0. you may have to setup `ssh-agent` on your machine.
1. `ssh -A` to `client`
2. `git clone` this repo on `client`
3. run `setup-env.sh` (or `setup-env-mainline.sh` for mainline KVM/QEMU)

### Step 2: Run migration evalutions
0. check example configs in `eval_configs/example-config.sh`
1. * run `eval.sh` with desired config file.
       * for example: `./eval.sh eval_configs/example-config.sh`
   * or use `batch.sh` for running multiple configs.
