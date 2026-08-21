# Day 03 — Keys and Secrets

**Week:** 00 · **Date:** 2026-08-21 · **Hours:** ~4

Today was all about locking things down before I actually write any real code or build the infrastructure. I wanted to get the security basics completely sorted so I don't accidentally do something stupid later, like committing an API key or hardcoding a password.

## What I actually did

First order of business was getting my SSH keys set up. I ran `ssh-keygen -t ed25519` in the terminal. I purposefully left the passphrase blank for now just to make automation easier while I'm in this prototype stage, though I know I might regret that later if I want to harden the security. The tool generated that weird little ascii randomart image and dumped my private key and public key into my `.ssh` directory. 

I spent a few minutes reading up on why everyone recommends `ed25519` over RSA these days. The consensus seems to be that it uses much shorter keys, it's significantly faster to compute, and it's mathematically more secure than older, massive RSA key sizes. 

That led me down a rabbit hole of solidifying my understanding of why we disable passwords entirely on servers once SSH keys are working. A password is incredibly vulnerable to brute-force attacks — there are basically botnets just hammering port 22 all day across the entire internet. A private key, on the other hand, has 256 bits of pure entropy. Brute-forcing that is mathematically impossible in our lifetime.

After that, I went back to the Gitleaks setup from yesterday. I actually wrote the `.gitleaks.toml` file and dropped it in the root of my repository. The whole plan here is to prevent me from committing any raw secrets to this build log or to any future configuration files. I ended up using a generic regex rule to detect anything that looks like `key`, `secret`, `token`, or `password` followed by a random string of characters.

To make sure it wasn't just sitting there doing nothing, I wrote a dummy test file with a fake API key (`MY_SECRET_TOKEN = "a1b2c3d4e5f6g7h8i9j0"`) and ran a quick scan against it. The config caught the pattern perfectly. It feels good to have that safety net in place before things get messy.

## What confused me

I had a really embarrassing head-scratching moment with the SSH public vs. private keys. I know the theory behind asymmetric cryptography, but I always have to stop and double-check which key goes where. I had to remind myself: the *public* key goes on the server (which I'll be flashing next week), and the *private* key stays securely on my local machine and absolutely *never* leaves.

I also spent way too much time figuring out the best regex for that gitleaks config. If the regex is too broad, it starts flagging completely normal code as a secret, which means you get alert fatigue and start ignoring it. But if it's too narrow, it misses actual leaks. I finally settled on a standard rule that specifically looks for assignments containing common keywords like "token" or "secret" followed by 16 to 40 characters. Hopefully that strikes the right balance.

## Tomorrow

The repository setup. I need to finally build out the full directory layout (`docs/`, `config/`, `scripts/`, etc.) and write the main README.md so the public face of this project is actually ready before the hardware boot happens next week.
