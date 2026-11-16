// SPDX-License-Identifier: MIT
// Query IPP state numerically: lpstat stays localized on some macOS versions.
#include <cups/cups.h>
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    if (argc != 2) return 1;
    cups_dest_t *destination = cupsGetNamedDest(CUPS_HTTP_DEFAULT, argv[1], NULL);
    if (!destination) { fprintf(stderr,"Cannot query queue: %s\n",cupsLastErrorString()); return 1; }
    const char *value = cupsGetOption("printer-state",destination->num_options,destination->options);
    int state = value ? atoi(value) : 0;
    cupsFreeDests(1,destination);
    if (state == IPP_PSTATE_IDLE || state == IPP_PSTATE_STOPPED) return 0;
    fprintf(stderr,"Queue is processing or its state is unavailable (IPP state %d).\n",state);
    return 1;
}
