#!/usr/bin/env python3
import sys, re, subprocess, pathlib
if len(sys.argv)!=2: print("Usage: update_ollama.py <version>"); sys.exit(1)
VERSION=sys.argv[1]
base=pathlib.Path(__file__).parent
repo=base.parent
flake=repo/'flake.nix'
deriv=base/'ollama-rocm-git.nix'
txt=flake.read_text()
txt=re.sub(r'(ollama-git\s*=\s*{\s*url\s*=\s*")github:ollama/ollama/v[^"]+(")', lambda m:f"{m.group(1)}github:ollama/ollama/v{VERSION}{m.group(2)}", txt)
flake.write_text(txt)
subprocess.run(['nix','flake','update'], cwd=str(repo), check=True)
d=deriv.read_text()
d=re.sub(r'(version\s*=\s*")[^"]+(")', lambda m:f"{m.group(1)}{VERSION}{m.group(2)}", d)
d=re.sub(r"(substituteInPlace version/version\.go --replace-fail 0\.0\.0 ')([^']+)(')", lambda m:f"{m.group(1)}{VERSION}{m.group(3)}", d)
# put a valid but wrong placeholder to force Nix to report the real hash
d=re.sub(r'(llamaCppSrc = pkgs.fetchFromGitHub \{[^}]*tag = llamaCppVersion;\s*hash = )"sha256-[^"]+"', r'\1"sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="', d, flags=re.DOTALL)
deriv.write_text(d)
proc=subprocess.run(['nix','build','.#ollama-rocm-git','--no-link'], cwd=str(repo), capture_output=True, text=True)
out=proc.stdout+proc.stderr
m=re.search(r'hash mismatch.*?got:\s+(sha256-[A-Za-z0-9+/=]+)', out, re.S)
if m:
    real=m.group(1)
    d=deriv.read_text()
    d=re.sub(r'(llamaCppSrc = pkgs.fetchFromGitHub \{[^}]*tag = llamaCppVersion;\s*hash = )"sha256-[^"]+"', rf'\1"{real}"', d, flags=re.DOTALL)
    deriv.write_text(d)
    print(f'updated to {VERSION}, llama hash {real}')
else:
    print(f'updated to {VERSION} - hash already correct')
