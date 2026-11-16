import GitignoreClaimKit

print("GitignoreClaimKit demo: what answers say about .gitignore, checked with git's own matching rules")
Scenarios.reinclude()
Scenarios.trailingComment()
Scenarios.anchoring()
Scenarios.directories()
Scenarios.tracking()
Scenarios.letterCase()
Scenarios.nested()
await Scenarios.conversation()
