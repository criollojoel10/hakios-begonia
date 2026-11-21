savedcmd_hakios_ramoops.mod := printf '%s\n'   hakios_ramoops.o | awk '!x[$$0]++ { print("./"$$0) }' > hakios_ramoops.mod
