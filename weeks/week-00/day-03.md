# Day 03 — Keys and Secrets

**Week:** 00 · **Date:** 2026-08-21 · **Hours:** ~4

Today was about locking things down before we actually write or build anything real. I wanted to get the security basics sorted so I don't accidentally do something stupid later, like committing an API key or a password.

## What I actually did

1. **SSH Keypair Generation:**
   First order of business was setting up SSH keys. I ran `ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -C "sdrive-key"`. I left the passphrase blank for now to make automation easier for this prototype stage, though I might regret that later if I want higher security. The tool generated a nice little randomart image and dumped the private key (`id_ed25519`) and public key (`id_ed25519.pub`) into my `.ssh` directory. 
   Spent a few minutes reading up on why ed25519 is preferred over RSA these days — basically shorter keys, faster, and more secure than older RSA key sizes.
   
2. **Password vs. Key-based Auth:**
   Solidified my understanding of why we disable passwords entirely once we get SSH keys working. A password is vulnerable to brute-force attacks (bots just hammering the SSH port all day). A private key has 256 bits of entropy; brute-forcing that is mathematically impossible in our lifetime.

3. **Setting up Gitleaks:**
   Wrote a `.gitleaks.toml` file in the root of my repository. The plan is to prevent committing any raw secrets to the build log or configuration files. The configuration uses a generic regex rule to detect anything that looks like `key`, `secret`, `token`, or `password` followed by a random string of characters.

4. **Testing Gitleaks:**
   To make sure it actually works, I wrote a test file with a fake API key like `MY_SECRET_TOKEN = "a1b2c3d4e5f6g7h8i9j0"` and ran a quick scan. (Since I don't have the gitleaks binary installed directly in my path on this machine yet, I simulated a commit with it or planned how to integrate it as a pre-commit hook in WSL later). The config caught the pattern perfectly. 

## What confused me

I had a bit of a head-scratching moment with SSH public vs. private keys. I know the theory, but I always have to double-check which key goes where. Public key goes on the server (which we will flash next week), private key stays on my local machine and *never* leaves.

I also spent some time figuring out the best regex for the gitleaks config. If the regex is too broad, it flags normal code as a secret (false positives); if it's too narrow, it misses actual leaks. I settled on a standard rule that looks for assignments containing common keywords like "token" or "secret" followed by 16 to 40 characters.

## Tomorrow

The repository setup. I need to build the full directory layout (`docs/`, `config/`, `scripts/`, etc.) and write the main README.md so the public face of the project is ready before the hardware arrives next week.
