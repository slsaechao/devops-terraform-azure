add-content -path c:/Users/slsaechao/.ssh/config -value @"
Host ${hostname}
  HostName ${hostname}
  User ${user}
  IdentityFile ${identityfile}
"@
