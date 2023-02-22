# migration

## Step 1: Set up key pair (for ssh and github access)
1. run `./setup-key.sh` to create key pair.
2. upload public key to github and cloudlab accounts.

## Step 2: Start experiments(`migration-3`) on cloudlab

## Step 3: Upload key pair to m400(`client` in `migration-3`)
1. run `./upload-key.sh`

## Step 4: Set up environment (QEMU, SeKVM, etc.)
1. `ssh` to `client`
2. `git clone` this repo on `client`
3. run `./setup-env.sh`

## Step 5: Run migration evalutions
1. check settings in `eval.sh`
2. check scripts for booting VMs
  (default: `blk.sh`, `resume-blk.sh` in this repo)
3. run `eval.sh` with desired parameters.
