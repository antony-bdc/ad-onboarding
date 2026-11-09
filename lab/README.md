# Test lab

Everything in this repo is meant to be tried in a throwaway lab domain first.

1. Create a VM with **Windows Server 2022/2025 Evaluation** (free for 180 days from Microsoft), 2 vCPU, 4 GB RAM.
2. `.\lab\New-LabDomain.ps1` installs AD DS and creates `lab.local` (reboots).
3. `.\lab\Initialize-LabStructure.ps1` creates the OUs and groups from `config\provisioning.json`.
4. `Invoke-UserOnboarding -Path .\samples\new-hires.csv -ConfigPath .\config\provisioning.json -WhatIf`, then without `-WhatIf`.

Take a VM snapshot after step 3 so you can reset the lab in seconds.
