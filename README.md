# migration

### Step 1: Set up key pair (for ssh and github access)
1. run `setup-key.sh` to create key pair.
2. upload public key to github and cloudlab accounts.

### Step 2: Start experiments(`migration-3`) on cloudlab

### Step 3: Upload key pair to m400(`client` in `migration-3`)
1. `./upload-key.sh {username} {client_ip}`

### Step 4: Set up environment (QEMU, SeKVM, etc.)
1. `ssh` to `client`
2. `git clone` this repo on `client`
3. run `setup-env.sh` (or `setup-env-mainline.sh` for mainline KVM/QEMU)

### Step 5: Run migration evalutions
1. check settings in `example-config.sh`
2. * run `eval.sh` with desired config file.
       * for example: `./eval.sh example-config.sh`
   * or use `batch.sh` for multiple configs.
